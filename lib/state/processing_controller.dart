import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/report_processing_exception.dart';
import '../models/app_settings.dart';
import '../models/processing_options.dart';
import '../models/processing_result.dart';
import '../models/selected_report.dart';
import '../services/file_service.dart';
import '../services/report_processor.dart';

/// Orquesta la selección de archivos, el procesamiento y el guardado.
class ProcessingController extends ChangeNotifier {
  ProcessingController({
    FileService? fileService,
    ReportProcessor? reportProcessor,
  }) : _fileService = fileService ?? FileService(),
       _processor = reportProcessor ?? ReportProcessor();

  final FileService _fileService;
  final ReportProcessor _processor;

  final List<SelectedReport> _files = [];
  final List<ProcessingResult> _results = [];
  final Map<String, List<int>> _generatedBytes = {};
  final List<String> _addErrors = [];

  bool _isProcessing = false;
  String _statusMessage = '';

  List<SelectedReport> get files => List.unmodifiable(_files);

  List<ProcessingResult> get results => List.unmodifiable(_results);

  /// Mensajes de archivos rechazados al agregarlos al lote.
  List<String> get addErrors => List.unmodifiable(_addErrors);

  bool get isProcessing => _isProcessing;

  String get statusMessage => _statusMessage;

  bool get hasFiles => _files.isNotEmpty;

  int get supportedCount => _files.where((file) => file.isSupported).length;

  int get legacyCount => _files.where((file) => file.isLegacy).length;

  bool get canProcess => hasFiles && !_isProcessing && supportedCount > 0;

  void clearAddErrors() {
    if (_addErrors.isEmpty) {
      return;
    }
    _addErrors.clear();
    notifyListeners();
  }

  /// Abre el diálogo nativo y agrega los archivos seleccionados.
  Future<void> pickFiles({String? initialDirectory}) async {
    try {
      final paths = await _fileService.pickReportPaths(
        initialDirectory: initialDirectory,
      );
      if (paths.isNotEmpty) {
        await addReports(paths);
      }
    } on ReportProcessingException catch (error) {
      _addErrors.add(_describeError(error, null));
      notifyListeners();
    }
  }

  /// Inspecciona y agrega rutas (por ejemplo, de "arrastrar y soltar").
  Future<void> addReports(List<String> paths) async {
    if (paths.isEmpty) {
      return;
    }
    for (final path in paths) {
      try {
        final report = await _fileService.inspect(path);
        if (_files.any((existing) => existing == report)) {
          continue;
        }
        _files.add(report);
      } on ReportProcessingException catch (error) {
        _addErrors.add(_describeError(error, p.basename(path)));
      } catch (error) {
        _addErrors.add('$error');
      }
    }
    notifyListeners();
  }

  void removeFile(SelectedReport report) {
    if (_isProcessing) {
      return;
    }
    _files.removeWhere((existing) => existing == report);
    notifyListeners();
  }

  void clearFiles() {
    if (_isProcessing || _files.isEmpty) {
      return;
    }
    _files.clear();
    _results.clear();
    _generatedBytes.clear();
    _statusMessage = '';
    notifyListeners();
  }

