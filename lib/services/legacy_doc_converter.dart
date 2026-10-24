import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../core/format_utils.dart';
import '../core/report_processing_exception.dart';

/// Convierte documentos Word 97-2003 (`.doc`) a `.docx` sin intervención del
/// usuario.
///
/// El formato `.doc` es un contenedor OLE2 binario (no es un ZIP OOXML), por lo
/// que no se puede reprocesar directamente como paquete OOXML. La conversión se
/// delega a una herramienta externa siguiendo una cascada:
///
/// 1. Automatización COM de Microsoft Word (`Word.Application`).
/// 2. LibreOffice en modo «headless» (`soffice --convert-to docx`).
/// 3. Si ninguna está disponible se lanza un error accionable en español.
///
/// La herramienta externa escribe en una carpeta temporal que siempre se
/// elimina al terminar; el archivo original nunca se modifica.
class LegacyDocConverter {
  const LegacyDocConverter({this.timeout = const Duration(seconds: 120)});

  /// Tiempo máximo que se espera a la herramienta externa por archivo.
  final Duration timeout;

  /// Marca que devuelve el script de Word cuando COM no está registrado.
  static const String wordUnavailableMarker = 'WORD_NOT_AVAILABLE';

  /// Código de salida del script de Word cuando COM no está registrado.
  static const int wordUnavailableExitCode = 3;

  /// Candidatos habituales de instalación de LibreOffice en Windows.
  static const List<String> sofficeCandidates = [
    r'C:\Program Files\LibreOffice\program\soffice.exe',
    r'C:\Program Files (x86)\LibreOffice\program\soffice.exe',
  ];

  /// Convierte [sourcePath] (`.doc`) y devuelve los bytes del `.docx`.
  ///
  /// [fileName] sólo se usa en los mensajes de error.
  Future<Uint8List> convert({
    required String sourcePath,
    required String fileName,
  }) async {
    Directory? workspace;
    try {
      workspace = await Directory.systemTemp.createTemp(
        'reportes_sistempac_doc_',
      );
      final destination = p.join(workspace.path, 'convertido.docx');
      await _convertToFile(
        sourcePath: sourcePath,
        destinationPath: destination,
        workspace: workspace,
        fileName: fileName,
      );

      final output = File(destination);
      if (!await output.exists()) {
        throw ReportProcessingException(
          ReportErrorCode.conversionFailed,
          'La conversión no generó ningún documento.',
          hint:
              'Abre el archivo en Word y usa "Guardar como…" para crear un '
              '.docx antes de procesarlo.',
          fileName: fileName,
        );
      }

      final bytes = await output.readAsBytes();
      if (!FormatUtils.isZip(bytes)) {
        throw ReportProcessingException(
          ReportErrorCode.conversionFailed,
          'La conversión no produjo un documento .docx válido.',
          hint:
              'El archivo .doc puede estar dañado o protegido. Ábrelo en Word, '
              'guárdalo como .docx y vuelve a intentarlo.',
          fileName: fileName,
        );
      }
      return bytes;
    } on ReportProcessingException {
      rethrow;
    } on FileSystemException catch (error) {
      throw ReportProcessingException(
        ReportErrorCode.conversionFailed,
        'No fue posible preparar la conversión del documento.',
        hint: error.message,
        fileName: fileName,
        cause: error,
      );
    } finally {
      await _disposeWorkspace(workspace);
    }
  }

  /// Ejecuta la cascada de conversores y deja el `.docx` en [destinationPath].
  Future<void> _convertToFile({
    required String sourcePath,
    required String destinationPath,
    required Directory workspace,
    required String fileName,
  }) async {
    final failures = <String>[];
    var anyAvailable = false;

    if (Platform.isWindows) {
      final word = await _convertWithWord(
        sourcePath: sourcePath,
        destinationPath: destinationPath,
      );
      switch (word.status) {
        case _BackendStatus.success:
          return;
        case _BackendStatus.unavailable:
          failures.add('Microsoft Word no está disponible.');
        case _BackendStatus.failed:
          anyAvailable = true;
          failures.add('Microsoft Word: ${word.detail ?? 'error desconocido'}');
      }
    }

    final soffice = await _findSoffice();
    if (soffice != null) {
      anyAvailable = true;
      final libreOffice = await _convertWithLibreOffice(
        executable: soffice,
        sourcePath: sourcePath,
        destinationPath: destinationPath,
        workspace: workspace,
      );
      if (libreOffice.status == _BackendStatus.success) {
        return;
      }
      failures.add('LibreOffice: ${libreOffice.detail ?? 'error desconocido'}');
    } else {
      failures.add('LibreOffice no está instalado.');
    }

    if (!anyAvailable) {
      throw ReportProcessingException(
        ReportErrorCode.legacyNeedsConversion,
        'No hay ningún conversor disponible para abrir este archivo .doc.',
        hint:
            'Instala Microsoft Word o LibreOffice en este equipo, o abre el '
            'archivo y usa "Guardar como…" para crear un .docx.',
        fileName: fileName,
      );
    }

    throw ReportProcessingException(
      ReportErrorCode.conversionFailed,
      'No fue posible convertir el documento .doc a .docx.',
      hint:
          '${failures.join(' · ')}. Abre el archivo en Word y usa '
          '"Guardar como…" para crear el .docx antes de procesarlo.',
      fileName: fileName,
    );
  }

