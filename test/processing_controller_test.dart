import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reportes_sistempac/core/format_utils.dart';
import 'package:reportes_sistempac/models/app_settings.dart';
import 'package:reportes_sistempac/models/processing_result.dart';
import 'package:reportes_sistempac/state/processing_controller.dart';

import 'helpers/test_fixtures.dart';

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
}
