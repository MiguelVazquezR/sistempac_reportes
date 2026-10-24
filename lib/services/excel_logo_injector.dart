import 'dart:math' as math;

import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../core/image_size_reader.dart';
import 'ooxml/ooxml_package.dart';

/// Resultado de intentar insertar el logo en un libro de Excel.
class LogoInjectionResult {
  const LogoInjectionResult({
    required this.bytes,
    required this.injected,
    this.warning,
  });

  final List<int> bytes;

  /// `false` cuando la inyección falló y se devolvieron los bytes originales.
  final bool injected;

  /// Motivo del fallo, para mostrarlo como advertencia al usuario.
  final String? warning;
}

/// Inserta un logo en la primera hoja de un `.xlsx` ya guardado.
///
/// `excel` 4.x no soporta imágenes, así que el logo se agrega manipulando el
/// paquete OOXML (ZIP) directamente:
///
/// * reutiliza el dibujo (`xl/drawings/drawingN.xml`) de la hoja si existe;
/// * elimina las imágenes ancladas en la zona superior (logo genérico del
///   reporte original) conservando los gráficos/curvas;
/// * agrega una nueva imagen anclada en [anchorColumn] y registra las
///   relaciones, el tipo de contenido y el medio en `xl/media/`.
class ExcelLogoInjector {
  const ExcelLogoInjector();

  /// Un píxel equivale a 9525 EMU (96 ppp).
  static const int emuPerPixel = 9525;

  /// Tamaño máximo del logo, en píxeles, para no tapar el reporte.
  static const double maxLogoWidthPixels = 260;
  static const double maxLogoHeightPixels = 80;

  /// Las imágenes ancladas antes de esta fila se consideran logo de plantilla.
  static const int templatePictureRowLimit = 12;

  static const String _drawingNs =
      'http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing';
  static const String _drawingMlNs =
      'http://schemas.openxmlformats.org/drawingml/2006/main';
  static const String _officeRelNs =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
  static const String _drawingRelType =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing';
  static const String _imageRelType =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships/image';
  static const String _drawingContentType =
      'application/vnd.openxmlformats-officedocument.drawing+xml';

  LogoInjectionResult inject(
    List<int> xlsxBytes, {
    required List<int> logoBytes,
    required int anchorColumn,
    int anchorRow = 0,
    bool removeTemplatePictures = true,
  }) {
    try {
      final package = OoxmlPackage.decode(xlsxBytes);
      final sheetPath = _firstWorksheetPath(package);
      if (sheetPath == null) {
        return LogoInjectionResult(
          bytes: xlsxBytes,
          injected: false,
          warning: 'No se encontró la hoja de cálculo dentro del libro; el logo no se insertó.',
        );
      }

      final media = _mediaFor(logoBytes);
      final dimensions =
          ImageSizeReader.read(logoBytes) ?? const ImageDimensions(240, 80);
      final size = _fit(dimensions);
      final mediaPath = 'xl/media/logo.${media.extension}';
      package.writeBytes(mediaPath, logoBytes);

      final drawingPath = _ensureDrawingPart(
        package,
        sheetPath: sheetPath,
        removeTemplatePictures: removeTemplatePictures,
      );
      final relationshipId = _addImageRelationship(
        package,
        drawingPath: drawingPath,
        mediaPath: mediaPath,
      );
      _appendPictureAnchor(
        package,
        drawingPath: drawingPath,
        relationshipId: relationshipId,
        anchorColumn: anchorColumn < 0 ? 0 : anchorColumn,
        anchorRow: anchorRow < 0 ? 0 : anchorRow,
        widthPx: size.$1,
        heightPx: size.$2,
      );
      _ensureContentTypes(
        package,
        mediaExtension: media.extension,
        contentType: media.contentType,
        drawingPath: drawingPath,
      );

      return LogoInjectionResult(bytes: package.encode(), injected: true);
    } catch (error) {
      return LogoInjectionResult(
        bytes: xlsxBytes,
        injected: false,
        warning: 'No se pudo insertar el logo en el Excel: $error',
      );
    }
  }

  (double, double) _fit(ImageDimensions dimensions) {
    if (dimensions.width <= 0 || dimensions.height <= 0) {
      return (200, 60);
    }
    final scale = math.min(
      maxLogoWidthPixels / dimensions.width,
      maxLogoHeightPixels / dimensions.height,
    );
    final safeScale = scale > 1 ? 1.0 : scale;
    final width = math.max(16.0, dimensions.width * safeScale);
    final height = math.max(16.0, dimensions.height * safeScale);
    return (width, height);
  }

