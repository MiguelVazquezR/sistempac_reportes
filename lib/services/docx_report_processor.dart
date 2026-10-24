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

  static const String _reportTitle = 'Reporte de ensayo';

  static final RegExp _folioPattern = RegExp(
    r'^[A-Za-z]{2,8}[-_ ]?\d{2,}(?:[-_][A-Za-z0-9]+)*$',
  );

  static const Set<String> _reportTitleVariants = {
    'reporte de ensayo',
    'reporte de ensayo de traccion',
    'reporte de ensayo de tracción',
    'reporte de prueba',
    'reporte de prueba de tension',
    'reporte de prueba de tensión',
    'reporte de prueba de traccion',
    'reporte de prueba de tracción',
    'reporte de tension',
    'reporte de tensión',
    'reporte de traccion',
    'reporte de tracción',
    'reporte de inspeccion',
    'reporte de inspección',
    'reporte de inspeccion de calidad',
    'reporte de inspección de calidad',
    'tensile test report',
    'tension test report',
    'test report',
    'material test report',
    'inspection report',
    'quality inspection report',
    '试验报告',
    '测试报告',
    '拉伸试验报告',
    '拉力试验报告',
    '拉伸测试报告',
    '拉力测试报告',
    '检测报告',
    '检验报告',
    '品质检验报告',
    '材料试验报告',
    '材料测试报告',
  };

  static const Map<String, String> _templateLabels = {
    'test type': 'Tipo de prueba',
    'tipo de prueba': 'Tipo de prueba',
    'tipo de ensayo': 'Tipo de prueba',
    '测试类型': 'Tipo de prueba',
    '试验类型': 'Tipo de prueba',
    'mat.name': 'Nombre material',
    'mat. name': 'Nombre material',
    'material name': 'Nombre material',
    'nombre material': 'Nombre material',
    'nombre de material': 'Nombre material',
    'nombre del material': 'Nombre material',
    '材料名称': 'Nombre material',
    'mat.type': 'Tipo material',
    'mat. type': 'Tipo material',
    'material type': 'Tipo material',
    'tipo material': 'Tipo material',
    'tipo de material': 'Tipo material',
    '材料类型': 'Tipo material',
    'test for': 'Prueba para',
    'prueba para': 'Prueba para',
    '测试用途': 'Prueba para',
    '试验用途': 'Prueba para',
    'humi': 'Humedad',
    'humedad': 'Humedad',
    '湿度': 'Humedad',
    'lo': 'Longitud',
    'longitud': 'Longitud',
    '长度': 'Longitud',
    'comment': 'Comentario',
    'comments': 'Comentarios',
    'comentario': 'Comentario',
    'comentarios': 'Comentarios',
    '备注': 'Comentario',
    '说明': 'Comentario',
  };

  static const Set<String> _signatureLabels = {
    'assessor',
    'evaluador',
    'ratifier',
    'ratificador',
    'test person',
    'technician',
    'tester',
    'inspector',
    'técnico de prueba',
    'técnico de pruebas',
    'técnico de ensayo',
    'persona de prueba',
    '检验员',
    '测试员',
    '试验员',
  };

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

    _normalizeReportLayout(package);

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

  static bool _hasStructuralContent(XmlElement paragraph) {
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

  /// Corrige la plantilla del reporte: encabezado, etiquetas y espacios.
  void _normalizeReportLayout(OoxmlPackage package) {
    final document = package.readXml(documentPart);
    if (document == null) {
      return;
    }

    final infoTable = _findInfoTable(document);
    if (infoTable == null) {
      return;
    }
    final templateTable = _topLevelTableOf(infoTable);
    if (templateTable == null) {
      return;
    }

    var changed = false;
    final title = _findTemplateTitle(templateTable, infoTable);
    changed |= _removeSpecialTemplateRows(
      templateTable,
      infoTable: infoTable,
      title: title,
    );
    changed |= _clearSignatureLabels(templateTable);

    if (title != null) {
      changed |= _replaceParagraphText(title, _reportTitle);
      changed |= _removeRowsBetweenTitleAndInfo(title, infoTable);
    }

    changed |= _replaceTemplateLabels(templateTable);
    changed |= _trimResultRows(templateTable);

    if (changed) {
      package.writeText(documentPart, document.toXmlString());
    }
  }

  static XmlElement? _findInfoTable(XmlDocument document) {
    final candidates = document.descendantElements
        .where(
          (element) => element.name.local == 'tbl' && _isInfoTable(element),
        )
        .toList(growable: false);
    if (candidates.isEmpty) {
      return null;
    }
    final sorted = candidates.toList(growable: false)
      ..sort(
        (left, right) => left.descendantElements.length.compareTo(
          right.descendantElements.length,
        ),
      );
    return sorted.first;
  }

  static bool _isInfoTable(XmlElement table) {
    final text = _normalizeLabel(_elementText(table));
    final hasType =
        text.contains('test type') ||
        text.contains('tipo de prueba') ||
        text.contains('tipo de ensayo') ||
        text.contains('测试类型') ||
        text.contains('试验类型');
    final hasMaterial =
        text.contains('mat.name') ||
        text.contains('mat. name') ||
        text.contains('material name') ||
        text.contains('nombre material') ||
        text.contains('nombre de material') ||
        text.contains('nombre del material') ||
        text.contains('材料名称') ||
        text.contains('mat.type') ||
        text.contains('mat. type') ||
        text.contains('material type') ||
        text.contains('tipo material') ||
        text.contains('tipo de material') ||
        text.contains('材料类型');
    return hasType && hasMaterial;
  }

  /// Tabla superior que contiene [element], aunque esté dentro de tablas
  /// anidadas. Devuelve `null` si el elemento no está dentro de una tabla.
  static XmlElement? _topLevelTableOf(XmlElement element) {
    XmlElement? top;
    XmlNode? current = element;
    while (current != null) {
      if (current is XmlElement && current.name.local == 'tbl') {
        top = current;
      }
      current = current.parent;
    }
    return top;
  }

  /// Fila de la tabla superior que contiene [element].
  static XmlElement? _topLevelRowOf(XmlElement element) {
    XmlNode? current = element;
    while (current != null) {
      if (current is XmlElement && current.name.local == 'tr') {
        final parent = current.parent;
        if (parent is XmlElement &&
            parent.name.local == 'tbl' &&
            _topLevelTableOf(parent) == parent) {
          return current;
        }
      }
      current = current.parent;
    }
    return null;
  }

  static List<XmlElement> _directChildren(XmlElement parent, String localName) {
    return parent.children
        .whereType<XmlElement>()
        .where((element) => element.name.local == localName)
        .toList(growable: false);
  }

  static String _elementText(XmlElement element) {
    return element.descendantElements
        .where((child) => child.name.local == 't')
        .map((child) => child.innerText)
        .join();
  }

  static String _normalizeLabel(String value) {
    return value
        .replaceAll('\u00A0', ' ')
        .replaceAll('\u3000', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toLowerCase()
        .replaceFirst(RegExp(r'[:：]\s*$'), '')
        .trim();
  }

  static List<String> _rowCellTexts(XmlElement row) {
    return _directChildren(row, 'tc')
        .map((cell) => _elementText(cell).trim())
        .where((text) => text.isNotEmpty)
        .toList(growable: false);
  }

  static bool _rowHasVisibleContent(XmlElement row) {
    if (_elementText(row).trim().isNotEmpty) {
      return true;
    }
    return row.descendantElements.any(
      (element) =>
          element.name.local == 'drawing' ||
          element.name.local == 'pict' ||
          element.name.local == 'object',
    );
  }

  static bool _isFolioText(String text) {
    final trimmed = text.trim();
    return trimmed.isNotEmpty &&
        trimmed.length <= 32 &&
        _folioPattern.hasMatch(trimmed);
  }

  static bool _isSignatureText(String text) {
    final normalized = _normalizeLabel(text);
    final label = normalized.split(RegExp(r'[:：]')).first.trim();
    return _signatureLabels.contains(label);
  }

  bool _removeSpecialTemplateRows(
    XmlElement templateTable, {
    required XmlElement infoTable,
    required XmlElement? title,
  }) {
    var changed = false;
    final rows = _directChildren(templateTable, 'tr');
    final titleRow = title == null ? null : _topLevelRowOf(title);
    final infoRow = _topLevelRowOf(infoTable);
    final titleIndex = titleRow == null ? -1 : rows.indexOf(titleRow);
    final infoIndex = infoRow == null ? -1 : rows.indexOf(infoRow);

    for (var index = 0; index < rows.length; index++) {
      final row = rows[index];
      final texts = _rowCellTexts(row);
      if (texts.isEmpty) {
        continue;
      }
      final allFolio =
          texts.every(_isFolioText) && (titleIndex < 0 || index < titleIndex);
      final allSignature =
          texts.every(_isSignatureText) && (infoIndex < 0 || index > infoIndex);
      if (!allFolio && !allSignature) {
        continue;
      }
      if (_removeRowAndEmptyMerges(row)) {
        changed = true;
      } else if (_clearRowContent(row)) {
        changed = true;
      }
    }
    return changed;
  }

  /// Columnas (por índice de celda) que reinician una combinación vertical.
  static Set<int> _verticalMergeColumns(
    XmlElement row, {
    required bool restart,
  }) {
    final columns = <int>{};
    final cells = _directChildren(row, 'tc');
    for (var index = 0; index < cells.length; index++) {
      final properties = _directChildren(cells[index], 'tcPr');
      if (properties.isEmpty) {
        continue;
      }
      final merges = _directChildren(properties.first, 'vMerge');
      if (merges.isEmpty) {
        continue;
      }
      String? value;
      for (final attribute in merges.first.attributes) {
        if (attribute.name.local == 'val' &&
            attribute.name.namespaceUri == _wNs) {
          value = attribute.value;
          break;
        }
      }
      final isRestart = value == 'restart';
      if ((restart && isRestart) || (!restart && !isRestart)) {
        columns.add(index);
      }
    }
    return columns;
  }

  static List<XmlElement>? _followingEmptyMergeContinuations(
    List<XmlElement> rows,
    int index,
    Set<int> restartColumns,
  ) {
    final result = <XmlElement>[];
    for (var next = index + 1; next < rows.length; next++) {
      final continuation = _verticalMergeColumns(rows[next], restart: false);
      final shared = continuation.intersection(restartColumns);
      if (shared.isEmpty) {
        break;
      }
      if (!restartColumns.every(continuation.contains)) {
        return null;
      }
      if (_rowHasVisibleContent(rows[next])) {
        return null;
      }
      result.add(rows[next]);
    }
    return result;
  }

  static bool _removeRow(XmlElement row) {
    final parent = row.parent;
    if (parent is! XmlElement || parent.name.local != 'tbl') {
      return false;
    }
    final rows = _directChildren(parent, 'tr');
    if (rows.length <= 1) {
      return false;
    }
    parent.children.remove(row);
    return true;
  }

  /// Elimina la fila y sus filas de continuación `vMerge` vacías.
  static bool _removeRowAndEmptyMerges(XmlElement row) {
    final parent = row.parent;
    if (parent is! XmlElement || parent.name.local != 'tbl') {
      return false;
    }
    final rows = _directChildren(parent, 'tr');
    final index = rows.indexOf(row);
    if (index < 0 || rows.length <= 1) {
      return false;
    }

    final toRemove = <XmlElement>[row];
    final restartColumns = _verticalMergeColumns(row, restart: true);
    if (restartColumns.isNotEmpty) {
      final continuations = _followingEmptyMergeContinuations(
        rows,
        index,
        restartColumns,
      );
      if (continuations == null) {
        return false;
      }
      toRemove.addAll(continuations);
    }
    if (rows.length - toRemove.length < 1) {
      return false;
    }
    for (final target in toRemove) {
      parent.children.remove(target);
    }
    return true;
  }

  static bool _canRemoveFromParent(XmlElement element) {
    final parent = element.parent;
    if (parent is! XmlElement) {
      return false;
    }
    if (parent.name.local != 'tc') {
      return true;
    }
    return _directChildren(parent, 'p').isNotEmpty;
  }

  static bool _clearParagraphText(XmlElement paragraph) {
    var changed = false;
    final textNodes = paragraph.descendantElements
        .where((element) => element.name.local == 't')
        .toList(growable: false);
    for (final node in textNodes) {
      if (node.innerText.isNotEmpty) {
        _setNodeText(node, '');
        changed = true;
      }
    }
    return changed;
  }

  static bool _clearRowContent(XmlElement row) {
    var changed = false;
    final visuals = row.descendantElements
        .where(
          (element) =>
              element.name.local == 'drawing' ||
              element.name.local == 'pict' ||
              element.name.local == 'object',
        )
        .toList(growable: false);
    for (final visual in visuals) {
      if (_canRemoveFromParent(visual)) {
        visual.parent?.children.remove(visual);
        changed = true;
      }
    }
    final nestedTables = row.descendantElements
        .where((element) => element.name.local == 'tbl')
        .toList(growable: false);
    for (final table in nestedTables) {
      if (_canRemoveFromParent(table)) {
        table.parent?.children.remove(table);
        changed = true;
      }
    }
    final paragraphs = row.descendantElements
        .where((element) => element.name.local == 'p')
        .toList(growable: false);
    for (final paragraph in paragraphs) {
      if (_clearParagraphText(paragraph)) {
        changed = true;
      }
    }
    return changed;
  }

  bool _clearSignatureLabels(XmlElement templateTable) {
    var changed = false;
    final rows = _directChildren(templateTable, 'tr');
    for (final row in rows) {
      final texts = _rowCellTexts(row);
      if (texts.isEmpty) {
        continue;
      }
      final allSignature = texts.every(_isSignatureText);
      if (allSignature && _clearRowContent(row)) {
        changed = true;
      }
    }
    return changed;
  }

  static bool _replaceParagraphText(XmlElement paragraph, String replacement) {
    final textNodes = paragraph.descendantElements
        .where((element) => element.name.local == 't')
        .toList(growable: false);
    if (textNodes.isEmpty) {
      return false;
    }
    final current = textNodes.map((node) => node.innerText).join();
    if (current == replacement) {
      return false;
    }
    _setNodeText(textNodes.first, replacement);
    for (final node in textNodes.skip(1)) {
      _setNodeText(node, '');
    }
    return true;
  }

  /// Primer párrafo con un título conocido antes de la tabla de información.
  static XmlElement? _findTemplateTitle(
    XmlElement templateTable,
    XmlElement infoTable,
  ) {
    final paragraphs = templateTable.descendantElements
        .where((element) => element.name.local == 'p')
        .toList(growable: false);
    final infoParagraphs = infoTable.descendantElements
        .where((element) => element.name.local == 'p')
        .toList(growable: false);
    if (infoParagraphs.isEmpty) {
      return null;
    }
    final infoStart = paragraphs.indexOf(infoParagraphs.first);
    if (infoStart < 0) {
      return null;
    }
    for (var index = 0; index < infoStart; index++) {
      final paragraph = paragraphs[index];
      if (_hasStructuralContent(paragraph)) {
        continue;
      }
      final normalized = _normalizeLabel(_elementText(paragraph));
      if (_reportTitleVariants.contains(normalized)) {
        return paragraph;
      }
    }
    return null;
  }

  /// Elimina las filas con texto entre el título y la tabla de información.
  static bool _removeRowsBetweenTitleAndInfo(
    XmlElement titleParagraph,
    XmlElement infoTable,
  ) {
    final titleRow = _topLevelRowOf(titleParagraph);
    final infoRow = _topLevelRowOf(infoTable);
    if (titleRow == null ||
        infoRow == null ||
        titleRow.parent != infoRow.parent) {
      return false;
    }
    final table = titleRow.parent;
    if (table is! XmlElement) {
      return false;
    }
    final rows = _directChildren(table, 'tr');
    final start = rows.indexOf(titleRow);
    final end = rows.indexOf(infoRow);
    if (start < 0 || end <= start) {
      return false;
    }

    var changed = false;
    for (var index = end - 1; index > start; index--) {
      final row = rows[index];
      final hasText = _rowCellTexts(row).isNotEmpty;
      final hasVisible = _rowHasVisibleContent(row);
      if (!hasText && hasVisible) {
        continue;
      }
      if (_removeRowAndEmptyMerges(row)) {
        changed = true;
      } else if (hasText && _clearRowContent(row)) {
        changed = true;
      }
    }
    return changed;
  }

  bool _replaceTemplateLabels(XmlElement templateTable) {
    var changed = false;
    final paragraphs = templateTable.descendantElements
        .where((element) => element.name.local == 'p')
        .toList(growable: false);
    for (final paragraph in paragraphs) {
      if (_hasStructuralContent(paragraph)) {
        continue;
      }
      final text = _elementText(paragraph);
      final trimmed = text.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final hasColon = RegExp(r'[:：]\s*$').hasMatch(trimmed);
      final replacement = _templateLabels[_normalizeLabel(trimmed)];
      if (replacement == null) {
        continue;
      }
      final desired = hasColon ? '$replacement:' : replacement;
      if (_replaceParagraphText(paragraph, desired)) {
        changed = true;
      }
    }
    return changed;
  }

  static bool _isResultsTable(XmlElement table) {
    final rows = _directChildren(table, 'tr');
    if (rows.length < 2) {
      return false;
    }
    final header = _normalizeLabel(_elementText(rows.first));
    final hasNumber =
        header.contains('num') ||
        header.contains('no.') ||
        header.contains('n.º') ||
        header.contains('序号') ||
        header.contains('编号');
    if (!hasNumber) {
      return false;
    }
    final hasMetric =
        header.contains('area') ||
        header.contains('área') ||
        header.contains('面积') ||
        header.contains('fmax') ||
        header.contains('stress') ||
        header.contains('esfuerzo') ||
        header.contains('elong') ||
        header.contains('alargamiento') ||
        header.contains('伸长') ||
        header.contains('lmax') ||
        header.contains('截面积') ||
        header.contains('最大力') ||
        header.contains('强度') ||
        header.contains('拉力');
    return hasMetric || _directChildren(rows.first, 'tc').length >= 3;
  }

  static XmlElement? _findStatsTable(XmlElement templateTable) {
    final tables = templateTable.descendantElements
        .where((element) => element.name.local == 'tbl')
        .toList(growable: false);
    for (final table in tables) {
      final rows = _directChildren(table, 'tr');
      if (rows.length < 2) {
        continue;
      }
      final header = _normalizeLabel(_elementText(rows.first));
      if (header.contains('avg') ||
          header.contains('average') ||
          header.contains('mean') ||
          header.contains('media') ||
          header.contains('promedio') ||
          header.contains('平均')) {
        return table;
      }
    }
    return null;
  }

  static bool _trimTrailingEmptyRows(XmlElement table) {
    final rows = _directChildren(table, 'tr');
    if (rows.length <= 1) {
      return false;
    }
    var lastWithContent = rows.length - 1;
    while (lastWithContent >= 1 &&
        !_rowHasVisibleContent(rows[lastWithContent])) {
      lastWithContent--;
    }
    if (lastWithContent == rows.length - 1) {
      return false;
    }
    var changed = false;
    for (var index = rows.length - 1; index > lastWithContent; index--) {
      if (_removeRow(rows[index])) {
        changed = true;
      }
    }
    return changed;
  }

  static bool _removeEmptyRowsBetween(
    XmlElement resultsTable,
    XmlElement statsTable,
  ) {
    final resultsRow = _topLevelRowOf(resultsTable);
    final statsRow = _topLevelRowOf(statsTable);
    if (resultsRow == null || statsRow == null) {
      return false;
    }
    final parent = resultsRow.parent;
    if (parent is! XmlElement ||
        parent.name.local != 'tbl' ||
        statsRow.parent != parent) {
      return false;
    }
    final rows = _directChildren(parent, 'tr');
    final start = rows.indexOf(resultsRow);
    final end = rows.indexOf(statsRow);
    if (start < 0 || end <= start) {
      return false;
    }
    var changed = false;
    for (var index = end - 1; index > start; index--) {
      final row = rows[index];
      if (_rowHasVisibleContent(row)) {
        continue;
      }
      if (_removeRowAndEmptyMerges(row)) {
        changed = true;
      }
    }
    return changed;
  }

  bool _trimResultRows(XmlElement templateTable) {
    var changed = false;
    final resultsTables = templateTable.descendantElements
        .where(
          (element) => element.name.local == 'tbl' && _isResultsTable(element),
        )
        .toList(growable: false);
    for (final table in resultsTables) {
      if (_trimTrailingEmptyRows(table)) {
        changed = true;
      }
    }
    final statsTable = _findStatsTable(templateTable);
    if (statsTable == null) {
      return changed;
    }
    for (final resultsTable in resultsTables) {
      if (_removeEmptyRowsBetween(resultsTable, statsTable)) {
        changed = true;
      }
    }
    return changed;
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
