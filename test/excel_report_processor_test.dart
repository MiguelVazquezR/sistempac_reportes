import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reportes_sistempac/core/report_processing_exception.dart';
import 'package:reportes_sistempac/models/processing_options.dart';
import 'package:reportes_sistempac/services/excel_report_processor.dart';

import 'helpers/test_fixtures.dart';

List<String> textsOf(List<int> bytes) {
  final excel = Excel.decodeBytes(bytes);
  final texts = <String>[];
  for (final sheet in excel.tables.values) {
    for (final row in sheet.rows) {
      for (final cell in row) {
        final value = cell?.value;
        if (value != null && value.toString().trim().isNotEmpty) {
          texts.add(value.toString());
        }
      }
    }
  }
  return texts;
}

String partText(Archive archive, String name) {
  final file = archive.findFile(name);
  expect(file, isNotNull, reason: 'Falta la parte $name');
  return utf8.decode(file!.content as List<int>, allowMalformed: true);
}

void main() {
  late Uint8List workbook;

  setUpAll(() {
    workbook = buildTensionWorkbook();
  });

  test('traduce las celdas y aplica marca y logo', () {
    final processor = ExcelReportProcessor();
    final result = processor.process(
      bytes: workbook,
      fileName: 'reporte.xlsx',
      options: ProcessingOptions(
        companyName: 'SISTEMPAC',
        title: 'Reporte de Prueba de Tensión',
        logoBytes: buildPng(),
      ),
    );

    expect(result.warnings, isEmpty);
    expect(result.translatedItems, greaterThanOrEqualTo(4));
    expect(result.branding?.headerPlaced, isTrue);
    expect(result.branding?.logoPlaced, isTrue);

    final texts = textsOf(result.bytes);
    expect(texts, contains('Reporte de prueba'));
    expect(texts, contains('N.º de reporte'));
    expect(texts, contains('SP-2024-001'));
    expect(texts.any((text) => text.startsWith('Fecha de prueba')), isTrue);
    expect(
      texts.any((text) => text.startsWith('Resistencia a la tracción')),
      isTrue,
    );
    expect(texts, contains('Alargamiento'));
    expect(texts, contains('SISTEMPAC'));
    expect(texts, contains('Reporte de Prueba de Tensión'));

    final decoded = Excel.decodeBytes(result.bytes);
    expect(decoded.tables.keys.first, 'Reporte de prueba');
  });

  test('inserta el logo como imagen del paquete OOXML', () {
    final processor = ExcelReportProcessor();
    final result = processor.process(
      bytes: workbook,
      fileName: 'reporte.xlsx',
      options: ProcessingOptions(
        companyName: 'SISTEMPAC',
        title: 'Reporte',
        logoBytes: buildPng(),
      ),
    );

    final archive = ZipDecoder().decodeBytes(result.bytes);
    expect(archive.findFile('xl/media/logo.png'), isNotNull);
    expect(
      partText(archive, 'xl/drawings/drawing1.xml'),
      contains('Logo empresa'),
    );
    expect(partText(archive, '[Content_Types].xml'), contains('image/png'));
    expect(
      partText(archive, 'xl/worksheets/sheet1.xml'),
      contains('<drawing r:id='),
    );
    expect(
      partText(archive, 'xl/drawings/_rels/drawing1.xml.rels'),
      contains('../media/logo.png'),
    );
    expect(malformedXmlParts(result.bytes), isEmpty);
  });

  test('sin logo no se crean imágenes ni se insertan dibujos', () {
    final processor = ExcelReportProcessor();
    final result = processor.process(
      bytes: workbook,
      fileName: 'reporte.xlsx',
      options: const ProcessingOptions(
        companyName: '',
        title: '',
        addBranding: false,
      ),
    );

    final archive = ZipDecoder().decodeBytes(result.bytes);
    expect(archive.findFile('xl/media/logo.png'), isNull);
    expect(result.branding?.logoPlaced, isFalse);
    expect(result.branding?.headerPlaced, isFalse);
    final drawing = archive.findFile('xl/drawings/drawing1.xml');
    if (drawing != null) {
      expect(
        utf8.decode(drawing.content as List<int>, allowMalformed: true),
        isNot(contains('Logo empresa')),
      );
    }
    expect(textsOf(result.bytes), contains('Reporte de prueba'));
  });

  test('avisa cuando el reporte no tiene filas libres en el encabezado', () {
    final processor = ExcelReportProcessor();
    final result = processor.process(
      bytes: buildTensionWorkbook(firstRow: 0),
      fileName: 'reporte.xlsx',
      options: const ProcessingOptions(
        companyName: 'SISTEMPAC',
        title: 'Reporte de Prueba de Tensión',
      ),
    );

    expect(result.warnings, isNotEmpty);
    expect(
      result.warnings.first,
      contains('no tiene filas libres en el encabezado'),
    );
    expect(result.branding?.headerPlaced, isTrue);
    expect(
      textsOf(result.bytes),
      containsAll(<String>['SISTEMPAC', 'Reporte de Prueba de Tensión']),
    );
  });

  test('un libro sin datos produce emptyDocument', () {
    final excel = Excel.createExcel();
    final bytes = Uint8List.fromList(excel.save()!);
    final processor = ExcelReportProcessor();

    expect(
      () => processor.process(
        bytes: bytes,
        fileName: 'vacio.xlsx',
        options: const ProcessingOptions(),
      ),
      throwsA(
        isA<ReportProcessingException>().having(
          (error) => error.code,
          'code',
          ReportErrorCode.emptyDocument,
        ),
      ),
    );
  });

  test('un archivo que no es xlsx produce corruptFile', () {
    final processor = ExcelReportProcessor();
    expect(
      () => processor.process(
        bytes: Uint8List.fromList([1, 2, 3, 4, 5]),
        fileName: 'falso.xlsx',
        options: const ProcessingOptions(),
      ),
      throwsA(
        isA<ReportProcessingException>().having(
          (error) => error.code,
          'code',
          ReportErrorCode.corruptFile,
        ),
      ),
    );
  });
}
