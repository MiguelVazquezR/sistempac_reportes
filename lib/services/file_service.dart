import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import '../core/format_utils.dart';
import '../core/image_size_reader.dart';
import '../core/report_processing_exception.dart';
import '../models/selected_report.dart';

/// Acceso a disco y a los diálogos nativos de selección/guardado.
class FileService {
  /// Abre el selector nativo y devuelve las rutas elegidas (puede ser vacío).
  Future<List<String>> pickReportPaths({String? initialDirectory}) async {
    final files = await FilePicker.pickFiles(
      dialogTitle: 'Selecciona uno o varios reportes (.xlsx o .docx)',
      initialDirectory: initialDirectory,
      type: FileType.custom,
      allowedExtensions: FormatUtils.acceptedExtensions,
    );
    return files
        .map((file) => file.path)
        .whereType<String>()
        .toList(growable: false);
  }

  /// Lee los metadatos mínimos del archivo y detecta su formato real.
  Future<SelectedReport> inspect(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw ReportProcessingException(
        ReportErrorCode.readFailed,
        'El archivo ya no existe en la ruta indicada.',
        hint: path,
        fileName: p.basename(path),
      );
    }

    int length;
    List<int> head;
    try {
      length = await file.length();
      final handle = await file.open();
      try {
        head = await handle.read(8);
      } finally {
        await handle.close();
      }
    } on FileSystemException catch (error) {
      throw ReportProcessingException(
        ReportErrorCode.readFailed,
        'No fue posible leer el archivo.',
        hint: error.message,
        fileName: p.basename(path),
        cause: error,
      );
    }

    final name = p.basename(path);
    if (length == 0) {
      throw ReportProcessingException(
        ReportErrorCode.emptyFile,
        'El archivo está vacío (0 bytes).',
        hint: 'Vuelve a copiarlo desde la fuente original.',
        fileName: name,
      );
    }

    return SelectedReport(
      path: file.absolute.path,
      name: name,
      sizeBytes: length,
      format: FormatUtils.detect(fileName: name, bytes: head),
    );
  }

  /// Igual que [inspect] pero devuelve `null` en lugar de lanzar excepción.
  Future<SelectedReport?> tryInspect(String path) async {
    try {
      return await inspect(path);
    } on ReportProcessingException {
      return null;
    }
  }

  Future<Uint8List> readBytes(String path) async {
    try {
      return await File(path).readAsBytes();
    } on FileSystemException catch (error) {
      throw ReportProcessingException(
        ReportErrorCode.readFailed,
        'No fue posible leer el contenido del archivo.',
        hint: error.message,
        fileName: p.basename(path),
        cause: error,
      );
    }
  }

  /// Abre el selector de imágenes para el logo.
  Future<String?> pickLogo({String? initialDirectory}) async {
    final file = await FilePicker.pickFile(
      dialogTitle: 'Selecciona el logo de la empresa',
      initialDirectory: initialDirectory,
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'gif', 'bmp'],
    );
    return file?.path;
  }

  /// Abre el selector de carpetas (destino de los reportes).
  Future<String?> pickDirectory({String? initialDirectory}) {
    return FilePicker.getDirectoryPath(
      dialogTitle: 'Selecciona la carpeta de salida',
      initialDirectory: initialDirectory,
    );
  }

  /// Valida que el logo exista y que su contenido sea una imagen soportada.
  Future<Uint8List> readLogo(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw ReportProcessingException(
        ReportErrorCode.missingLogo,
        'El logo configurado ya no existe.',
        hint: 'Selecciona un logo nuevo en Configuración. Ruta: $path',
      );
    }
    final bytes = await readBytes(path);
    if (ImageSizeReader.detectExtension(bytes) == null) {
      throw const ReportProcessingException(
        ReportErrorCode.missingLogo,
        'El archivo del logo no es una imagen válida.',
        hint: 'Usa una imagen PNG o JPG con fondo transparente o blanco.',
      );
    }
    return bytes;
  }

  /// Calcula la ruta de salida evitando sobrescribir archivos existentes.
  ///
  /// Si [outputDirectory] es `null` el reporte se guarda junto al original.
  Future<String> resolveOutputPath(
    SelectedReport report, {
    String? outputDirectory,
    String suffix = '_ES',
  }) async {
    final directory =
        (outputDirectory == null || outputDirectory.trim().isEmpty)
        ? report.directory
        : outputDirectory.trim();
    final fileName = FormatUtils.suggestedOutputName(
      report.name,
      format: report.format,
      suffix: suffix,
    );
    var candidate = p.join(directory, fileName);
    var counter = 2;
    while (await File(candidate).exists() && counter <= 999) {
      final stem = p.basenameWithoutExtension(fileName);
      candidate = p.join(directory, '$stem ($counter)${p.extension(fileName)}');
      counter++;
    }
    return candidate;
  }

  /// Escribe los bytes del reporte generado.
  Future<String> writeOutput(String path, List<int> bytes) async {
    final file = File(path);
    try {
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } on FileSystemException catch (error) {
      throw ReportProcessingException(
        ReportErrorCode.writeFailed,
        'No fue posible guardar el reporte generado.',
        hint:
            'Verifica que la carpeta exista y que tengas permisos de '
            'escritura. Detalle: ${error.message}',
        fileName: p.basename(path),
        cause: error,
      );
    }
  }

  /// Pregunta al usuario dónde guardar un archivo ya generado.
  ///
  /// Devuelve la ruta elegida o `null` si el usuario cancela.
  Future<String?> saveAs({
    required String fileName,
    required List<int> bytes,
    String? initialDirectory,
  }) async {
    final isDocx = p.extension(fileName).toLowerCase() == '.docx';
    final uri = await FilePicker.saveFile(
      dialogTitle: 'Guardar reporte como…',
      fileName: fileName,
      bytes: Uint8List.fromList(bytes),
      initialDirectory: initialDirectory,
      mimeType: isDocx
          ? 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
          : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
    if (uri == null) {
      return null;
    }
    return uri.scheme == 'file' ? uri.toFilePath() : uri.toString();
  }
}
