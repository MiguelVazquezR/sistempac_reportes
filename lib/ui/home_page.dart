import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../core/app_theme.dart';
import '../models/app_settings.dart';
import '../models/processing_result.dart';
import '../models/selected_report.dart';
import '../state/processing_controller.dart';
import '../state/settings_controller.dart';
import 'widgets/file_drop_card.dart';
import 'widgets/legacy_format_dialog.dart';
import 'widgets/results_panel.dart';
import 'widgets/selected_files_panel.dart';
import 'widgets/status_banner.dart';

/// Página principal: selección de archivos, opciones y resultados.
class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.settingsController,
    required this.processingController,
    required this.onOpenSettings,
  });

  final SettingsController settingsController;
  final ProcessingController processingController;
  final VoidCallback onOpenSettings;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final TextEditingController _titleController;
  final Set<String> _legacyDialogShown = {};
  bool _titleTouched = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(
      text: widget.settingsController.settings.defaultTitle,
    );
    widget.settingsController.addListener(_syncTitleFromSettings);
  }

  @override
  void dispose() {
    widget.settingsController.removeListener(_syncTitleFromSettings);
    _titleController.dispose();
    super.dispose();
  }

  void _syncTitleFromSettings() {
    if (_titleTouched || !mounted) {
      return;
    }
    final defaultTitle = widget.settingsController.settings.defaultTitle;
    if (_titleController.text != defaultTitle) {
      _titleController.text = defaultTitle;
    }
  }

  Future<void> _handlePaths(List<String> paths) async {
    if (paths.isEmpty) {
      return;
    }
    await widget.processingController.addReports(paths);
    if (!mounted) {
      return;
    }
    await _maybeShowLegacyDialog();
  }

  Future<void> _handleBrowse() async {
    await widget.processingController.pickFiles();
    if (!mounted) {
      return;
    }
    await _maybeShowLegacyDialog();
  }

  Future<void> _maybeShowLegacyDialog() async {
    final legacyFiles = widget.processingController.files
        .where((file) => file.isLegacy)
        .toList(growable: false);
    for (final file in legacyFiles) {
      if (_legacyDialogShown.contains(file.identityKey)) {
        continue;
      }
      _legacyDialogShown.add(file.identityKey);
      if (!mounted) {
        return;
      }
      await showLegacyFormatDialog(
        context,
        fileName: file.name,
        format: file.format,
      );
      return;
    }
  }

  Future<void> _handleLegacyHelp(SelectedReport file) {
    return showLegacyFormatDialog(
      context,
      fileName: file.name,
      format: file.format,
    );
  }

  Future<void> _process() async {
    final settings = widget.settingsController.settings;
    final title = _titleController.text.trim();
    await widget.processingController.processAll(
      settings: settings,
      title: title.isEmpty ? settings.defaultTitle : title,
    );
    if (!mounted) {
      return;
    }
    final results = widget.processingController.results;
    if (results.isEmpty) {
      return;
    }
    final failed = results
        .where((result) => result.status == ProcessingStatus.failed)
        .length;
    final message = failed == 0
        ? 'Se generaron ${results.length} reporte${results.length == 1 ? '' : 's'}.'
        : 'Se generaron ${results.length - failed} de ${results.length} reportes.';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.settingsController,
        widget.processingController,
      ]),
      builder: (context, _) {
        final settings = widget.settingsController.settings;
        final processing = widget.processingController;
        final theme = Theme.of(context);

        return Column(
          children: [
            Expanded(
              child: ListView(
                padding: AppTheme.pagePadding,
                children: [
                  if (settings.addBranding && !settings.hasCompanyName) ...[
                    StatusBanner(
                      message:
                          'Personaliza la marca antes de generar los reportes.',
                      severity: BannerSeverity.info,
                      details: const [
                        'Configura el nombre de la empresa y el logo en Ajustes; '
                            'se aplicarán a todos los reportes del lote.',
                      ],
                      action: TextButton(
                        onPressed: widget.onOpenSettings,
                        child: const Text('Abrir ajustes'),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (processing.addErrors.isNotEmpty) ...[
                    StatusBanner(
                      message: 'Algunos archivos no se pudieron agregar.',
                      severity: BannerSeverity.warning,
                      details: processing.addErrors,
                      action: TextButton(
                        onPressed: processing.clearAddErrors,
                        child: const Text('Ocultar'),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  FileDropCard(
                    enabled: !processing.isProcessing,
                    onBrowse: _handleBrowse,
                    onFilesDropped: _handlePaths,
                  ),
                  const SizedBox(height: 20),
                  _buildOptionsCard(context, theme, settings, processing),
                  const SizedBox(height: 20),
                  SelectedFilesPanel(
                    files: processing.files,
                    enabled: !processing.isProcessing,
                    onRemove: processing.removeFile,
                    onClear: processing.clearFiles,
                    onLegacyHelp: _handleLegacyHelp,
                  ),
                  if (processing.files.isNotEmpty) const SizedBox(height: 20),
                  ResultsPanel(
                    results: processing.results,
                    enabled: !processing.isProcessing,
                    onSaveAs: (result) async {
                      final saved = await processing.saveResultAs(result);
                      if (!context.mounted) {
                        return;
                      }
                      if (saved != null) {
                        ScaffoldMessenger.of(context)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(
                            SnackBar(
                              content: Text(
                                'Copia guardada en ${p.basename(saved)}.',
                              ),
                            ),
                          );
                      }
                    },
                    onReveal: processing.revealInExplorer,
                  ),
                ],
              ),
            ),
            _buildActionBar(context, theme, processing),
          ],
        );
      },
    );
  }

  Widget _buildOptionsCard(
    BuildContext context,
    ThemeData theme,
    AppSettings settings,
    ProcessingController processing,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tune, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Opciones del lote',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _titleController,
              enabled: !processing.isProcessing,
              onChanged: (_) => _titleTouched = true,
              decoration: const InputDecoration(
                labelText: 'Título que aparecerá en los reportes',
                hintText: 'Ej. Reporte de Prueba de Tensión',
                prefixIcon: Icon(Icons.title, size: 20),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InfoPill(
                  icon: Icons.business_outlined,
                  label: settings.hasCompanyName
                      ? settings.companyName
                      : 'Sin empresa configurada',
                  active: settings.hasCompanyName,
                ),
                _InfoPill(
                  icon: Icons.image_outlined,
                  label: settings.hasLogo
                      ? p.basename(settings.logoPath!)
                      : 'Sin logo',
                  active: settings.hasLogo,
                ),
                _InfoPill(
                  icon: Icons.translate,
                  label: settings.translateContent
                      ? 'Traducción al español'
                      : 'Sin traducción',
                  active: settings.translateContent,
                ),
                _InfoPill(
                  icon: Icons.folder_outlined,
                  label: settings.outputDirectory == null
                      ? 'Guardar junto al original'
                      : p.basename(settings.outputDirectory!),
                  active: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionBar(
    BuildContext context,
    ThemeData theme,
    ProcessingController processing,
  ) {
    final statusText = processing.statusMessage.isNotEmpty
        ? processing.statusMessage
        : _idleHint(processing);

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          if (processing.isProcessing)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            )
          else
            Icon(
              Icons.info_outline,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              statusText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 16),
          FilledButton.icon(
            onPressed: processing.canProcess ? _process : null,
            icon: processing.isProcessing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.auto_awesome, size: 18),
            label: Text(
              processing.hasFiles
                  ? 'Generar reportes (${processing.supportedCount})'
                  : 'Generar reportes',
            ),
          ),
        ],
      ),
    );
  }

  String _idleHint(ProcessingController processing) {
    if (!processing.hasFiles) {
      return 'Agrega al menos un archivo .xlsx o .docx para comenzar.';
    }
    if (processing.supportedCount == 0) {
      return 'Los archivos agregados están en formato antiguo: conviértelos a '
          '.xlsx o .docx para procesarlos.';
    }
    final pendientes = processing.supportedCount;
    return 'Listo para generar $pendientes reporte${pendientes == 1 ? '' : 's'}.';
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({
    required this.icon,
    required this.label,
    required this.active,
  });

  final IconData icon;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = active
        ? AppTheme.primary
        : theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