  /// Convierte con Word usando automatización COM.
  Future<_BackendResult> _convertWithWord({
    required String sourcePath,
    required String destinationPath,
  }) async {
    final script = buildWordScript(
      sourcePath: sourcePath,
      destinationPath: destinationPath,
    );
    final command = await _runCommand(_powershellPath(), [
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-EncodedCommand',
      encodeCommand(script),
    ]);

    if (command.unavailable) {
      return const _BackendResult.unavailable();
    }
    if (command.exitCode == wordUnavailableExitCode ||
        command.stderr.contains(wordUnavailableMarker)) {
      return const _BackendResult.unavailable();
    }
    if (command.timedOut) {
      return _BackendResult.failed(
        'agotó el tiempo de espera de ${timeout.inSeconds} s',
      );
    }
    if (command.exitCode != 0) {
      return _BackendResult.failed(_firstLine(command.stderr));
    }
    if (!await File(destinationPath).exists()) {
      return _BackendResult.failed('Word no generó el archivo de salida');
    }
    return const _BackendResult.success();
  }

  /// Convierte con LibreOffice en modo «headless».
  Future<_BackendResult> _convertWithLibreOffice({
    required String executable,
    required String sourcePath,
    required String destinationPath,
    required Directory workspace,
  }) async {
    final outputDirectory = Directory(p.join(workspace.path, 'libreoffice'));
    final profileDirectory = Directory(p.join(workspace.path, 'perfil-lo'));
    try {
      await outputDirectory.create(recursive: true);
      await profileDirectory.create(recursive: true);
    } on FileSystemException catch (error) {
      return _BackendResult.failed(error.message);
    }

    final command = await _runCommand(executable, [
      '--headless',
      '--norestore',
      '--nolockcheck',
      '--nodefault',
      '--nofirststartwizard',
      '-env:UserInstallation=${_fileUri(profileDirectory.path)}',
      '--convert-to',
      'docx:MS Word 2007 XML',
      '--outdir',
      outputDirectory.path,
      sourcePath,
    ]);

    if (command.unavailable) {
      return const _BackendResult.unavailable();
    }
    if (command.timedOut) {
      return _BackendResult.failed(
        'agotó el tiempo de espera de ${timeout.inSeconds} s',
      );
    }
    if (command.exitCode != 0) {
      return _BackendResult.failed(_firstLine(command.stderr));
    }

    try {
      final produced = await outputDirectory
          .list()
          .where(
            (entity) => entity is File && p.extension(entity.path) == '.docx',
          )
          .cast<File>()
          .toList();
      if (produced.isEmpty) {
        return _BackendResult.failed('soffice no generó ningún archivo .docx');
      }
      await produced.first.copy(destinationPath);
      return const _BackendResult.success();
    } on FileSystemException catch (error) {
      return _BackendResult.failed(error.message);
    }
  }

  /// Script de PowerShell que abre el `.doc` en Word y lo guarda como `.docx`.
  ///
  /// Las rutas se escapan duplicando las comillas simples, que es la forma
  /// válida de literalizar cadenas en PowerShell. `ConfirmConversions` se
  /// desactiva para que Word no muestre el diálogo de conversión de formato y
  /// `AutomationSecurity` bloquea las macros del documento.
  static String buildWordScript({
    required String sourcePath,
    required String destinationPath,
  }) {
    final source = _escapePowerShellLiteral(sourcePath);
    final destination = _escapePowerShellLiteral(destinationPath);
    return '''
[Console]::OutputEncoding = [Text.Encoding]::UTF8
\$ErrorActionPreference = 'Stop'
if ([Type]::GetTypeFromProgID('Word.Application') -eq \$null) {
  [Console]::Error.WriteLine('$wordUnavailableMarker')
  exit $wordUnavailableExitCode
}
\$word = \$null
\$doc = \$null
try {
  \$word = New-Object -ComObject Word.Application
  \$word.Visible = \$false
  \$word.ScreenUpdating = \$false
  \$word.DisplayAlerts = 0
  \$word.AutomationSecurity = 3
  \$doc = \$word.Documents.Open('$source', \$false, \$true, \$false)
  try { \$doc.SaveAs2('$destination', 16) } catch { \$doc.SaveAs('$destination', 16) }
  \$doc.Close(0)
  exit 0
} catch {
  [Console]::Error.WriteLine(\$_.Exception.Message)
  exit 1
} finally {
  if (\$doc -ne \$null) { try { \$doc.Close(0) } catch { } }
  if (\$word -ne \$null) {
    try { \$word.Quit(0) } catch { }
    try { [void][Runtime.InteropServices.Marshal]::ReleaseComObject(\$word) } catch { }
  }
}
''';
  }

