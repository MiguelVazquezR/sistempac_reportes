import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/format_utils.dart';
import '../../models/selected_report.dart';

/// Lista de archivos agregados al lote actual.
class SelectedFilesPanel extends StatelessWidget {
  const SelectedFilesPanel({
    super.key,
    required this.files,
    required this.onRemove,
    required this.onClear,
    required this.onLegacyHelp,
    this.enabled = true,
  });

  final List<SelectedReport> files;
  final ValueChanged<SelectedReport> onRemove;
  final VoidCallback onClear;
  final ValueChanged<SelectedReport> onLegacyHelp;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (files.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.inventory_2_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Archivos en el lote (${files.length})',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: enabled ? onClear : null,
                  icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                  label: const Text('Vaciar lista'),
                ),
              ],
            ),
            const Divider(height: 12),
            for (final file in files)
              _FileRow(
                file: file,
                enabled: enabled,
                onRemove: () => onRemove(file),
                onLegacyHelp: () => onLegacyHelp(file),
              ),
          ],
        ),
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.file,
    required this.enabled,
    required this.onRemove,
    required this.onLegacyHelp,
  });

  final SelectedReport file;
  final bool enabled;
  final VoidCallback onRemove;
  final VoidCallback onLegacyHelp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isExcel =
        file.format == ReportFormat.xlsx ||
        file.format == ReportFormat.legacyXls;
    final Color iconColor = file.isProcessable
        ? (isExcel ? AppTheme.success : AppTheme.accent)
        : AppTheme.warning;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isExcel ? Icons.table_chart_outlined : Icons.article_outlined,
              color: iconColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${file.formatLabel} · ${file.readableSize}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (file.isConvertible) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Se convertirá a .docx automáticamente.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppTheme.accent,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (file.needsManualConversion)
            TextButton(
              onPressed: onLegacyHelp,
              child: const Text('Cómo convertir'),
            ),
          IconButton(
            tooltip: 'Quitar de la lista',
            onPressed: enabled ? onRemove : null,
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }
}
