import 'dart:typed_data';

import '../core/format_utils.dart';
import '../core/report_processing_exception.dart';
import '../models/processing_options.dart';
import '../models/selected_report.dart';
import 'docx_report_processor.dart';
import 'excel_report_processor.dart';

/// Punto de entrada único del procesamiento de reportes.
///
/// Selecciona el procesador según el formato real del archivo y normaliza los
/// errores de formato antiguo o desconocido.
class ReportProcessor {
  ReportProcessor({
    ExcelReportProcessor? excelProcessor,
    DocxReportProcessor? docxProcessor,
  }) : _excelProcessor = excelProcessor ?? ExcelReportProcessor(),
       _docxProcessor = docxProcessor ?? DocxReportProcessor();

  final ExcelReportProcessor _excelProcessor;
  final DocxReportProcessor _docxProcessor;

  ProcessedReport process({
    required SelectedReport file,
    required ProcessingOptions options,
    required Uint8List bytes,
  }) {
    switch (file.format) {
      case ReportFormat.xlsx:
        return _excelProcessor.process(
          bytes: bytes,
          fileName: file.name,
          options: options,
        );
      case ReportFormat.docx:
        return _docxProcessor.process(
          bytes: bytes,
          fileName: file.name,
          options: options,
        );
      case ReportFormat.legacyXls:
      case ReportFormat.legacyDoc:
        throw ReportProcessingException(
          ReportErrorCode.legacyNeedsConversion,
          'El archivo está en un formato antiguo que no se puede convertir '
          'automáticamente.',
          hint:
              'Ábrelo en ${file.format == ReportFormat.legacyDoc ? 'Word' : 'Excel'} '
              'y usa "Guardar como…" para crear un archivo '
              '${file.format == ReportFormat.legacyDoc ? '.docx' : '.xlsx'}.',
          fileName: file.name,
        );
      case ReportFormat.unknown:
        throw ReportProcessingException(
          ReportErrorCode.unsupportedFormat,
          'El formato del archivo no es compatible.',
          hint:
              'Solo se aceptan reportes .xlsx o .docx. Si el archivo está '
              'protegido o dañado, ábrelo y guárdalo de nuevo desde '
              'Excel o Word.',
          fileName: file.name,
        );
    }
  }
}