  /// Codifica un script para `powershell.exe -EncodedCommand` (UTF-16LE/base64).
  ///
  /// Así se evitan problemas de comillas y de caracteres no ASCII en las rutas
  /// (los nombres de los reportes suelen incluir caracteres chinos).
  static String encodeCommand(String script) {
    final bytes = <int>[];
    for (final unit in script.codeUnits) {
      bytes.add(unit & 0xFF);
      bytes.add((unit >> 8) & 0xFF);
    }
    return base64.encode(bytes);
  }

  /// Inversa de [encodeCommand]; útil para inspeccionar el comando en pruebas.
  static String decodeCommand(String encoded) {
    final bytes = base64.decode(encoded);
    final units = <int>[];
    for (var index = 0; index + 1 < bytes.length; index += 2) {
      units.add(bytes[index] | (bytes[index + 1] << 8));
    }
    return String.fromCharCodes(units);
  }

  static String _escapePowerShellLiteral(String value) =>
      value.replaceAll("'", "''");

  static String _fileUri(String path) =>
      'file:///${p.windows.normalize(path).replaceAll('\\', '/')}';

  static String _firstLine(String value) {
    for (final line in const LineSplitter().convert(value)) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) {
        return trimmed;
      }
    }
    return 'error desconocido';
  }

  static String _powershellPath() {
    final systemRoot = Platform.environment['SystemRoot'];
    if (systemRoot != null && systemRoot.trim().isNotEmpty) {
      final candidate = p.join(
        systemRoot,
        'System32',
        'WindowsPowerShell',
        'v1.0',
        'powershell.exe',
      );
      if (File(candidate).existsSync()) {
        return candidate;
      }
    }
    return 'powershell.exe';
  }

  /// Busca `soffice.exe` en las rutas habituales y en `PATH`.
  Future<String?> _findSoffice() async {
    if (Platform.isWindows) {
      for (final candidate in sofficeCandidates) {
        if (await File(candidate).exists()) {
          return candidate;
        }
      }
    }
    final executable = Platform.isWindows ? 'soffice.exe' : 'soffice';
    final pathVariable = Platform.environment['PATH'] ?? '';
    for (final entry in pathVariable.split(Platform.isWindows ? ';' : ':')) {
      final directory = entry.trim();
      if (directory.isEmpty) {
        continue;
      }
      final candidate = p.join(directory, executable);
      if (await File(candidate).exists()) {
        return candidate;
      }
    }
    return null;
  }

  Future<_CommandResult> _runCommand(
    String executable,
    List<String> arguments,
  ) async {
    final Process process;
    try {
      process = await Process.start(executable, arguments, runInShell: false);
    } on ProcessException catch (error) {
      return _CommandResult.unavailable(error.message);
    }

    final stdoutFuture = process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .join();
    final stderrFuture = process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .join();

    var timedOut = false;
    int exitCode;
    try {
      exitCode = await process.exitCode.timeout(timeout);
    } on TimeoutException {
      timedOut = true;
      process.kill();
      exitCode = -1;
    }

    return _CommandResult(
      exitCode: exitCode,
      stdout: await _safeRead(stdoutFuture),
      stderr: await _safeRead(stderrFuture),
      timedOut: timedOut,
    );
  }

  /// Lee la salida de un proceso sin bloquearse si un proceso nieto mantiene el
  /// tubo abierto (Word tarda en liberar la instancia COM).
  static Future<String> _safeRead(Future<String> future) async {
    try {
      return await future.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      return '';
    } on Exception {
      return '';
    }
  }

  static Future<void> _disposeWorkspace(Directory? workspace) async {
    if (workspace == null) {
      return;
    }
    try {
      if (await workspace.exists()) {
        await workspace.delete(recursive: true);
      }
    } on FileSystemException {
      // Windows libera el resto de los temporales por su cuenta.
    }
  }
}

/// Estado de un conversor externo.
enum _BackendStatus { success, unavailable, failed }

/// Resultado de intentar convertir con una herramienta externa.
class _BackendResult {
  const _BackendResult.success()
    : status = _BackendStatus.success,
      detail = null;

  const _BackendResult.unavailable()
    : status = _BackendStatus.unavailable,
      detail = null;

  const _BackendResult.failed(this.detail) : status = _BackendStatus.failed;

  final _BackendStatus status;
  final String? detail;
}

/// Resultado de ejecutar un proceso externo.
class _CommandResult {
  const _CommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.timedOut,
  }) : unavailable = false;

  const _CommandResult.unavailable(this.stderr)
    : exitCode = -1,
      stdout = '',
      timedOut = false,
      unavailable = true;

  final int exitCode;
  final String stdout;
  final String stderr;
  final bool timedOut;
  final bool unavailable;
}
