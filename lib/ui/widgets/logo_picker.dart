import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/app_theme.dart';

/// Vista previa y acciones para el logo de la empresa.
class LogoPicker extends StatelessWidget {
  const LogoPicker({
    super.key,
    required this.logoPath,
    required this.onPick,
    required this.onClear,
    this.enabled = true,
  });

  final String? logoPath;
  final VoidCallback onPick;
  final VoidCallback onClear;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasLogo = logoPath != null && logoPath!.isNotEmpty;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 104,
          height: 76,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: const Color(0xFFFAFBFD),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border),
          ),
          child: hasLogo
              ? Padding(
                  padding: const EdgeInsets.all(8),
                  child: Image.file(
                    File(logoPath!),
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => Icon(
                      Icons.broken_image_outlined,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : Icon(
                  Icons.image_outlined,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hasLogo ? logoPath!.split(RegExp(r'[\\/]')).last : 'Sin logo',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'PNG o JPG con fondo transparente o blanco. Se insertará en el '
                'encabezado del reporte.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: enabled ? onPick : null,
                    icon: const Icon(Icons.upload_file_outlined, size: 18),
                    label: Text(hasLogo ? 'Cambiar logo' : 'Elegir logo'),
                  ),
                  if (hasLogo) ...[
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: enabled ? onClear : null,
                      child: const Text('Quitar'),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
