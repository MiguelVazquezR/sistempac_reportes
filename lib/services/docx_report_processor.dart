import 'dart:math' as math;

import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../core/image_size_reader.dart';
import '../core/report_processing_exception.dart';
import '../models/processing_options.dart';
import 'ooxml/ooxml_package.dart';
import 'translation/translation_service.dart';

/// Analiza y reescribe documentos Word `.docx` de reportes de tensión.
///
/// * Traduce los párrafos del cuerpo, encabezados y pies de página.
/// * Inserta la marca (empresa + título) y el logo en el encabezado para que
///   se repitan en todas las páginas; si el documento no tiene encabezado, la
///   marca se coloca al inicio del cuerpo.
class DocxReportProcessor {
  DocxReportProcessor({TranslationService? translationService})
    : _translation = translationService ?? TranslationService();

  final TranslationService _translation;

  static const String documentPart = 'word/document.xml';

  static const String _wNs =
      'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
  static const String _wpNs =
      'http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing';
  static const String _aNs =
      'http://schemas.openxmlformats.org/drawingml/2006/main';
  static const String _picNs =
      'http://schemas.openxmlformats.org/drawingml/2006/picture';
  static const String _rNs =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
  static const String _imageRelType =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships/image';

  static const double _maxLogoWidthPixels = 260;
  static const double _maxLogoHeightPixels = 80;
  static const int _emuPerPixel = 9525;

  ProcessedReport process({
    required List<int> bytes,
    required String fileName,
    required ProcessingOptions options,
  }) {
    if (bytes.isEmpty) {
      throw ReportProcessingException(
        ReportErrorCode.emptyFile,
        'El archivo está vacío (0 bytes).',
        fileName: p.basename(fileName),
      );
    }

    final OoxmlPackage package;
    try {
      package = OoxmlPackage.decode(bytes);
    } catch (error) {
      throw ReportProcessingException(
        ReportErrorCode.corruptFile,
        'El archivo no es un documento de Word (.docx) válido.',
        hint:
            'Los archivos .doc antiguos deben guardarse como .docx desde Word.',
        fileName: p.basename(fileName),
        cause: error,
      );
    }

    if (!package.contains(documentPart)) {
      throw ReportProcessingException(
        ReportErrorCode.corruptFile,
        'El paquete no contiene el documento principal de Word.',
        hint: 'Guarda el archivo de nuevo como .docx desde Word.',
        fileName: p.basename(fileName),
      );
    }

    final warnings = <String>[];
    var translatedItems = 0;
    var untranslatedItems = 0;

    if (options.translateContent) {
      for (final part in _textParts(package)) {
        final stats = _translatePart(package, part);
        translatedItems += stats.translated;
        untranslatedItems += stats.untranslated;
      }
    }

    var headerPlaced = false;
    var logoPlaced = false;
    String? detail;

    if (options.addBranding || options.hasLogo) {
      final targetPart = _brandingPart(package, warnings);
      if (options.hasLogo && options.replaceLogo) {
        _removeExistingPictures(package, targetPart);
      }
      final inserted = _insertBranding(
        package,
        partPath: targetPart,
        options: options,
        warnings: warnings,
      );
      headerPlaced = inserted.$1;
      logoPlaced = inserted.$2;
      detail = inserted.$3;
    }

    return ProcessedReport(
      bytes: package.encode(),
      warnings: warnings,
      translatedItems: translatedItems,
      untranslatedItems: untranslatedItems,
      branding: BrandingPlacement(
        headerPlaced: headerPlaced,
        logoPlaced: logoPlaced,
        detail: detail,
      ),
    );
  }

  /// Partes con texto visible: cuerpo, encabezados y pies de página.
  List<String> _textParts(OoxmlPackage package) {
    final headerFooter = RegExp(r'^word/(header|footer)\d*\.xml$');
    return package.names
        .where((name) => name == documentPart || headerFooter.hasMatch(name))
        .toList(growable: false);
  }

