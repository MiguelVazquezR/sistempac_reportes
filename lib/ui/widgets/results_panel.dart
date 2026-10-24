import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../models/processing_result.dart';
import 'status_banner.dart';

/// Resultados del último lote procesado.
class ResultsPanel extends StatelessWidget {
  const ResultsPanel({
    super.key,
    required this.results,
    required this.onSaveAs,
    required this.onReveal,
    this.enabled = true,
  });

  final List<ProcessingResult> results;
  final ValueChanged<ProcessingResult> onSaveAs;
  final ValueChanged<String> onReveal;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final success = results.where((result) => result.isSuccess).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              success == results.length
                  ? Icons.verified_outlined
                  : Icons.fact_check_outlined,
              size: 20,
              color: AppTheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              'Resultados',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$success de ${results.length} correctos',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (final result in results)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ResultCard(
              result: result,
              enabled: enabled,
              onSaveAs: () => onSaveAs(result),
              onReveal: result.outputPath == null
                  ? null
                  : () => onReveal(result.outputPath!),
            ),
          ),
      ],
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.result,
    required this.enabled,
    required this.onSaveAs,
    required this.onReveal,
  });

  final ProcessingResult result;
  final bool enabled;
  final VoidCallback onSaveAs;
  final VoidCallback? onReveal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final severity = switch (result.status) {
      ProcessingStatus.success => BannerSeverity.success,
      ProcessingStatus.warning => BannerSeverity.warning,
      ProcessingStatus.failed => BannerSeverity.error,
      ProcessingStatus.cancelled => BannerSeverity.info,
      _ => BannerSeverity.info,
    };
    final color = switch (severity) {
      BannerSeverity.success => AppTheme.success,
      BannerSeverity.warning => AppTheme.warning,
      BannerSeverity.error => AppTheme.danger,
      BannerSeverity.info => AppTheme.accent,
    };
    final icon = switch (result.status) {
      ProcessingStatus.success => Icons.check_circle_outline,
      ProcessingStatus.warning => Icons.warning_amber_rounded,
      ProcessingStatus.failed => Icons.error_outline,
      ProcessingStatus.cancelled => Icons.info_outline,
      _ => Icons.hourglass_empty,
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        result.sourceName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (result.outputName.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Generado: ${result.outputName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (result.isSuccess && result.translatedItems > 0)
                  _MiniChip(
                    label: '${result.translatedItems} traducidos',
                    color: AppTheme.success,
                  ),
                if (result.isSuccess && result.untranslatedItems > 0) ...[
                  const SizedBox(width: 6),
                  _MiniChip(
                    label: '${result.untranslatedItems} sin traducir',
                    color: AppTheme.warning,
                  ),
                ],
                if (result.isSuccess && result.convertedFromLegacy) ...[
                  const SizedBox(width: 6),
                  const _MiniChip(
                    label: 'convertido de .doc',
                    color: AppTheme.accent,
                  ),
                ],
              ],
            ),
            if (result.errorMessage != null) ...[
              const SizedBox(height: 10),
              Text(
                result.errorMessage!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppTheme.danger,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (result.errorHint != null && result.errorHint!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    result.errorHint!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
            if (result.warnings.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final warning in result.warnings)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.info_outline,
                        size: 14,
                        color: AppTheme.warning,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          warning,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            if (result.isSuccess && result.outputPath != null) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: enabled ? onReveal : null,
                    icon: const Icon(Icons.folder_open_outlined, size: 18),
                    label: const Text('Mostrar en carpeta'),
                  ),
                  const SizedBox(width: 6),
                  OutlinedButton.icon(
                    onPressed: enabled ? onSaveAs : null,
                    icon: const Icon(Icons.save_alt, size: 18),
                    label: const Text('Guardar como…'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
