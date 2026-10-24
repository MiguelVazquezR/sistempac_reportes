import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reportes_sistempac/core/format_utils.dart';
import 'package:reportes_sistempac/core/report_processing_exception.dart';
import 'package:reportes_sistempac/models/processing_options.dart';
import 'package:reportes_sistempac/models/selected_report.dart';
import 'package:reportes_sistempac/services/ooxml/ooxml_package.dart';
import 'package:reportes_sistempac/services/report_processor.dart';

import 'helpers/test_fixtures.dart';

SelectedReport _report(String name, ReportFormat format) {
  return SelectedReport(
    path: 'C:\\reportes\\$name',
    name: name,
    sizeBytes: 1024,
    format: format,
  );
}

void main() {
  group('ReportProcessor', () {
    test('rechaza .xls con indicación de conversión', () {
      expect(
        () => ReportProcessor().process(
          file: _report('reporte.xls', ReportFormat.legacyXls),
          options: const ProcessingOptions(),
          bytes: Uint8List.fromList([1, 2, 3]),
        ),
        throwsA(
          isA<ReportProcessingException>()
              .having(
                (error) => error.code,
                'code',
                ReportErrorCode.legacyNeedsConversion,
              )
              .having((error) => error.hint, 'hint', contains('.xlsx')),
        ),
      );
    });

    test('rechaza .doc con indicación de conversión', () {
      expect(
        () => ReportProcessor().process(
          file: _report('informe.doc', ReportFormat.legacyDoc),
          options: const ProcessingOptions(),
          bytes: Uint8List.fromList([1, 2, 3]),
        ),
        throwsA(
          isA<ReportProcessingException>().having(
            (error) => error.hint,
            'hint',
            contains('.docx'),
          ),
        ),
      );
    });

    test('rechaza formatos desconocidos', () {
      expect(
        () => ReportProcessor().process(
          file: _report('foto.png', ReportFormat.unknown),
          options: const ProcessingOptions(),
          bytes: Uint8List.fromList([1, 2, 3]),
        ),
        throwsA(
          isA<ReportProcessingException>().having(
            (error) => error.code,
            'code',
            ReportErrorCode.unsupportedFormat,
          ),
        ),
      );
    });
  });

  group('OoxmlPackage', () {
    test('decodifica y vuelve a codificar las partes', () {
      final bytes = zipParts({
        '[Content_Types].xml': '<Types/>',
        'word/document.xml': '<document/>',
      });
      final package = OoxmlPackage.decode(bytes);
      expect(package.names, contains('word/document.xml'));
      expect(package.readText('[Content_Types].xml'), '<Types/>');

      package.writeText('word/document.xml', '<document>ok</document>');
      final roundTrip = OoxmlPackage.decode(package.encode());
      expect(
        roundTrip.readText('word/document.xml'),
        '<document>ok</document>',
      );
    });

    test('resuelve rutas y relaciones', () {
      expect(
        OoxmlPackage.relationshipsPathFor('xl/worksheets/sheet1.xml'),
        'xl/worksheets/_rels/sheet1.xml.rels',
      );
      expect(
        OoxmlPackage.resolvePartPath(
          'xl/worksheets/sheet1.xml',
          '../drawings/drawing1.xml',
        ),
        'xl/drawings/drawing1.xml',
      );
      expect(
        OoxmlPackage.relativeTarget('word/header1.xml', 'word/media/logo.png'),
        'media/logo.png',
      );
      expect(
        OoxmlPackage.relativeTarget(
          'xl/drawings/drawing1.xml',
          'xl/media/logo.png',
        ),
        '../media/logo.png',
      );
    });

    test('elimina partes', () {
      final bytes = zipParts({'a.xml': '<a/>', 'b.xml': '<b/>'});
      final package = OoxmlPackage.decode(bytes);
      package.remove('a.xml');
      final roundTrip = OoxmlPackage.decode(package.encode());
      expect(roundTrip.contains('a.xml'), isFalse);
      expect(roundTrip.contains('b.xml'), isTrue);
    });
  });
}
