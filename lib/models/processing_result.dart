import '../core/format_utils.dart';

/// Estado del procesamiento de un archivo dentro de un lote.
enum ProcessingStatus {
  pending,
  processing,
  success,
  warning,
  failed,
  cancelled,
}

/// Resultado de procesar y guardar un reporte.
class ProcessingResult {
  const ProcessingResult({
    required this.sourcePath,
    required this.sourceName,
    required this.format,
    required this.status,
    this.outputPath,
    this.translatedItems = 0,
    this.untranslatedItems = 0,
    this.warnings = const [],
    this.errorCode,
    this.errorMessage,
    this.errorHint,
  });

  final String sourcePath;
  final String sourceName;
  final ReportFormat format;
  final ProcessingStatus status;
  final String? outputPath;

  /// Etiquetas/celdas traducidas.
  final int translatedItems;

  /// Elementos con texto sin traducir (chino restante, por ejemplo).
  final int untranslatedItems;

  final List<String> warnings;
  final String? errorCode;
  final String? errorMessage;
  final String? errorHint;

  bool get isSuccess =>
      status == ProcessingStatus.success || status == ProcessingStatus.warning;

  bool get hasWarnings => warnings.isNotEmpty;

  String get outputName =>
      outputPath == null ? '' : outputPath!.split(RegExp(r'[\\/]')).last;

  ProcessingResult copyWith({
    ProcessingStatus? status,
    String? outputPath,
    int? translatedItems,
    int? untranslatedItems,
    List<String>? warnings,
    String? errorCode,
    String? errorMessage,
    String? errorHint,
  }) {
    return ProcessingResult(
      sourcePath: sourcePath,
      sourceName: sourceName,
      format: format,
      status: status ?? this.status,
      outputPath: outputPath ?? this.outputPath,
      translatedItems: translatedItems ?? this.translatedItems,
      untranslatedItems: untranslatedItems ?? this.untranslatedItems,
      warnings: warnings ?? this.warnings,
      errorCode: errorCode ?? this.errorCode,
      errorMessage: errorMessage ?? this.errorMessage,
      errorHint: errorHint ?? this.errorHint,
    );
  }
}
