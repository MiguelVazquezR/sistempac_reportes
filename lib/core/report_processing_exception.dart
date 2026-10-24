/// Códigos de error controlados por la aplicación.
///
/// Cada código permite mostrar un mensaje claro y accionable al usuario en
/// lugar de un volcado de excepción del procesador de archivos.
enum ReportErrorCode {
  /// La extensión o el contenido del archivo no corresponde a un reporte
  /// soportado (.xlsx o .docx).
  unsupportedFormat,

  /// El archivo es un .xls/.doc antiguo (formato OLE) y requiere convertirse
  /// manualmente a .xlsx/.docx.
  legacyNeedsConversion,

  /// El archivo está dañado o no es un paquete OOXML válido.
  corruptFile,

  /// El archivo está vacío (0 bytes).
  emptyFile,

  /// El libro/hoja no contiene datos que se puedan procesar.
  emptyDocument,

  /// No fue posible leer el archivo desde el disco.
  readFailed,

  /// El logo configurado no existe o no es una imagen válida.
  missingLogo,

  /// No fue posible escribir el archivo de salida.
  writeFailed,

  /// El usuario cerró el diálogo de guardado.
  saveCancelled,

  /// Error inesperado durante el procesamiento.
  processingFailed,
}

/// Excepción de dominio con mensaje en español y pista de solución.
class ReportProcessingException implements Exception {
  const ReportProcessingException(
    this.code,
    this.message, {
    this.hint,
    this.fileName,
    this.cause,
  });

  final ReportErrorCode code;
  final String message;

  /// Texto de ayuda que se muestra debajo del mensaje principal.
  final String? hint;

  /// Nombre del archivo que originó el error (sin ruta completa).
  final String? fileName;

  /// Excepción original, útil para depuración.
  final Object? cause;

  /// Indica si el usuario puede corregir el problema sin soporte técnico.
  bool get isRecoverable =>
      code == ReportErrorCode.legacyNeedsConversion ||
      code == ReportErrorCode.saveCancelled ||
      code == ReportErrorCode.unsupportedFormat;

  /// Indica si el error debe mostrarse como advertencia y no como fallo.
  bool get isCancellation => code == ReportErrorCode.saveCancelled;

  ReportProcessingException withFileName(String name) {
    return ReportProcessingException(
      code,
      message,
      hint: hint,
      fileName: name,
      cause: cause,
    );
  }

  @override
  String toString() => 'ReportProcessingException(${code.name}): $message';
}