  ({String extension, String contentType}) _mediaFor(List<int> logoBytes) {
    final detected = ImageSizeReader.detectExtension(logoBytes) ?? 'png';
    switch (detected) {
      case 'jpg':
        return (extension: 'jpg', contentType: 'image/jpeg');
      case 'gif':
        return (extension: 'gif', contentType: 'image/gif');
      case 'bmp':
        return (extension: 'bmp', contentType: 'image/bmp');
      default:
        return (extension: 'png', contentType: 'image/png');
    }
  }

  // ------------------------------------------------------------------ partes

  String? _firstWorksheetPath(OoxmlPackage package) {
    final workbook = package.readXml('xl/workbook.xml');
    final rels = package.readXml('xl/_rels/workbook.xml.rels');
    if (workbook != null && rels != null) {
      final sheets = workbook.descendantElements
          .where((element) => element.name.local == 'sheet')
          .toList();
      if (sheets.isNotEmpty) {
        final ids = sheets.first.attributes
            .where((attribute) => attribute.name.local == 'id')
            .map((attribute) => attribute.value)
            .toList();
        if (ids.isNotEmpty) {
          final target = _relationshipTarget(rels, ids.first);
          if (target != null) {
            final resolved = _resolvePartPath('xl/workbook.xml', target);
            if (package.contains(resolved)) {
              return resolved;
            }
          }
        }
      }
    }
    if (package.contains('xl/worksheets/sheet1.xml')) {
      return 'xl/worksheets/sheet1.xml';
    }
    final candidates = package.names
        .where(
          (name) => name.startsWith('xl/worksheets/') && name.endsWith('.xml'),
        )
        .toList();
    return candidates.isEmpty ? null : candidates.first;
  }

  static String _resolvePartPath(String fromPart, String target) {
    if (target.startsWith('/')) {
      return target.substring(1);
    }
    final base = p.posix.dirname(fromPart);
    return p.posix.normalize(p.posix.join(base, target));
  }

  static String _relativeTarget(String fromPart, String toPart) {
    final base = p.posix.dirname(fromPart);
    return p.posix.relative(toPart, from: base);
  }

  static String _relationshipsPathFor(String partPath) {
    return p.posix.join(
      p.posix.dirname(partPath),
      '_rels',
      '${p.posix.basename(partPath)}.rels',
    );
  }

  static String? _relationshipTarget(XmlDocument rels, String id) {
    for (final element in rels.descendantElements.where(
      (element) => element.name.local == 'Relationship',
    )) {
      if (element.getAttribute('Id') == id) {
        return element.getAttribute('Target');
      }
    }
    return null;
  }

  ({String id, String target})? _existingDrawingRelationship(
    XmlDocument relationships,
  ) {
    for (final element in relationships.descendantElements.where(
      (element) => element.name.local == 'Relationship',
    )) {
      if (element.getAttribute('Type') != _drawingRelType) {
        continue;
      }
      final id = element.getAttribute('Id');
      final target = element.getAttribute('Target');
      if (id != null && target != null) {
        return (id: id, target: target);
      }
    }
    return null;
  }

