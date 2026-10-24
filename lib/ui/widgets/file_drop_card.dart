import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import '../../core/app_theme.dart';

/// Zona para arrastrar archivos y botón para abrir el selector nativo.
class FileDropCard extends StatefulWidget {
  const FileDropCard({
    super.key,
    required this.onBrowse,
    required this.onFilesDropped,
    this.enabled = true,
  });

  final VoidCallback onBrowse;
  final ValueChanged<List<String>> onFilesDropped;
  final bool enabled;

  @override
  State<FileDropCard> createState() => _FileDropCardState();
}

class _FileDropCardState extends State<FileDropCard> {
  bool _isHovering = false;

  void _setHovering(bool value) {
    if (_isHovering == value) {
      return;
    }
    setState(() => _isHovering = value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DropTarget(
      enable: widget.enabled,
      onDragEntered: (_) => _setHovering(true),
      onDragExited: (_) => _setHovering(false),
      onDragDone: (details) {
        _setHovering(false);
        final paths = details.files
            .map((file) => file.path)
            .where((path) => path.isNotEmpty)
            .toList(growable: false);
        if (paths.isNotEmpty) {
          widget.onFilesDropped(paths);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 26),
        decoration: BoxDecoration(
          color: _isHovering
              ? AppTheme.accent.withValues(alpha: 0.08)
              : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _isHovering ? AppTheme.accent : AppTheme.border,
            width: _isHovering ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isHovering
                    ? Icons.file_download_outlined
                    : Icons.cloud_upload_outlined,
                size: 30,
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              _isHovering
                  ? 'Suelta los archivos para agregarlos'
                  : 'Arrastra aquí tus reportes',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Archivos .xlsx (Excel) o .docx (Word). Puedes agregar varios a la vez.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: widget.enabled ? widget.onBrowse : null,
              icon: const Icon(Icons.folder_open_outlined, size: 18),
              label: const Text('Seleccionar archivos'),
            ),
          ],
        ),
      ),
    );
  }
}
