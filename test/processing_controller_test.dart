import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reportes_sistempac/core/format_utils.dart';
import 'package:reportes_sistempac/core/report_processing_exception.dart';
import 'package:reportes_sistempac/models/app_settings.dart';
import 'package:reportes_sistempac/models/processing_result.dart';
import 'package:reportes_sistempac/services/legacy_doc_converter.dart';
import 'package:reportes_sistempac/state/processing_controller.dart';

import 'helpers/test_fixtures.dart';

/// Conversor falso: evita abrir Word o LibreOffice durante las pruebas.
class _FakeDocConverter implements LegacyDocConverter {
  _FakeDocConverter({this.bytes, this.error});

  final Uint8List? bytes;
  final ReportProcessingException? error;
  final List<String> convertedFiles = [];

  @override
  Duration get timeout => const Duration(seconds: 1);

  @override
  Future<Uint8List> convert({
    required String sourcePath,
    required String fileName,
  }) async {
    convertedFiles.add(fileName);
    final failure = error;
    if (failure != null) {
      throw failure;
    }
    return bytes!;
  }
}

void main() {
  test('procesa un lote completo y guarda el resultado en disco', () async {
    final directory = await Directory.systemTemp.createTemp(
      'reportes_sistempac_test',
    );
    addTearDown(() => directory.delete(recursive: true));

    final source = File(p.join(directory.path, 'reporte_tension.xlsx'))
      ..writeAsBytesSync(buildTensionWorkbook());

    final controller = ProcessingController();
    addTearDown(controller.dispose);

    await controller.addReports([source.path]);
    expect(controller.files, hasLength(1));
    expect(controller.files.first.format, ReportFormat.xlsx);
    expect(controller.canProcess, isTrue);

    await controller.processAll(
      settings: const AppSettings(
        companyName: 'SISTEMPAC',
        defaultTitle: 'Reporte de Prueba de Tensión',
        replaceLogo: false,
      ),
      title: 'Reporte de Prueba de Tensión',
    );

    expect(controller.results, hasLength(1));
    final result = controller.results.first;
    expect(result.status, isNot(ProcessingStatus.failed));
    expect(result.errorMessage, isNull);
    expect(result.outputPath, endsWith('reporte_tension_ES.xlsx'));
    expect(File(result.outputPath!).existsSync(), isTrue);
    expect(result.translatedItems, greaterThanOrEqualTo(4));

    final decoded = Excel.decodeBytes(
      File(result.outputPath!).readAsBytesSync(),
    );
    expect(decoded.tables.keys.first, 'Reporte de prueba');
    expect(controller.statusMessage, contains('1 reporte generado'));
  });

  test('ignora duplicados y archivos inexistentes', () async {
    final directory = await Directory.systemTemp.createTemp(
      'reportes_sistempac_test',
    );
    addTearDown(() => directory.delete(recursive: true));

    final source = File(p.join(directory.path, 'reporte.xlsx'))
      ..writeAsBytesSync(buildTensionWorkbook());

    final controller = ProcessingController();
    addTearDown(controller.dispose);

    await controller.addReports([source.path, source.path]);
    await controller.addReports([p.join(directory.path, 'no-existe.xlsx')]);

    expect(controller.files, hasLength(1));
    expect(controller.addErrors, hasLength(1));
    expect(controller.addErrors.first, contains('no existe'));

    controller.removeFile(controller.files.first);
    expect(controller.files, isEmpty);
    expect(controller.canProcess, isFalse);
  });

  test('no sobrescribe un resultado anterior', () async {
    final directory = await Directory.systemTemp.createTemp(
      'reportes_sistempac_test',
    );
    addTearDown(() => directory.delete(recursive: true));

    final source = File(p.join(directory.path, 'reporte.xlsx'))
      ..writeAsBytesSync(buildTensionWorkbook());
    File(p.join(directory.path, 'reporte_ES.xlsx')).writeAsBytesSync([1]);

    final controller = ProcessingController();
    addTearDown(controller.dispose);

    await controller.addReports([source.path]);
    await controller.processAll(
      settings: const AppSettings(
        companyName: 'SISTEMPAC',
        replaceLogo: false,
        addBranding: false,
      ),
      title: '',
    );

    expect(
      controller.results.first.outputPath,
      endsWith('reporte_ES (2).xlsx'),
    );
  });

  test('convierte un .doc a .docx antes de procesarlo', () async {
    final directory = await Directory.systemTemp.createTemp(
      'reportes_sistempac_test',
    );
    addTearDown(() => directory.delete(recursive: true));

    final source = File(p.join(directory.path, 'reporte_tension.doc'))
      ..writeAsBytesSync(buildLegacyDocBytes());
    final converter = _FakeDocConverter(bytes: buildConvertedDocx());

    final controller = ProcessingController(legacyDocConverter: converter);
    addTearDown(controller.dispose);

    await controller.addReports([source.path]);

    expect(controller.files.single.format, ReportFormat.legacyDoc);
    expect(controller.files.single.isConvertible, isTrue);
    expect(controller.files.single.needsManualConversion, isFalse);
    expect(controller.supportedCount, 1);
    expect(controller.convertibleCount, 1);
    expect(controller.manualConversionCount, 0);
    expect(controller.canProcess, isTrue);

    await controller.processAll(
      settings: const AppSettings(
        companyName: 'SISTEMPAC',
        addBranding: false,
        replaceLogo: false,
      ),
      title: 'Reporte de Prueba de Tensión',
    );

    expect(converter.convertedFiles, ['reporte_tension.doc']);
    final result = controller.results.single;
    expect(result.status, isNot(ProcessingStatus.failed));
    expect(result.errorMessage, isNull);
    expect(result.convertedFromLegacy, isTrue);
    expect(result.format, ReportFormat.legacyDoc);
    expect(result.outputPath, endsWith('reporte_tension_ES.docx'));
    expect(
      FormatUtils.isZip(File(result.outputPath!).readAsBytesSync()),
      isTrue,
      reason: 'El resultado debe ser un .docx real',
    );
    expect(controller.statusMessage, contains('1 convertido de .doc'));
    expect(source.existsSync(), isTrue, reason: 'El .doc no se modifica');
  });

  test('reporta el fallo de conversión de un .doc', () async {
    final directory = await Directory.systemTemp.createTemp(
      'reportes_sistempac_test',
    );
    addTearDown(() => directory.delete(recursive: true));

    final source = File(p.join(directory.path, 'reporte.doc'))
      ..writeAsBytesSync(buildLegacyDocBytes());
    final converter = _FakeDocConverter(
      error: const ReportProcessingException(
        ReportErrorCode.conversionFailed,
        'No fue posible convertir el documento .doc a .docx.',
        hint: 'Microsoft Word: error simulado',
        fileName: 'reporte.doc',
      ),
    );

    final controller = ProcessingController(legacyDocConverter: converter);
    addTearDown(controller.dispose);

    await controller.addReports([source.path]);
    await controller.processAll(
      settings: const AppSettings(addBranding: false, replaceLogo: false),
      title: '',
    );

    final result = controller.results.single;
    expect(result.status, ProcessingStatus.failed);
    expect(result.errorCode, ReportErrorCode.conversionFailed.name);
    expect(result.convertedFromLegacy, isFalse);
    expect(result.outputPath, isNull);
  });

  test('mantiene los .xls como conversión manual', () async {
    final directory = await Directory.systemTemp.createTemp(
      'reportes_sistempac_test',
    );
    addTearDown(() => directory.delete(recursive: true));

    final source = File(p.join(directory.path, 'libro_antiguo.xls'))
      ..writeAsBytesSync(buildLegacyDocBytes());

    final controller = ProcessingController();
    addTearDown(controller.dispose);

    await controller.addReports([source.path]);

    final file = controller.files.single;
    expect(file.format, ReportFormat.legacyXls);
    expect(file.needsManualConversion, isTrue);
    expect(file.isConvertible, isFalse);
    expect(controller.supportedCount, 0);
    expect(controller.manualConversionCount, 1);
    expect(controller.canProcess, isFalse);
  });
}