  /// Reutiliza el dibujo existente de la hoja o crea uno nuevo.
  String _ensureDrawingPart(
    OoxmlPackage package, {
    required String sheetPath,
    required bool removeTemplatePictures,
  }) {
    final sheet = package.readXml(sheetPath);
    if (sheet == null) {
      throw StateError('La hoja $sheetPath no contiene XML válido.');
    }
    final sheetRelationshipsPath = _relationshipsPathFor(sheetPath);
    final sheetRelationships = package.readXml(sheetRelationshipsPath);

    final drawingElements = sheet.descendantElements
        .where((element) => element.name.local == 'drawing')
        .toList();
    if (drawingElements.isNotEmpty && sheetRelationships != null) {
      final ids = drawingElements.first.attributes
          .where((attribute) => attribute.name.local == 'id')
          .map((attribute) => attribute.value)
          .toList();
      if (ids.isNotEmpty) {
        final target = _relationshipTarget(sheetRelationships, ids.first);
        if (target != null) {
          final existing = _resolvePartPath(sheetPath, target);
          if (package.contains(existing)) {
            if (removeTemplatePictures) {
              _stripTemplatePictures(package, existing);
            }
            return existing;
          }
          // La hoja apunta a un dibujo que no existe: se crea en esa ruta.
          package.writeText(existing, _emptyDrawingXml());
          package.writeText(
            _relationshipsPathFor(existing),
            _emptyRelationshipsXml(),
          );
          return existing;
        }
      }
    }

    // Algunas plantillas traen el dibujo y su relación, pero sin el elemento
    // <drawing> en la hoja: se reutiliza la parte para no dejar huérfanos.
    if (drawingElements.isEmpty && sheetRelationships != null) {
      final reuse = _existingDrawingRelationship(sheetRelationships);
      if (reuse != null) {
        final existing = _resolvePartPath(sheetPath, reuse.target);
        if (package.contains(existing)) {
          if (removeTemplatePictures) {
            _stripTemplatePictures(package, existing);
          }
          _insertDrawingElement(sheet, reuse.id);
          package.writeText(sheetPath, sheet.toXmlString());
          return existing;
        }
      }
    }

    final drawingPath = _unusedDrawingPath(package);
    package.writeText(drawingPath, _emptyDrawingXml());
    package.writeText(
      _relationshipsPathFor(drawingPath),
      _emptyRelationshipsXml(),
    );

    final relationships =
        sheetRelationships ?? XmlDocument.parse(_emptyRelationshipsXml());
    final relationshipId = _nextRelationshipId(relationships);
    relationships.rootElement.children.add(
      XmlElement(XmlName('Relationship'), [
        XmlAttribute(XmlName('Id'), relationshipId),
        XmlAttribute(XmlName('Type'), _drawingRelType),
        XmlAttribute(
          XmlName('Target'),
          _relativeTarget(sheetPath, drawingPath),
        ),
      ]),
    );
    package.writeText(sheetRelationshipsPath, relationships.toXmlString());

    _insertDrawingElement(sheet, relationshipId);
    package.writeText(sheetPath, sheet.toXmlString());
    return drawingPath;
  }

  String _unusedDrawingPath(OoxmlPackage package) {
    for (var index = 1; index < 1000; index++) {
      final candidate = 'xl/drawings/drawing$index.xml';
      if (!package.contains(candidate)) {
        return candidate;
      }
    }
    throw StateError('El libro ya contiene demasiados dibujos.');
  }

  void _insertDrawingElement(XmlDocument sheet, String relationshipId) {
    final worksheets = sheet.descendantElements
        .where((element) => element.name.local == 'worksheet')
        .toList();
    if (worksheets.isEmpty) {
      throw StateError('La hoja no contiene el elemento worksheet.');
    }
    final worksheet = worksheets.first;
    final hasRelNamespace = worksheet.attributes.any(
      (attribute) => attribute.name.local == 'r',
    );
    if (!hasRelNamespace) {
      worksheet.attributes.add(XmlAttribute(XmlName('xmlns:r'), _officeRelNs));
    }

    final drawing = XmlElement(XmlName('drawing'), [
      XmlAttribute(XmlName('r:id'), relationshipId),
    ], []);
    const trailing = [
      'legacyDrawing',
      'picture',
      'oleObjects',
      'controls',
      'webPublishItems',
      'tableParts',
      'extLst',
    ];
    final index = worksheet.children.indexWhere(
      (node) => node is XmlElement && trailing.contains(node.name.local),
    );
    if (index >= 0) {
      worksheet.children.insert(index, drawing);
    } else {
      worksheet.children.add(drawing);
    }
  }

  void _stripTemplatePictures(OoxmlPackage package, String drawingPath) {
    final document = package.readXml(drawingPath);
    if (document == null) {
      return;
    }
    final pictures = document.descendantElements
        .where((element) => element.name.local == 'pic')
        .toList();
    var changed = false;
    for (final picture in pictures) {
      final anchor = _anchorOf(picture);
      if (anchor == null) {
        continue;
      }
      final row = _anchorRow(anchor);
      if (row == null || row >= templatePictureRowLimit) {
        continue;
      }
      anchor.parent?.children.remove(anchor);
      changed = true;
    }
    if (changed) {
      package.writeText(drawingPath, document.toXmlString());
    }
  }

  static const Set<String> _anchorNames = {
    'twoCellAnchor',
    'oneCellAnchor',
    'absoluteAnchor',
  };

  XmlElement? _anchorOf(XmlElement element) {
    XmlNode? node = element.parent;
    while (node != null) {
      if (node is XmlElement && _anchorNames.contains(node.name.local)) {
        return node;
      }
      node = node.parent;
    }
    return null;
  }

