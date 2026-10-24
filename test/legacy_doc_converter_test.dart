import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reportes_sistempac/core/format_utils.dart';
import 'package:reportes_sistempac/models/app_settings.dart';
import 'package:reportes_sistempac/models/processing_result.dart';
import 'package:reportes_sistempac/services/legacy_doc_converter.dart';
import 'package:reportes_sistempac/state/processing_controller.dart';

import 'helpers/test_fixtures.dart';

/// Guarda un `.docx` como `.doc` usando Word (sólo para la prueba integrada).
///
/// Devuelve `null` si la operación funcionó y el detalle del error si falló.
Future<String?> _saveDocxAsDoc(String source, String destination) async {
  final script =
      '''
\$ErrorActionPreference = 'Stop'
\$word = \$null
\$doc = \$null
try {
  \$word = New-Object -ComObject Word.Application
  \$word.Visible = \$false
  \$word.DisplayAlerts = 0
  \$doc = \$word.Documents.Open('${source.replaceAll("'", "''")}', \$false, \$true, \$false)
  \$doc.SaveAs2('${destination.replaceAll("'", "''")}', 0)
  \$doc.Close(0)
  exit 0
} catch {
  [Console]::Error.WriteLine(\$_.Exception.Message)
  exit 1
} finally {
  if (\$doc -ne \$null) { try { \$doc.Close(0) } catch { } }
  if (\$word -ne \$null) { try { \$word.Quit(0) } catch { } }
}
''';
  final result = await Process.run('powershell.exe', [
    '-NoProfile',
    '-NonInteractive',
    '-ExecutionPolicy',
    'Bypass',
    '-EncodedCommand',
    LegacyDocConverter.encodeCommand(script),
  ]);
  if (result.exitCode == 0) {
    return null;
  }
  return '${result.stderr}${result.stdout}';
}

void main() {
  group('LegacyDocConverter.encodeCommand', () {
    test('codifica el script en UTF-16LE/base64 y lo puede decodificar', () {
      const script = r"Write-Output '测试报告 O'Brien' con acentos: ñ";

      final encoded = LegacyDocConverter.encodeCommand(script);

      expect(encoded, isNotEmpty);
      expect(encoded, isNot(contains('\n')));
      expect(LegacyDocConverter.decodeCommand(encoded), script);
    });

    test('soporta caracteres fuera del plano básico', () {
      const script = 'Reporte 😀 de tensión';

      expect(
        LegacyDocConverter.decodeCommand(
          LegacyDocConverter.encodeCommand(script),
        ),
        script,
      );
    });
  });

  group('LegacyDocConverter.buildWordScript', () {
    test('guarda como .docx, bloquea macros y escapa comillas simples', () {
      final script = LegacyDocConverter.buildWordScript(
        sourcePath: r"C:\Reportes\O'Brien\报告.doc",
        destinationPath: r'C:\Temp\convertido.docx',
      );

      expect(
        script,
        contains(r"Documents.Open('C:\Reportes\O''Brien\报告.doc'"),
        reason: 'Las comillas simples deben duplicarse en PowerShell',
      );
      expect(script, contains(r"SaveAs2('C:\Temp\convertido.docx', 16)"));
      expect(script, contains(r'$word.AutomationSecurity = 3'));
      expect(script, contains(r'$word.DisplayAlerts = 0'));
      expect(script, contains(r'$word.Visible = $false'));
      expect(script, contains(r'$doc.Close(0)'));
      expect(script, contains(r'$word.Quit(0)'));
      expect(script, contains(LegacyDocConverter.wordUnavailableMarker));
    });

    test('usa el marcador de Word no disponible como código de salida', () {
      expect(LegacyDocConverter.wordUnavailableExitCode, 3);

      final script = LegacyDocConverter.buildWordScript(
        sourcePath: r'C:\a.doc',
        destinationPath: r'C:\a.docx',
      );

      expect(script, contains('exit 3'));
      expect(
        script,
        contains("[Console]::Error.WriteLine('WORD_NOT_AVAILABLE')"),
      );
    });
  });

  group('LegacyDocConverter.convert (Word COM real)', () {
    final enabled = Platform.environment['RUN_WORD_COM_TEST'] == '1';

    test(
      'convierte un .doc real a .docx sin modificar el original',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'reportes_sistempac_com',
        );
        addTearDown(() => directory.delete(recursive: true));

        final docx = File(p.join(directory.path, 'origen.docx'))
          ..writeAsBytesSync(buildConvertedDocx());
        final doc = File(p.join(directory.path, 'origen.doc'));

        final failure = await _saveDocxAsDoc(docx.path, doc.path);
        expect(failure, isNull, reason: 'Word debe crear el .doc de prueba');
        expect(doc.existsSync(), isTrue);
        expect(
          FormatUtils.detect(
            fileName: doc.path,
            bytes: doc.readAsBytesSync().take(8).toList(),
          ),
          ReportFormat.legacyDoc,
        );

        final bytes = await const LegacyDocConverter().convert(
          sourcePath: doc.path,
          fileName: p.basename(doc.path),
        );

        expect(FormatUtils.isZip(bytes), isTrue);
        expect(bytes.length, greaterThan(1024));
        expect(doc.existsSync(), isTrue, reason: 'El original no se modifica');

        // Flujo completo: el controlador convierte el .doc y genera el reporte.
        final controller = ProcessingController(
          legacyDocConverter: const LegacyDocConverter(),
        );
        addTearDown(controller.dispose);

        await controller.addReports([doc.path]);
        expect(controller.canProcess, isTrue);

        await controller.processAll(
          settings: const AppSettings(
            companyName: 'SISTEMPAC',
            addBranding: false,
            replaceLogo: false,
          ),
          title: 'Reporte de Prueba de Tensión',
        );

        final result = controller.results.single;
        expect(result.status, isNot(ProcessingStatus.failed));
        expect(result.convertedFromLegacy, isTrue);
        expect(result.outputPath, endsWith('origen_ES.docx'));

        final output = File(result.outputPath!);
        expect(output.existsSync(), isTrue);
        final archive = ZipDecoder().decodeBytes(output.readAsBytesSync());
        final body = utf8.decode(
          archive.findFile('word/document.xml')!.content as List<int>,
          allowMalformed: true,
        );
        expect(body, contains('Reporte de prueba'));
      },
      skip: enabled
          ? null
          : 'Define RUN_WORD_COM_TEST=1 para ejecutar la prueba con Word COM.',
      timeout: const Timeout(Duration(minutes: 5)),
    );
  });
}
