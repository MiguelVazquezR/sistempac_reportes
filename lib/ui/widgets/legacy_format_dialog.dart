import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/format_utils.dart';

/// Explica cómo convertir un `.xls`/`.doc` antiguo a `.xlsx`/`.docx`.
Future<void> showLegacyFormatDialog(
  BuildContext context, {
  required String fileName,
  required ReportFormat format,
}) {
  final isWord = format == ReportFormat.legacyDoc;
  final application = isWord ? 'Word' : 'Excel';
  final targetExtension = isWord ? '.docx' : '.xlsx';
  final description = isWord
      ? 'Los documentos .doc se convierten a .docx automáticamente al generar '
            'los reportes. Si la conversión falla, guarda una copia con estos '
            'pasos y arrástrala de nuevo.'
      : 'Este archivo es un ${FormatUtils.label(format)} y no se puede '
            'convertir automáticamente. Conviértelo una vez y el optimizador '
            'conservará todo el formato.';
  final steps = <String>[
    'Abre "$fileName" en $application.',
    'Entra en Archivo → Guardar como (o "Guardar una copia").',
    'Selecciona el tipo de archivo "$targetExtension".',
    'Guarda la copia y arrástrala de nuevo a esta ventana.',
  ];

  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final theme = Theme.of(dialogContext);
      return AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.history_toggle_off, color: AppTheme.warning),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Formato antiguo detectado',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(description, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 16),
              for (var index = 0; index < steps.length; index++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${index + 1}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AppTheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          steps[index],
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Entendido'),
          ),
        ],
      );
    },
  );
}
