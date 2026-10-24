import 'dart:math' as math;

import 'package:excel/excel.dart';
import 'package:path/path.dart' as p;

import '../core/report_processing_exception.dart';
import '../models/processing_options.dart';
import 'excel_logo_injector.dart';
import 'translation/translation_service.dart';

/// Analiza y reescribe libros `.xlsx` de reportes de tensión.
class ExcelReportProcessor {
  ExcelReportProcessor({
    TranslationService? translationService,
    ExcelLogoInjector? logoInjector,
  }) : _translation = translationService ?? TranslationService(),
       _logoInjector = logoInjector ?? const ExcelLogoInjector();

  final TranslationService _translation;
  final ExcelLogoInjector _logoInjector;

  /// Límites de seguridad para libros con dimensiones "infladas".
  static const int maxRowsToScan = 4000;
  static const int maxColumnsToScan = 80;

  static final ExcelColor _brandColor = ExcelColor.fromHexString('#1F3864');

  ProcessedReport process({
    required List<int> bytes,
    required String fileName,
    required ProcessingOptions options,
  }) {
    if (bytes.isEmpty) {
      throw ReportProcessingException(
        ReportErrorCode.emptyFile,
        'El archivo está vacío (0 bytes).',
        fileName: p.basename(fileName),
      );
    }

    final Excel excel;
    try {
      excel = Excel.decodeBytes(bytes);
    } on UnsupportedError catch (error) {
      throw ReportProcessingException(
        ReportErrorCode.corruptFile,
        'El archivo no es un libro de Excel (.xlsx) válido.',
        hint: 'El formato .xls antiguo debe guardarse como .xlsx desde Excel.',
        fileName: p.basename(fileName),
        cause: error,
      );
    } catch (error) {
      throw ReportProcessingException(
        ReportErrorCode.corruptFile,
        'No fue posible abrir el libro de Excel.',
        hint: 'Verifica que el archivo no esté dañado ni protegido con contraseña.',
        fileName: p.basename(fileName),
        cause: error,
      );
    }

    if (excel.tables.isEmpty) {
      throw ReportProcessingException(
        ReportErrorCode.emptyDocument,
        'El libro no contiene hojas de cálculo.',
        fileName: p.basename(fileName),
      );
    }

    final warnings = <String>[];
    var translatedItems = 0;
    var untranslatedItems = 0;

    if (options.translateContent) {
      for (final sheet in excel.tables.values) {
        final stats = _translateSheet(sheet);
        translatedItems += stats.translated;
        untranslatedItems += stats.untranslated;
      }
      _renameSheets(excel);
    }

    final mainSheet = _pickMainSheet(excel);
    if (mainSheet == null) {
      throw ReportProcessingException(
        ReportErrorCode.emptyDocument,
        'El libro no contiene datos que se puedan procesar.',
        hint:
            'Abre el archivo en Excel para confirmar que las celdas tienen '
            'contenido.',
        fileName: p.basename(fileName),
      );
    }

    var branding = const BrandingPlacement(
      headerPlaced: false,
      logoPlaced: false,
    );
    if (options.addBranding || (options.replaceLogo && options.hasLogo)) {
      branding = _applyBranding(mainSheet.sheet, options, warnings);
    }

    List<int> saved;
    try {
      saved = excel.save(fileName: p.basename(fileName)) ?? bytes;
    } catch (error) {
      throw ReportProcessingException(
        ReportErrorCode.processingFailed,
        'No fue posible reconstruir el libro de Excel.',
        hint:
            'Si el libro contiene gráficos complejos o macros, ábrelo y '
            'guárdalo como .xlsx antes de procesarlo.',
        fileName: p.basename(fileName),
        cause: error,
      );
    }

    var output = saved;
    var logoPlaced = false;
    if (options.hasLogo) {
      final injection = _logoInjector.inject(
        saved,
        logoBytes: options.logoBytes!,
        anchorColumn: mainSheet.maxUsedColumn + 1,
        removeTemplatePictures: options.replaceLogo,
      );
      if (injection.injected) {
        output = injection.bytes;
        logoPlaced = true;
      } else if (injection.warning != null) {
        warnings.add(injection.warning!);
      }
    }

    return ProcessedReport(
      bytes: output,
      warnings: warnings,
      translatedItems: translatedItems,
      untranslatedItems: untranslatedItems,
      branding: BrandingPlacement(
        headerPlaced: branding.headerPlaced,
        logoPlaced: logoPlaced,
        detail: branding.detail,
      ),
    );
  }

  /// Traduce las celdas de texto de una hoja conservando el estilo original.
  ({int translated, int untranslated}) _translateSheet(Sheet sheet) {
    var translated = 0;
    var untranslated = 0;
    final rowCount = math.min(sheet.maxRows, maxRowsToScan);
    final columnCount = math.min(sheet.maxColumns, maxColumnsToScan);

    for (var rowIndex = 0; rowIndex < rowCount; rowIndex++) {
      final cells = sheet.row(rowIndex);
      final lastColumn = math.min(cells.length, columnCount);
      for (var columnIndex = 0; columnIndex < lastColumn; columnIndex++) {
        final cell = cells[columnIndex];
        if (cell == null || cell.value is! TextCellValue) {
          continue;
        }
        final raw = cell.value.toString();
        if (raw.trim().isEmpty) {
          continue;
        }
        final outcome = _translation.translate(raw);
        if (outcome.changed) {
          sheet.updateCell(
            cell.cellIndex,
            TextCellValue(outcome.text),
            cellStyle: cell.cellStyle,
          );
          translated++;
        } else if (outcome.untranslatedCjk) {
          untranslated++;
        }
      }
    }
    return (translated: translated, untranslated: untranslated);
  }