  ({int translated, int untranslated}) _translatePart(
    OoxmlPackage package,
    String partPath,
  ) {
    final document = package.readXml(partPath);
    if (document == null) {
      return (translated: 0, untranslated: 0);
    }

    var translated = 0;
    var untranslated = 0;
    var dirty = false;

    final paragraphs = document.descendantElements
        .where((element) => element.name.local == 'p')
        .toList(growable: false);

    for (final paragraph in paragraphs) {
      if (_hasStructuralContent(paragraph)) {
        continue;
      }
      final textNodes = paragraph.descendantElements
          .where((element) => element.name.local == 't')
          .toList(growable: false);
      if (textNodes.isEmpty) {
        continue;
      }
      final original = textNodes.map((node) => node.innerText).join();
      if (original.trim().isEmpty) {
        continue;
      }
      final outcome = _translation.translate(original);
      if (!outcome.changed) {
        if (outcome.untranslatedCjk) {
          untranslated++;
        }
        continue;
      }
      _setNodeText(textNodes.first, outcome.text);
      for (final node in textNodes.skip(1)) {
        _setNodeText(node, '');
      }
      translated++;
      dirty = true;
    }

    if (dirty) {
      package.writeText(partPath, document.toXmlString());
    }
    return (translated: translated, untranslated: untranslated);
  }

  /// Evita tocar párrafos con imágenes, campos o tabulaciones, donde reemplazar
  /// el texto podría destruir contenido.
  static const Set<String> _protectedElements = {
    'drawing',
    'pict',
    'object',
    'fldSimple',
    'instrText',
    'footnoteReference',
    'endnoteReference',
    'sdt',
    'tab',
    'br',
    'sym',
  };

  bool _hasStructuralContent(XmlElement paragraph) {
    return paragraph.descendantElements.any(
      (element) => _protectedElements.contains(element.name.local),
    );
  }

  static void _setNodeText(XmlElement node, String text) {
    node.children
      ..clear()
      ..add(XmlText(text));
    node.setAttribute('xml:space', 'preserve');
  }

  /// Encabezado donde se estampa la marca, o el cuerpo si no existe.
  String _brandingPart(OoxmlPackage package, List<String> warnings) {
    final headers =
        package.names
            .where((name) => RegExp(r'^word/header\d*\.xml$').hasMatch(name))
            .toList()
          ..sort();
    if (headers.isNotEmpty) {
      return headers.first;
    }
    warnings.add(
      'El documento no tiene encabezado configurado: la marca se insertó al '
      'inicio del cuerpo y solo se verá en la primera página.',
    );
    return documentPart;
  }

  (bool headerPlaced, bool logoPlaced, String? detail) _insertBranding(
    OoxmlPackage package, {
    required String partPath,
    required ProcessingOptions options,
    required List<String> warnings,
  }) {
    final document = package.readXml(partPath);
    if (document == null) {
      warnings.add(
        'No se pudo abrir la parte $partPath para insertar la marca.',
      );
      return (false, false, null);
    }
    final container = _contentContainer(document);
    if (container == null) {
      warnings.add(
        'La parte $partPath no tiene un contenedor de contenido válido.',
      );
      return (false, false, null);
    }

    final lines = options.brandingLines;
    var logoPlaced = false;
    var insertAt = 0;

    for (var index = 0; index < lines.length; index++) {
      final paragraph = XmlDocument.parse(
        _brandingParagraphXml(lines[index], primary: index == 0),
      ).rootElement.copy();
      container.children.insert(insertAt, paragraph);
      insertAt++;
    }

    if (options.hasLogo) {
      final logoParagraph = _buildLogoParagraph(package, partPath, options);
      if (logoParagraph != null) {
        container.children.insert(
          insertAt,
          XmlDocument.parse(logoParagraph).rootElement.copy(),
        );
        logoPlaced = true;
        insertAt++;
      }
    }

    package.writeText(partPath, document.toXmlString());
    return (
      lines.isNotEmpty || logoPlaced,
      logoPlaced,
      lines.isEmpty
          ? null
          : 'Marca agregada en ${partPath.startsWith('word/header') ? 'el encabezado' : 'el inicio del cuerpo'}.',
    );
  }

