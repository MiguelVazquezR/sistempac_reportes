import 'package:flutter/material.dart';

import '../../core/app_theme.dart';

/// Tonos disponibles para los mensajes de estado.
enum BannerSeverity { info, success, warning, error }

/// Mensaje destacado con icono, texto y detalles opcionales.
class StatusBanner extends StatelessWidget {
  const StatusBanner({
    super.key,
    required this.message,
    this.severity = BannerSeverity.info,
    this.details = const [],
    this.action,
  });

  final String message;
  final BannerSeverity severity;
  final List<String> details;
  final Widget? action;

  Color get _color {
    switch (severity) {
      case BannerSeverity.info:
        return AppTheme.accent;
      case BannerSeverity.success:
        return AppTheme.success;
      case BannerSeverity.warning:
        return AppTheme.warning;
      case BannerSeverity.error:
        return AppTheme.danger;
    }
  }

  IconData get _icon {
    switch (severity) {
      case BannerSeverity.info:
        return Icons.info_outline;
      case BannerSeverity.success:
        return Icons.check_circle_outline;
      case BannerSeverity.warning:
        return Icons.warning_amber_rounded;
      case BannerSeverity.error:
        return Icons.error_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _color.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_icon, color: _color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  for (final detail in details)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        detail,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
          if (action != null) ...[const SizedBox(width: 12), action!],
        ],
      ),
    );
  }
}