  /// Renombra las hojas con nombres chinos cuando existe traducción.
  void _renameSheets(Excel excel) {
    final names = excel.tables.keys.toList(growable: false);
    final used = names.toSet();
    for (final name in names) {
      final translated = _translation.translateSheetName(name);
      if (translated == name || used.contains(translated)) {
        continue;
      }
      try {
        excel.rename(name, translated);
        used.add(translated);
      } catch (_) {
        // Si el nombre no se puede aplicar se conserva el original.
      }
    }
  }

  _SheetAnalysis? _pickMainSheet(Excel excel) {
    _SheetAnalysis? best;
    for (final sheet in excel.tables.values) {
      final analysis = _analyze(sheet);
      if (analysis == null) {
        continue;
      }
      if (best == null || analysis.filledCells > best.filledCells) {
        best = analysis;
      }
    }
    return best;
  }

  _SheetAnalysis? _analyze(Sheet sheet) {
    final rowCount = math.min(sheet.maxRows, maxRowsToScan);
    final columnCount = math.min(sheet.maxColumns, maxColumnsToScan);
    var firstRow = -1;
    var lastRow = -1;
    var maxColumn = -1;
    var filled = 0;

    for (var rowIndex = 0; rowIndex < rowCount; rowIndex++) {
      final cells = sheet.row(rowIndex);
      final lastColumn = math.min(cells.length, columnCount);
      for (var columnIndex = 0; columnIndex < lastColumn; columnIndex++) {
        final cell = cells[columnIndex];
        if (cell == null || cell.value == null) {
          continue;
        }
        if (cell.value.toString().trim().isEmpty) {
          continue;
        }
        filled++;
        if (firstRow < 0) {
          firstRow = rowIndex;
        }
        lastRow = rowIndex;
        if (columnIndex > maxColumn) {
          maxColumn = columnIndex;
        }
      }
    }

    if (filled == 0 || maxColumn < 0) {
      return null;
    }
    return _SheetAnalysis(
      sheet: sheet,
      firstUsedRow: firstRow,
      lastUsedRow: lastRow,
      maxUsedColumn: maxColumn,
      filledCells: filled,
    );
  }

  /// Escribe empresa y título sin alterar el contenido del reporte.
  BrandingPlacement _applyBranding(
    Sheet sheet,
    ProcessingOptions options,
    List<String> warnings,
  ) {
    final analysis = _analyze(sheet);
    if (analysis == null) {
      return const BrandingPlacement(headerPlaced: false, logoPlaced: false);
    }
    final lines = options.brandingLines;
    if (lines.isEmpty) {
      return BrandingPlacement(
        headerPlaced: false,
        logoPlaced: false,
        detail: 'No hay nombre de empresa ni título configurados.',
      );
    }

    final startRow = analysis.firstUsedRow - lines.length;
    final hasFreeHeaderRows = startRow >= 0;
    final writeRow = hasFreeHeaderRows
        ? startRow
        : math.max(analysis.lastUsedRow + 2, 0);

    for (var index = 0; index < lines.length; index++) {
      sheet.updateCell(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: writeRow + index),
        TextCellValue(lines[index]),
        cellStyle: _brandingStyle(primary: index == 0),
      );
    }

    if (!hasFreeHeaderRows) {
      warnings.add(
        'La hoja "${sheet.sheetName}" no tiene filas libres en el encabezado: '
        'el nombre de la empresa y el título se agregaron al final de la hoja.',
      );
    }

    return BrandingPlacement(
      headerPlaced: true,
      logoPlaced: false,
      detail: hasFreeHeaderRows
          ? 'Marca agregada en las filas ${writeRow + 1}-${writeRow + lines.length}.'
          : 'Marca agregada al final de la hoja (sin espacio en el encabezado).',
    );
  }

  CellStyle _brandingStyle({required bool primary}) {
    return CellStyle(
      bold: true,
      fontSize: primary ? 16 : 12,
      fontColorHex: _brandColor,
      horizontalAlign: HorizontalAlign.Left,
      verticalAlign: VerticalAlign.Center,
    );
  }
}

/// Medidas de ocupación de una hoja, usadas para ubicar la marca y el logo.
class _SheetAnalysis {
  const _SheetAnalysis({
    required this.sheet,
    required this.firstUsedRow,
    required this.lastUsedRow,
    required this.maxUsedColumn,
    required this.filledCells,
  });

  final Sheet sheet;
  final int firstUsedRow;
  final int lastUsedRow;
  final int maxUsedColumn;
  final int filledCells;
}