  XmlElement? _contentContainer(XmlDocument document) {
    final body = document.descendantElements
        .where((element) => element.name.local == 'body')
        .toList();
    if (body.isNotEmpty) {
      return body.first;
    }
    final roots = document.descendantElements
        .where(
          (element) =>
              element.name.local == 'hdr' || element.name.local == 'ftr',
        )
        .toList();
    return roots.isEmpty ? document.rootElement : roots.first;
  }

  /// Quita el logo de plantilla para no duplicar imágenes.
  ///
  /// En encabezados se eliminan todas las imágenes; en el cuerpo solo las de
  /// los primeros párrafos (zona de título). Los gráficos se conservan.
  void _removeExistingPictures(OoxmlPackage package, String partPath) {
    final document = package.readXml(partPath);
    if (document == null) {
      return;
    }
    final container = _contentContainer(document);
    if (container == null) {
      return;
    }
    final isHeader = partPath != documentPart;
    var paragraphsSeen = 0;
    var changed = false;

    for (final child in container.children.whereType<XmlElement>().toList(
      growable: false,
    )) {
      if (child.name.local != 'p') {
        continue;
      }
      if (!isHeader && paragraphsSeen >= 10) {
        break;
      }
      paragraphsSeen++;
      final drawings = child.descendantElements
          .where((element) => element.name.local == 'drawing')
          .toList(growable: false);
      for (final drawing in drawings) {
        final isPicture = drawing.descendantElements.any(
          (element) => element.name.local == 'pic',
        );
        if (!isPicture) {
          continue;
        }
        drawing.parent?.children.remove(drawing);
        changed = true;
      }
    }

    if (changed) {
      package.writeText(partPath, document.toXmlString());
    }
  }

  static String _brandingParagraphXml(String text, {required bool primary}) {
    final size = primary ? 32 : 24;
    return '<w:p xmlns:w="$_wNs">'
        '<w:pPr><w:jc w:val="center"/></w:pPr>'
        '<w:r>'
        '<w:rPr><w:b/><w:sz w:val="$size"/><w:color w:val="1F3864"/></w:rPr>'
        '<w:t xml:space="preserve">${_escapeXml(text)}</w:t>'
        '</w:r>'
        '</w:p>';
  }

  String? _buildLogoParagraph(
    OoxmlPackage package,
    String partPath,
    ProcessingOptions options,
  ) {
    final logoBytes = options.logoBytes;
    if (logoBytes == null || logoBytes.isEmpty) {
      return null;
    }

    final detected = ImageSizeReader.detectExtension(logoBytes) ?? 'png';
    final extension = detected == 'jpg' ? 'jpeg' : detected;
    final contentType = switch (detected) {
      'jpg' => 'image/jpeg',
      'gif' => 'image/gif',
      'bmp' => 'image/bmp',
      _ => 'image/png',
    };

    final mediaPath = 'word/media/logo.$extension';
    package.writeBytes(mediaPath, logoBytes);
    _ensureImageContentType(package, extension, contentType);
    final relationshipId = _ensureImageRelationship(
      package,
      partPath,
      mediaPath,
    );

    final dimensions =
        ImageSizeReader.read(logoBytes) ?? const ImageDimensions(240, 80);
    final size = _fitLogo(dimensions);
    final cx = (size.$1 * _emuPerPixel).round();
    final cy = (size.$2 * _emuPerPixel).round();
    final shapeId = _nextShapeId(package, partPath);

    return '<w:p xmlns:w="$_wNs" xmlns:wp="$_wpNs" xmlns:a="$_aNs" '
        'xmlns:pic="$_picNs" xmlns:r="$_rNs">'
        '<w:pPr><w:jc w:val="right"/></w:pPr>'
        '<w:r><w:drawing>'
        '<wp:inline distT="0" distB="0" distL="0" distR="0">'
        '<wp:extent cx="$cx" cy="$cy"/>'
        '<wp:effectExtent l="0" t="0" r="0" b="0"/>'
        '<wp:docPr id="$shapeId" name="Logo empresa"/>'
        '<wp:cNvGraphicFramePr>'
        '<a:graphicFrameLocks noChangeAspect="1"/>'
        '</wp:cNvGraphicFramePr>'
        '<a:graphic><a:graphicData uri="$_picNs"><pic:pic>'
        '<pic:nvPicPr>'
        '<pic:cNvPr id="$shapeId" name="logo.$extension"/>'
        '<pic:cNvPicPr/>'
        '</pic:nvPicPr>'
        '<pic:blipFill>'
        '<a:blip r:embed="$relationshipId"/>'
        '<a:stretch><a:fillRect/></a:stretch>'
        '</pic:blipFill>'
        '<pic:spPr>'
        '<a:xfrm><a:off x="0" y="0"/><a:ext cx="$cx" cy="$cy"/></a:xfrm>'
        '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom>'
        '</pic:spPr>'
        '</pic:pic></a:graphicData></a:graphic>'
        '</wp:inline>'
        '</w:drawing></w:r>'
        '</w:p>';
  }

