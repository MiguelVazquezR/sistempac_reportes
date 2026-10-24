import 'package:path/path.dart' as p;

/// Formatos que la aplicación reconoce al abrir un archivo.
enum ReportFormat {
  /// Libro de Excel moderno (OOXML).
  xlsx,

  /// Documento de Word moderno (OOXML).
  docx,

  /// Libro de Excel 97-2003 (OLE). Requiere conversión manual.
  legacyXls,

  /// Documento de Word 97-2003 (OLE). Se convierte a `.docx` automáticamente.
  legacyDoc,

  /// Formato no soportado o desconocido.
  unknown,
}

/// Utilidades de detección y nombrado de archivos de reporte.
abstract final class FormatUtils {
  /// Firma de los documentos OLE2 (.xls, .doc, .ppt antiguos).
  static const List<int> oleSignature = [
    0xD0,
    0xCF,
    0x11,
    0xE0,
    0xA1,
    0xB1,
    0x1A,
    0xE1,
  ];

  /// Firma local de un archivo ZIP (`PK\x03\x04`), usada por OOXML.
  static const List<int> zipSignature = [0x50, 0x4B, 0x03, 0x04];

  /// Extensiones que el usuario puede seleccionar en el diálogo nativo.
  static const List<String> supportedExtensions = ['xlsx', 'docx'];

  /// Extensiones que se reconocen pero necesitan conversión previa.
  static const List<String> legacyExtensions = ['xls', 'doc'];

  /// Todas las extensiones aceptadas por el selector de archivos.
  static const List<String> acceptedExtensions = ['xlsx', 'docx', 'xls', 'doc'];

  static String extensionOf(String fileName) {
    final ext = p.extension(fileName);
    return ext.isEmpty ? '' : ext.substring(1).toLowerCase();
  }

  static bool startsWith(List<int> bytes, List<int> signature) {
    if (bytes.length < signature.length) {
      return false;
    }
    for (var i = 0; i < signature.length; i++) {
      if (bytes[i] != signature[i]) {
        return false;
      }
    }
    return true;
  }

  static bool isOle(List<int> bytes) => startsWith(bytes, oleSignature);

  static bool isZip(List<int> bytes) => startsWith(bytes, zipSignature);

  static ReportFormat formatForExtension(String extension) {
    switch (extension.toLowerCase()) {
      case 'xlsx':
      case 'xlsm':
        return ReportFormat.xlsx;
      case 'docx':
        return ReportFormat.docx;
      case 'xls':
        return ReportFormat.legacyXls;
      case 'doc':
        return ReportFormat.legacyDoc;
      default:
        return ReportFormat.unknown;
    }
  }

  /// Detecta el formato combinando la extensión con los primeros bytes.
  ///
  /// La firma OLE tiene prioridad porque un archivo `.xlsx` renombrado desde
  /// un `.xls` mantiene su extensión "moderna" pero su contenido es antiguo.
  static ReportFormat detect({
    required String fileName,
    required List<int> bytes,
  }) {
    final ext = extensionOf(fileName);
    final byExtension = formatForExtension(ext);

    if (isOle(bytes)) {
      return ext == 'doc' || ext == 'docx'
          ? ReportFormat.legacyDoc
          : ReportFormat.legacyXls;
    }

    if (isZip(bytes)) {
      // Un ZIP con extensión desconocida se deja como desconocido: el
      // procesador valida el contenido (xl/workbook.xml o word/document.xml).
      return byExtension == ReportFormat.legacyXls ||
              byExtension == ReportFormat.legacyDoc
          ? ReportFormat.unknown
          : byExtension;
    }

    return ReportFormat.unknown;
  }

  static bool isLegacy(ReportFormat format) =>
      format == ReportFormat.legacyXls || format == ReportFormat.legacyDoc;

  static bool isSupported(ReportFormat format) =>
      format == ReportFormat.xlsx || format == ReportFormat.docx;

  /// Formatos antiguos que la aplicación convierte automáticamente.
  ///
  /// Sólo `.doc` puede convertirse a `.docx` con Word o LibreOffice; `.xls`
  /// sigue requiriendo la conversión manual desde Excel.
  static bool isConvertible(ReportFormat format) =>
      format == ReportFormat.legacyDoc;

  /// Formatos antiguos que el usuario debe convertir por su cuenta.
  static bool needsManualConversion(ReportFormat format) =>
      format == ReportFormat.legacyXls;

  /// Formatos que el lote puede procesar (directamente o tras convertir).
  static bool isProcessable(ReportFormat format) =>
      isSupported(format) || isConvertible(format);

  /// Nombre legible del formato para mensajes de la interfaz.
  static String label(ReportFormat format) {
    switch (format) {
      case ReportFormat.xlsx:
        return 'Excel (.xlsx)';
      case ReportFormat.docx:
        return 'Word (.docx)';
      case ReportFormat.legacyXls:
        return 'Excel 97-2003 (.xls)';
      case ReportFormat.legacyDoc:
        return 'Word 97-2003 (.doc)';
      case ReportFormat.unknown:
        return 'Formato desconocido';
    }
  }

  /// Extensión de salida esperada (con punto) para un formato soportado.
  ///
  /// Los documentos `.doc` se convierten a `.docx` antes de procesarse, por lo
  /// que su resultado también es un `.docx`.
  static String outputExtension(ReportFormat format) {
    switch (format) {
      case ReportFormat.docx:
      case ReportFormat.legacyDoc:
        return '.docx';
      case ReportFormat.xlsx:
      case ReportFormat.legacyXls:
      default:
        return '.xlsx';
    }
  }

  /// Construye el nombre de salida, por ejemplo `reporte_123_ES.xlsx`.
  static String suggestedOutputName(
    String sourceFileName, {
    ReportFormat format = ReportFormat.unknown,
    String suffix = '_ES',
  }) {
    final extension = format == ReportFormat.unknown
        ? p.extension(sourceFileName)
        : outputExtension(format);
    final stem = p.basenameWithoutExtension(sourceFileName).trim();
    final safeStem = stem.isEmpty ? 'reporte' : stem;
    return '$safeStem$suffix$extension';
  }

  /// Tamaño en bytes con formato humano (`1.2 MB`).
  static String formatFileSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    const units = ['KB', 'MB', 'GB'];
    var value = bytes / 1024;
    var unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex++;
    }
    final decimals = value >= 10 ? 0 : 1;
    return '${value.toStringAsFixed(decimals)} ${units[unitIndex]}';
  }

  /// Quita caracteres no permitidos en nombres de archivo de Windows.
  static String sanitizeFileStem(String value) {
    final cleaned = value
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned.isEmpty ? 'reporte' : cleaned;
  }
}
