import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:xml/xml.dart';

/// Utilidades para construir archivos OOXML sintéticos en las pruebas.

List<int> _uint32(int value) => [
  (value >> 24) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 8) & 0xFF,
  value & 0xFF,
];

List<int> _pngChunk(String type, List<int> data) {
  final payload = [...ascii.encode(type), ...data];
  final crc = getCrc32(payload);
  return [..._uint32(data.length), ...payload, ..._uint32(crc)];
}

/// PNG RGBA válido del tamaño indicado (para probar el lector de dimensiones).
Uint8List buildPng({int width = 120, int height = 40}) {
  final raw = <int>[];
  for (var y = 0; y < height; y++) {
    raw.add(0);
    for (var x = 0; x < width; x++) {
      raw.addAll([31, 56, 100, 255]);
    }
  }
  final idat = ZLibEncoder().encode(raw);
  return Uint8List.fromList([
    137,
    80,
    78,
    71,
    13,
    10,
    26,
    10,
    ..._pngChunk('IHDR', [
      ..._uint32(width),
      ..._uint32(height),
      8,
      6,
      0,
      0,
      0,
    ]),
    ..._pngChunk('IDAT', idat),
    ..._pngChunk('IEND', const []),
  ]);
}

/// JPEG mínimo con cabecera SOF0 (solo para leer dimensiones).
Uint8List buildJpeg({int width = 64, int height = 32}) {
  return Uint8List.fromList([
    0xFF, 0xD8, // SOI
    0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x00,
    0x00, 0x01, 0x00, 0x01, 0x00, 0x00, // APP0
    0xFF, 0xC0, 0x00, 0x11, 0x08,
    (height >> 8) & 0xFF, height & 0xFF,
    (width >> 8) & 0xFF, width & 0xFF,
    0x03, 0x01, 0x22, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11, 0x01, // SOF0
    0xFF, 0xD9, // EOI
  ]);
}

