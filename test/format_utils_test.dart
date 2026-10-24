import 'package:flutter_test/flutter_test.dart';
import 'package:reportes_sistempac/core/format_utils.dart';

void main() {
  group('FormatUtils.detect', () {
    final zipHead = <int>[0x50, 0x4B, 0x03, 0x04, 0x14, 0x00, 0x00, 0x00];
    final oleHead = <int>[0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1];

    test('reconoce archivos .xlsx y .docx reales', () {
      expect(
        FormatUtils.detect(fileName: 'reporte.xlsx', bytes: zipHead),
        ReportFormat.xlsx,
      );
      expect(
        FormatUtils.detect(fileName: 'reporte.docx', bytes: zipHead),
        ReportFormat.docx,
      );
    });

    test('detecta .xls/.doc antiguos por su firma OLE', () {
      expect(
        FormatUtils.detect(fileName: 'reporte.xls', bytes: oleHead),
        ReportFormat.legacyXls,
      );
      expect(
        FormatUtils.detect(fileName: 'reporte.doc', bytes: oleHead),
        ReportFormat.legacyDoc,
      );
      // Un .xlsx renombrado desde .xls sigue siendo OLE.
      expect(
        FormatUtils.detect(fileName: 'renombrado.xlsx', bytes: oleHead),
        ReportFormat.legacyXls,
      );
    });

    test('marca como desconocido lo que no es OOXML ni OLE', () {
      expect(
        FormatUtils.detect(
          fileName: 'foto.png',
          bytes: [0x89, 0x50, 0x4E, 0x47],
        ),
        ReportFormat.unknown,
      );
    });

    test('clasifica formatos', () {
      expect(FormatUtils.isSupported(ReportFormat.xlsx), isTrue);
      expect(FormatUtils.isSupported(ReportFormat.docx), isTrue);
      expect(FormatUtils.isSupported(ReportFormat.legacyXls), isFalse);
      expect(FormatUtils.isLegacy(ReportFormat.legacyDoc), isTrue);
      expect(FormatUtils.label(ReportFormat.legacyDoc), 'Word 97-2003 (.doc)');
    });
  });

  group('FormatUtils helpers', () {
    test('genera nombres de salida con sufijo', () {
      expect(
        FormatUtils.suggestedOutputName(
          'reporte.xlsx',
          format: ReportFormat.xlsx,
        ),
        'reporte_ES.xlsx',
      );
      expect(
        FormatUtils.suggestedOutputName(
          'informe.docx',
          format: ReportFormat.docx,
        ),
        'informe_ES.docx',
      );
    });

    test('formatea tamaños de archivo', () {
      expect(FormatUtils.formatFileSize(512), '512 B');
      expect(FormatUtils.formatFileSize(2048), '2.0 KB');
      expect(FormatUtils.formatFileSize(5 * 1024 * 1024), '5.0 MB');
    });

    test('limpia caracteres inválidos del nombre', () {
      expect(FormatUtils.sanitizeFileStem('a:b*c?'), 'a b c');
      expect(FormatUtils.sanitizeFileStem('   '), 'reporte');
    });

    test('obtiene la extensión en minúsculas', () {
      expect(FormatUtils.extensionOf('Reporte.XLSX'), 'xlsx');
      expect(FormatUtils.extensionOf('sin_extension'), '');
    });
  });

  group('FormatUtils conversión de formatos antiguos', () {
    test('sólo los .doc se convierten automáticamente', () {
      expect(FormatUtils.isConvertible(ReportFormat.legacyDoc), isTrue);
      expect(FormatUtils.isConvertible(ReportFormat.legacyXls), isFalse);
      expect(FormatUtils.isConvertible(ReportFormat.docx), isFalse);
      expect(FormatUtils.needsManualConversion(ReportFormat.legacyXls), isTrue);
      expect(
        FormatUtils.needsManualConversion(ReportFormat.legacyDoc),
        isFalse,
      );
    });

    test('los .doc cuentan como procesables', () {
      expect(FormatUtils.isProcessable(ReportFormat.xlsx), isTrue);
      expect(FormatUtils.isProcessable(ReportFormat.docx), isTrue);
      expect(FormatUtils.isProcessable(ReportFormat.legacyDoc), isTrue);
      expect(FormatUtils.isProcessable(ReportFormat.legacyXls), isFalse);
      expect(FormatUtils.isProcessable(ReportFormat.unknown), isFalse);
    });

    test('un .doc produce un .docx como salida', () {
      expect(FormatUtils.outputExtension(ReportFormat.docx), '.docx');
      expect(FormatUtils.outputExtension(ReportFormat.legacyDoc), '.docx');
      expect(FormatUtils.outputExtension(ReportFormat.xlsx), '.xlsx');
      expect(FormatUtils.outputExtension(ReportFormat.legacyXls), '.xlsx');
      expect(
        FormatUtils.suggestedOutputName(
          'reporte.doc',
          format: ReportFormat.legacyDoc,
        ),
        'reporte_ES.docx',
      );
    });
  });
}