  /// Procesa todos los archivos del lote y guarda los resultados.
  Future<void> processAll({
    required AppSettings settings,
    required String title,
  }) async {
    if (!canProcess) {
      return;
    }

    _isProcessing = true;
    _results.clear();
    _generatedBytes.clear();
    _statusMessage = 'Preparando el lote…';
    notifyListeners();

    final globalWarnings = <String>[];
    List<int>? logoBytes;
    if (settings.hasLogo) {
      try {
        logoBytes = await _fileService.readLogo(settings.logoPath!);
      } on ReportProcessingException catch (error) {
        globalWarnings.add(error.message);
      } catch (error) {
        globalWarnings.add('No se pudo leer el logo configurado: $error');
      }
    }

    final options = ProcessingOptions.fromSettings(
      settings,
      title: title,
      logoBytes: logoBytes,
    );

    for (var index = 0; index < _files.length; index++) {
      final file = _files[index];
      _statusMessage =
          'Procesando ${index + 1} de ${_files.length}: ${file.name}';
      notifyListeners();

      try {
        final bytes = await _fileService.readBytes(file.path);
        final processed = _processor.process(
          file: file,
          options: options,
          bytes: bytes,
        );
        final outputPath = await _fileService.resolveOutputPath(
          file,
          outputDirectory: settings.outputDirectory,
        );
        await _fileService.writeOutput(outputPath, processed.bytes);
        _generatedBytes[outputPath] = processed.bytes;

        final warnings = <String>[...globalWarnings, ...processed.warnings];
        _results.add(
          ProcessingResult(
            sourcePath: file.path,
            sourceName: file.name,
            format: file.format,
            status: warnings.isEmpty
                ? ProcessingStatus.success
                : ProcessingStatus.warning,
            outputPath: outputPath,
            translatedItems: processed.translatedItems,
            untranslatedItems: processed.untranslatedItems,
            warnings: warnings,
          ),
        );
      } on ReportProcessingException catch (error) {
        _results.add(_failure(file, error));
      } catch (error) {
        _results.add(
          _failure(
            file,
            ReportProcessingException(
              ReportErrorCode.processingFailed,
              'Ocurrió un error inesperado al procesar el archivo.',
              hint: '$error',
              fileName: file.name,
            ),
          ),
        );
      }
      notifyListeners();
    }

    _isProcessing = false;
    _statusMessage = _summary();
    notifyListeners();
  }

  /// Pregunta dónde guardar un resultado ya generado y actualiza la ruta.
  Future<String?> saveResultAs(ProcessingResult result) async {
    final outputPath = result.outputPath;
    final bytes = outputPath == null ? null : _generatedBytes[outputPath];
    if (outputPath == null || bytes == null) {
      return null;
    }
    try {
      final chosen = await _fileService.saveAs(
        fileName: result.outputName,
        bytes: bytes,
        initialDirectory: p.dirname(outputPath),
      );
      if (chosen == null) {
        return null;
      }
      final saved = await _fileService.writeOutput(chosen, bytes);
      final index = _results.indexOf(result);
      if (index >= 0) {
        _results[index] = result.copyWith(outputPath: saved);
        notifyListeners();
      }
      return saved;
    } on ReportProcessingException catch (error) {
      _addErrors.add(_describeError(error, null));
      notifyListeners();
      return null;
    } catch (error) {
      _addErrors.add('No se pudo guardar la copia: $error');
      notifyListeners();
      return null;
    }
  }

  /// Abre el Explorador de Windows con el archivo seleccionado.
  Future<void> revealInExplorer(String path) async {
    if (path.isEmpty) {
      return;
    }
    try {
      await Process.run('explorer.exe', ['/select,$path']);
    } catch (error) {
      _addErrors.add('No se pudo abrir la carpeta: $error');
      notifyListeners();
    }
  }

  void resetResults() {
    if (_isProcessing) {
      return;
    }
    _results.clear();
    _generatedBytes.clear();
    _statusMessage = '';
    notifyListeners();
  }

  ProcessingResult _failure(
    SelectedReport file,
    ReportProcessingException exception,
  ) {
    return ProcessingResult(
      sourcePath: file.path,
      sourceName: file.name,
      format: file.format,
      status: exception.isCancellation
          ? ProcessingStatus.cancelled
          : ProcessingStatus.failed,
      errorCode: exception.code.name,
      errorMessage: exception.message,
      errorHint: exception.hint,
    );
  }

  String _describeError(ReportProcessingException error, String? fallbackName) {
    final name = error.fileName ?? fallbackName;
    final buffer = StringBuffer();
    if (name != null && name.isNotEmpty) {
      buffer.write('$name: ');
    }
    buffer.write(error.message);
    if (error.hint != null && error.hint!.isNotEmpty) {
      buffer.write(' ${error.hint}');
    }
    return buffer.toString();
  }

  String _summary() {
    if (_results.isEmpty) {
      return '';
    }
    final success = _results.where((result) => result.isSuccess).length;
    final failed = _results.length - success;
    final translated = _results.fold<int>(
      0,
      (total, result) => total + result.translatedItems,
    );
    final buffer = StringBuffer(
      '$success reporte${success == 1 ? '' : 's'} generado'
      '${success == 1 ? '' : 's'}',
    );
    if (failed > 0) {
      buffer.write(' · $failed con error');
    }
    if (translated > 0) {
      buffer.write(' · $translated textos traducidos');
    }
    return buffer.toString();
  }
}