/// Empaqueta un mapa de partes en un ZIP (formato OOXML).
Uint8List zipParts(Map<String, String> parts) {
  final archive = Archive();
  parts.forEach((name, content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  final encoded = ZipEncoder().encode(archive);
  if (encoded == null) {
    throw StateError('No se pudo crear el ZIP de prueba.');
  }
  return Uint8List.fromList(encoded);
}

const String _wNs =
    'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"';
const String _rNs =
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"';
const String _wpNs =
    'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"';
const String _aNs =
    'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"';
const String _picNs =
    'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"';

String _contentTypes({required bool withHeader}) {
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
      '${withHeader ? '<Override PartName="/word/header1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml"/>' : ''}'
      '</Types>';
}

const String _packageRels =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
    '</Relationships>';

/// DOCX mínimo con cuerpo y, opcionalmente, un encabezado con una imagen.
Uint8List buildDocx({
  required List<String> bodyParagraphs,
  String? headerText,
  bool headerWithPicture = false,
}) {
  final withHeader = headerText != null;
  final parts = <String, String>{
    '[Content_Types].xml': _contentTypes(withHeader: withHeader),
    '_rels/.rels': _packageRels,
    'word/document.xml': _documentXml(
      bodyParagraphs: bodyParagraphs,
      withHeader: withHeader,
    ),
  };

  if (withHeader) {
    parts['word/header1.xml'] = _headerXml(
      headerText: headerText,
      withPicture: headerWithPicture,
    );
    parts['word/_rels/document.xml.rels'] =
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/header" Target="header1.xml"/>'
        '</Relationships>';
    if (headerWithPicture) {
      parts['word/_rels/header1.xml.rels'] =
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/old-logo.png"/>'
          '</Relationships>';
      parts['word/media/old-logo.png'] = 'placeholder';
      parts['[Content_Types].xml'] = _contentTypes(withHeader: true)
          .replaceFirst(
            '<Default Extension="xml"',
            '<Default Extension="png" ContentType="image/png"/>'
                '<Default Extension="xml"',
          );
    }
  }

  return zipParts(parts);
}

String _fixtureText(String text) {
  return text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}

String _fixtureParagraph(String text) {
  return '<w:p><w:r><w:t xml:space="preserve">${_fixtureText(text)}</w:t>'
      '</w:r></w:p>';
}

String _fixtureCell(String body, {String properties = ''}) {
  return '<w:tc><w:tcPr><w:tcW w:w="0" w:type="auto"/>$properties'
      '</w:tcPr>$body</w:tc>';
}

String _fixtureRow(List<String> cells) => '<w:tr>${cells.join()}</w:tr>';

String _fixtureTable(List<String> rows, {int columns = 6}) {
  final grid = List<String>.filled(columns, '<w:gridCol w:w="1500"/>').join();
  return '<w:tbl><w:tblPr><w:tblW w:w="0" w:type="auto"/></w:tblPr>'
      '<w:tblGrid>$grid</w:tblGrid>${rows.join()}</w:tbl>';
}

String _emptyFixtureRow(int columns) {
  return _fixtureRow(
    List<String>.generate(columns, (_) => _fixtureCell('<w:p/>')),
  );
}

/// DOCX con la estructura de la plantilla real: folio, título, subtítulo con
/// `vMerge`, tabla de información anidada, resultados con filas vacías,
/// estadísticas y firmas.
Uint8List buildReportTemplateDocx({String title = 'Reporte de ensayo'}) {
  final infoTable = _fixtureTable([
    _fixtureRow([
      _fixtureCell(_fixtureParagraph('Test Type')),
      _fixtureCell('<w:p/>'),
      _fixtureCell(_fixtureParagraph('Operador')),
      _fixtureCell('<w:p/>'),
      _fixtureCell(_fixtureParagraph('Dpto. Calidad')),
      _fixtureCell('<w:p/>'),
    ]),
    _fixtureRow([
      _fixtureCell(_fixtureParagraph('Mat.Name')),
      _fixtureCell('<w:p/>'),
      _fixtureCell(_fixtureParagraph('Mat.Type')),
      _fixtureCell('<w:p/>'),
      _fixtureCell(_fixtureParagraph('Make Date')),
      _fixtureCell('<w:p/>'),
    ]),
    _fixtureRow([
      _fixtureCell(_fixtureParagraph('Test For')),
      _fixtureCell('<w:p/>'),
      _fixtureCell(_fixtureParagraph('Humi')),
      _fixtureCell('<w:p/>'),
      _fixtureCell(_fixtureParagraph('Temp')),
      _fixtureCell('<w:p/>'),
    ]),
    _fixtureRow([
      _fixtureCell(_fixtureParagraph('Lo')),
      _fixtureCell('<w:p/>'),
      _fixtureCell(_fixtureParagraph('PET')),
      _fixtureCell('<w:p/>'),
      _fixtureCell('<w:p/>'),
      _fixtureCell('<w:p/>'),
    ]),
  ]);

  final resultsTable = _fixtureTable([
    _fixtureRow([
      _fixtureCell(_fixtureParagraph('Num')),
      _fixtureCell(_fixtureParagraph('Area')),
      _fixtureCell(_fixtureParagraph('Fmax')),
      _fixtureCell(_fixtureParagraph('Stress')),
      _fixtureCell(_fixtureParagraph('Elong')),
      _fixtureCell('<w:p/>'),
    ]),
    _fixtureRow([
      _fixtureCell(_fixtureParagraph('1')),
      _fixtureCell(_fixtureParagraph('21.7')),
      _fixtureCell(_fixtureParagraph('284.6')),
      _fixtureCell(_fixtureParagraph('13.1')),
      _fixtureCell(_fixtureParagraph('618')),
      _fixtureCell('<w:p/>'),
    ]),
    _emptyFixtureRow(6),
    _emptyFixtureRow(6),
    _emptyFixtureRow(6),
  ]);

  final statsTable = _fixtureTable([
    _fixtureRow([
      _fixtureCell(_fixtureParagraph('Avg')),
      _fixtureCell(_fixtureParagraph('3.94')),
      _fixtureCell(_fixtureParagraph('13.67')),
      _fixtureCell(_fixtureParagraph('1.13')),
      _fixtureCell(_fixtureParagraph('0.047')),
      _fixtureCell(_fixtureParagraph('618')),
    ]),
    _fixtureRow([
      _fixtureCell(_fixtureParagraph('Std. Dev.')),
      _fixtureCell(_fixtureParagraph('0.12')),
      _fixtureCell(_fixtureParagraph('0.34')),
      _fixtureCell(_fixtureParagraph('0.05')),
      _fixtureCell(_fixtureParagraph('0.002')),
      _fixtureCell(_fixtureParagraph('0')),
    ]),
  ]);

  final signatureTable = _fixtureTable([
    _fixtureRow([_fixtureCell(_fixtureParagraph('assessor:'))]),
  ], columns: 1);
  final ratifierTable = _fixtureTable([
    _fixtureRow([_fixtureCell(_fixtureParagraph('ratifier:'))]),
  ], columns: 1);
  final testPersonTable = _fixtureTable([
    _fixtureRow([_fixtureCell(_fixtureParagraph('test person:'))]),
  ], columns: 1);

  final topTable = _fixtureTable([
    _fixtureRow([
      _fixtureCell(
        _fixtureParagraph('TLG001'),
        properties: '<w:gridSpan w:val="6"/>',
      ),
    ]),
    _fixtureRow([
      _fixtureCell(
        _fixtureParagraph(title),
        properties: '<w:gridSpan w:val="6"/>',
      ),
    ]),
    _fixtureRow([
      _fixtureCell(
        _fixtureParagraph('Material'),
        properties: '<w:vMerge w:val="restart"/>',
      ),
      _fixtureCell('<w:p/>'),
    ]),
    _fixtureRow([
      _fixtureCell(
        _fixtureParagraph('Reporte de prueba de tensión'),
        properties: '<w:vMerge/>',
      ),
      _fixtureCell('<w:p/>'),
    ]),
    _emptyFixtureRow(6),
    _fixtureRow([
      _fixtureCell('$infoTable<w:p/>', properties: '<w:gridSpan w:val="6"/>'),
    ]),
    _fixtureRow([
      _fixtureCell(
        _fixtureParagraph('comment:'),
        properties: '<w:gridSpan w:val="6"/>',
      ),
    ]),
    _fixtureRow([
      _fixtureCell(
        '$resultsTable<w:p/>',
        properties: '<w:gridSpan w:val="6"/>',
      ),
    ]),
    _emptyFixtureRow(6),
    _fixtureRow([
      _fixtureCell('$statsTable<w:p/>', properties: '<w:gridSpan w:val="6"/>'),
    ]),
    _fixtureRow([
      _fixtureCell(
        '<w:p><w:r><w:pict/></w:r></w:p>',
        properties: '<w:gridSpan w:val="6"/>',
      ),
    ]),
    _fixtureRow([
      _fixtureCell('<w:p/>'),
      _fixtureCell('$signatureTable<w:p/>'),
      _fixtureCell('<w:p/>'),
      _fixtureCell('$ratifierTable<w:p/>'),
      _fixtureCell('<w:p/>'),
      _fixtureCell(
        '$testPersonTable<w:p/>',
        properties: '<w:vMerge w:val="restart"/>',
      ),
    ]),
    _fixtureRow([
      _fixtureCell('<w:p/>'),
      _fixtureCell('<w:p/>'),
      _fixtureCell('<w:p/>'),
      _fixtureCell('<w:p/>'),
      _fixtureCell('<w:p/>'),
      _fixtureCell('<w:p/>', properties: '<w:vMerge/>'),
    ]),
    _fixtureRow([
      _fixtureCell(
        _fixtureParagraph('Printed in 2024-05-01'),
        properties: '<w:gridSpan w:val="6"/>',
      ),
    ]),
  ]);

  return zipParts({
    '[Content_Types].xml': _contentTypes(withHeader: false),
    '_rels/.rels': _packageRels,
    'word/document.xml':
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document $_wNs $_rNs $_wpNs $_aNs $_picNs>'
        '<w:body>${_fixtureParagraph('LOGO')}$topTable<w:sectPr/>'
        '</w:body></w:document>',
  });
}

String _documentXml({
  required List<String> bodyParagraphs,
  required bool withHeader,
}) {
  final paragraphs = bodyParagraphs
      .map(
        (text) => '<w:p><w:r><w:rPr><w:b/></w:rPr><w:t>$text</w:t></w:r></w:p>',
      )
      .join();
  final headerReference = withHeader
      ? '<w:headerReference w:type="default" r:id="rId1"/>'
      : '';
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:document $_wNs $_rNs $_wpNs $_aNs $_picNs>'
      '<w:body>$paragraphs<w:sectPr>$headerReference</w:sectPr></w:body>'
      '</w:document>';
}

String _headerXml({required String headerText, required bool withPicture}) {
  final picture = withPicture
      ? '<w:r><w:drawing><wp:inline><wp:extent cx="914400" cy="304800"/>'
            '<wp:docPr id="7" name="Logo plantilla"/><a:graphic>'
            '<a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
            '<pic:pic><pic:nvPicPr><pic:cNvPr id="7" name="old-logo.png"/>'
            '<pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed="rId1"/>'
            '</pic:blipFill><pic:spPr/></pic:pic>'
            '</a:graphicData></a:graphic></wp:inline></w:drawing></w:r>'
      : '';
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:hdr $_wNs $_rNs $_wpNs $_aNs $_picNs>'
      '<w:p><w:r><w:t>$headerText</w:t></w:r>$picture</w:p>'
      '</w:hdr>';
}

/// Libro `.xlsx` sintético con etiquetas chinas, un valor numérico y dos filas
/// libres en el encabezado (a partir de [firstRow]) para la marca.
Uint8List buildTensionWorkbook({int firstRow = 2}) {
  final excel = Excel.createExcel();
  final sheet = excel['测试报告'];

  void put(int row, List<CellValue> values) {
    for (var index = 0; index < values.length; index++) {
      sheet.updateCell(
        CellIndex.indexByColumnRow(columnIndex: index, rowIndex: row),
        values[index],
      );
    }
  }

  put(firstRow, [TextCellValue('测试报告')]);
  put(firstRow + 1, [TextCellValue('报告编号'), TextCellValue('SP-2024-001')]);
  put(firstRow + 2, [TextCellValue('测试日期：2024-05-01')]);
  put(firstRow + 3, [
    TextCellValue('抗拉强度 (MPa)'),
    DoubleCellValue(25.4),
    TextCellValue('伸长率'),
  ]);
  excel.delete('Sheet1');
  final bytes = excel.save();
  return Uint8List.fromList(bytes!);
}

/// Contenido que imita un `.doc` de Word 97-2003 (firma OLE2 + relleno).
///
/// No es un documento válido: sólo sirve para probar la detección del formato
/// antiguo y el flujo de conversión sin depender de Word.
Uint8List buildLegacyDocBytes({int padding = 512}) {
  return Uint8List.fromList([
    0xD0,
    0xCF,
    0x11,
    0xE0,
    0xA1,
    0xB1,
    0x1A,
    0xE1,
    ...List<int>.filled(padding, 0),
  ]);
}

/// `.docx` mínimo que simula el resultado de convertir un `.doc`.
Uint8List buildConvertedDocx({
  List<String> bodyParagraphs = const ['测试报告', '报告编号: A-1'],
}) {
  return buildDocx(bodyParagraphs: bodyParagraphs);
}

/// Devuelve las partes XML del paquete que no son XML bien formado.
List<String> malformedXmlParts(List<int> bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final failures = <String>[];
  for (final file in archive.files) {
    if (!file.isFile ||
        !(file.name.endsWith('.xml') || file.name.endsWith('.rels'))) {
      continue;
    }
    final text = utf8.decode(file.content as List<int>, allowMalformed: true);
    try {
      XmlDocument.parse(text);
    } on XmlException {
      failures.add(file.name);
    }
  }
  return failures;
}