  int? _anchorRow(XmlElement anchor) {
    final froms = anchor.descendantElements
        .where((element) => element.name.local == 'from')
        .toList();
    if (froms.isEmpty) {
      return null;
    }
    final rows = froms.first.descendantElements
        .where((element) => element.name.local == 'row')
        .toList();
    if (rows.isEmpty) {
      return null;
    }
    return int.tryParse(rows.first.innerText.trim());
  }

  String _addImageRelationship(
    OoxmlPackage package, {
    required String drawingPath,
    required String mediaPath,
  }) {
    final relationshipsPath = _relationshipsPathFor(drawingPath);
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
          _relativeTarget(drawingPath, mediaPath),
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

  void _appendPictureAnchor(
    OoxmlPackage package, {
    required String drawingPath,
    required String relationshipId,
    required int anchorColumn,
    required int anchorRow,
    required double widthPx,
    required double heightPx,
  }) {
    final document = package.readXml(drawingPath);
    if (document == null) {
      throw StateError('El dibujo $drawingPath no contiene XML válido.');
    }
    final root = document.rootElement;
    final shapeId = _nextShapeId(root);
    final cx = (widthPx * emuPerPixel).round();
    final cy = (heightPx * emuPerPixel).round();
    final anchorXml =
        '''
<xdr:oneCellAnchor xmlns:xdr="$_drawingNs" xmlns:a="$_drawingMlNs" xmlns:r="$_officeRelNs">
  <xdr:from>
    <xdr:col>$anchorColumn</xdr:col>
    <xdr:colOff>0</xdr:colOff>
    <xdr:row>$anchorRow</xdr:row>
    <xdr:rowOff>0</xdr:rowOff>
  </xdr:from>
  <xdr:ext cx="$cx" cy="$cy"/>
  <xdr:pic>
    <xdr:nvPicPr>
      <xdr:cNvPr id="$shapeId" name="Logo empresa" descr="Logo de la empresa"/>
      <xdr:cNvPicPr>
        <a:picLocks noChangeAspect="1"/>
      </xdr:cNvPicPr>
    </xdr:nvPicPr>
    <xdr:blipFill>
      <a:blip r:embed="$relationshipId"/>
      <a:stretch>
        <a:fillRect/>
      </a:stretch>
    </xdr:blipFill>
    <xdr:spPr>
      <a:prstGeom prst="rect">
        <a:avLst/>
      </a:prstGeom>
    </xdr:spPr>
  </xdr:pic>
  <xdr:clientData/>
</xdr:oneCellAnchor>''';
    root.children.add(XmlDocument.parse(anchorXml).rootElement.copy());
    package.writeText(drawingPath, document.toXmlString());
  }

  static int _nextShapeId(XmlElement drawingRoot) {
    var highest = 1;
    for (final element in drawingRoot.descendantElements.where(
      (element) => element.name.local == 'cNvPr',
    )) {
      final value = int.tryParse(element.getAttribute('id') ?? '') ?? 0;
      if (value > highest) {
        highest = value;
      }
    }
    return highest + 1;
  }

  void _ensureContentTypes(
    OoxmlPackage package, {
    required String mediaExtension,
    required String contentType,
    required String drawingPath,
  }) {
    final document = package.readXml('[Content_Types].xml');
    if (document == null) {
      return;
    }
    final root = document.rootElement;
    final extension = mediaExtension.toLowerCase();

    final hasDefault = root.children.whereType<XmlElement>().any(
      (element) =>
          element.name.local == 'Default' &&
          (element.getAttribute('Extension') ?? '').toLowerCase() == extension,
    );
    if (!hasDefault) {
      root.children.add(
        XmlElement(XmlName('Default'), [
          XmlAttribute(XmlName('Extension'), mediaExtension),
          XmlAttribute(XmlName('ContentType'), contentType),
        ]),
      );
    }

    final partName = '/$drawingPath';
    final hasOverride = root.children.whereType<XmlElement>().any(
      (element) =>
          element.name.local == 'Override' &&
          element.getAttribute('PartName') == partName,
    );
    if (!hasOverride) {
      root.children.add(
        XmlElement(XmlName('Override'), [
          XmlAttribute(XmlName('PartName'), partName),
          XmlAttribute(XmlName('ContentType'), _drawingContentType),
        ]),
      );
    }
    package.writeText('[Content_Types].xml', document.toXmlString());
  }

  static String _emptyDrawingXml() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<xdr:wsDr xmlns:xdr="$_drawingNs" xmlns:a="$_drawingMlNs" '
        'xmlns:r="$_officeRelNs"/>';
  }

  static String _emptyRelationshipsXml() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/'
        'relationships"/>';
  }
}