  (double, double) _fitLogo(ImageDimensions dimensions) {
    if (dimensions.width <= 0 || dimensions.height <= 0) {
      return (200, 60);
    }
    final scale = math.min(
      _maxLogoWidthPixels / dimensions.width,
      _maxLogoHeightPixels / dimensions.height,
    );
    final safeScale = scale > 1 ? 1.0 : scale;
    return (
      math.max(16.0, dimensions.width * safeScale),
      math.max(16.0, dimensions.height * safeScale),
    );
  }

  String _ensureImageRelationship(
    OoxmlPackage package,
    String partPath,
    String mediaPath,
  ) {
    final relationshipsPath = OoxmlPackage.relationshipsPathFor(partPath);
    final relationships =
        package.readXml(relationshipsPath) ??
        XmlDocument.parse(_emptyRelationshipsXml());
    final relationshipId = _nextRelationshipId(relationships);
    relationships.rootElement.children.add(
      XmlElement(XmlName('Relationship'), [
        XmlAttribute(XmlName('Id'), relationshipId),
        XmlAttribute(XmlName('Type'), _imageRelType),
        XmlAttribute(
          XmlName('Target'),
          OoxmlPackage.relativeTarget(partPath, mediaPath),
        ),
      ]),
    );
    package.writeText(relationshipsPath, relationships.toXmlString());
    return relationshipId;
  }

  static String _nextRelationshipId(XmlDocument relationships) {
    var highest = 0;
    for (final element in relationships.descendantElements.where(
      (element) => element.name.local == 'Relationship',
    )) {
      final id = element.getAttribute('Id') ?? '';
      final match = RegExp(r'(\d+)\s*$').firstMatch(id);
      if (match != null) {
        final value = int.tryParse(match.group(1)!) ?? 0;
        if (value > highest) {
          highest = value;
        }
      }
    }
    return 'rId${highest + 1}';
  }

  static int _nextShapeId(OoxmlPackage package, String partPath) {
    final document = package.readXml(partPath);
    var highest = 0;
    if (document != null) {
      for (final element in document.descendantElements.where(
        (element) =>
            element.name.local == 'docPr' || element.name.local == 'cNvPr',
      )) {
        final value = int.tryParse(element.getAttribute('id') ?? '') ?? 0;
        if (value > highest) {
          highest = value;
        }
      }
    }
    return highest + 1;
  }

  void _ensureImageContentType(
    OoxmlPackage package,
    String extension,
    String contentType,
  ) {
    final document = package.readXml('[Content_Types].xml');
    if (document == null) {
      return;
    }
    final root = document.rootElement;
    final normalized = extension.toLowerCase();
    final hasDefault = root.children.whereType<XmlElement>().any(
      (element) =>
          element.name.local == 'Default' &&
          (element.getAttribute('Extension') ?? '').toLowerCase() == normalized,
    );
    if (hasDefault) {
      return;
    }
    root.children.add(
      XmlElement(XmlName('Default'), [
        XmlAttribute(XmlName('Extension'), extension),
        XmlAttribute(XmlName('ContentType'), contentType),
      ]),
    );
    package.writeText('[Content_Types].xml', document.toXmlString());
  }

  static String _emptyRelationshipsXml() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/'
        'relationships"/>';
  }

  static String _escapeXml(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}
