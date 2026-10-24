import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/report_processing_exception.dart';
import '../services/file_service.dart';
import '../state/settings_controller.dart';
import 'widgets/logo_picker.dart';
import 'widgets/status_banner.dart';

/// Página de ajustes: empresa, título, logo y carpeta de salida.
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.settingsController,
    required this.onBack,
  });

  final SettingsController settingsController;
  final VoidCallback onBack;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final FileService _fileService = FileService();
  late final TextEditingController _companyController;
  late final TextEditingController _titleController;
  bool _initialized = false;
  String? _logoError;

  @override
  void initState() {
    super.initState();
    _companyController = TextEditingController();
    _titleController = TextEditingController();
    widget.settingsController.addListener(_syncFromSettings);
    _syncFromSettings();
  }

  @override
  void dispose() {
    widget.settingsController.removeListener(_syncFromSettings);
    _companyController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  void _syncFromSettings() {
    if (_initialized || widget.settingsController.isLoading) {
      return;
    }
    final settings = widget.settingsController.settings;
    _companyController.text = settings.companyName;
    _titleController.text = settings.defaultTitle;
    _initialized = true;
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _pickLogo() async {
    try {
      final path = await _fileService.pickLogo();
      if (path == null) {
        return;
      }
      await _fileService.readLogo(path);
      await widget.settingsController.updateField(logoPath: path);
      if (mounted) {
        setState(() => _logoError = null);
      }
    } on ReportProcessingException catch (error) {
      if (mounted) {
        setState(() => _logoError = error.message);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _logoError = 'No se pudo seleccionar el logo: $error');
      }
    }
  }

  Future<void> _pickOutputDirectory() async {
    try {
      final path = await _fileService.pickDirectory(
        initialDirectory: widget.settingsController.settings.outputDirectory,
      );
      if (path == null) {
        return;
      }
      await widget.settingsController.updateField(outputDirectory: path);
    } catch (error) {
      if (mounted) {
        setState(() => _logoError = 'No se pudo elegir la carpeta: $error');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.settingsController,
      builder: (context, _) {
        final theme = Theme.of(context);
        final controller = widget.settingsController;
        final settings = controller.settings;
        final loading = controller.isLoading;

        return ListView(
          padding: AppTheme.pagePadding,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Configuración de la marca',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Estos datos se aplican a todos los reportes que generes.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: widget.onBack,
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: const Text('Volver a procesar'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (loading)
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: LinearProgressIndicator(minHeight: 2),
              ),
            _SectionCard(
              icon: Icons.business_outlined,
              title: 'Identidad',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _companyController,
                    enabled: !loading,
                    onChanged: (value) =>
                        controller.updateField(companyName: value),
                    decoration: const InputDecoration(
                      labelText: 'Nombre de la empresa',
                      hintText: 'Ej. SISTEMPAC',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _titleController,
                    enabled: !loading,
                    onChanged: (value) =>
                        controller.updateField(defaultTitle: value),
                    decoration: const InputDecoration(
                      labelText: 'Título predeterminado',
                      hintText: 'Ej. Reporte de Prueba de Tensión',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _SectionCard(
              icon: Icons.image_outlined,
              title: 'Logo',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LogoPicker(
                    logoPath: settings.logoPath,
                    enabled: !loading,
                    onPick: _pickLogo,
                    onClear: () {
                      controller.updateField(clearLogoPath: true);
                      setState(() => _logoError = null);
                    },
                  ),
                  if (_logoError != null) ...[
                    const SizedBox(height: 10),
                    StatusBanner(
                      message: _logoError!,
                      severity: BannerSeverity.error,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            _SectionCard(
              icon: Icons.folder_outlined,
              title: 'Carpeta de salida',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    settings.outputDirectory ??
                        'Los reportes se guardan junto al archivo original '
                            'con el sufijo _ES.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: loading ? null : _pickOutputDirectory,
                        icon: const Icon(Icons.folder_open_outlined, size: 18),
                        label: const Text('Elegir carpeta'),
                      ),
                      if (settings.outputDirectory != null)
                        TextButton(
                          onPressed: () => controller.updateField(
                            clearOutputDirectory: true,
                          ),
                          child: const Text('Usar carpeta del original'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _SectionCard(
              icon: Icons.toggle_on_outlined,
              title: 'Comportamiento',
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: settings.translateContent,
                    onChanged: loading
                        ? null
                        : (value) =>
                              controller.updateField(translateContent: value),
                    title: const Text('Traducir textos al español'),
                    subtitle: const Text(
                      'Convierte etiquetas chinas e inglesas conservando los '
                      'valores y el formato de las celdas.',
                    ),
                  ),
                  const Divider(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: settings.addBranding,
                    onChanged: loading
                        ? null
                        : (value) => controller.updateField(addBranding: value),
                    title: const Text('Agregar empresa y título'),
                    subtitle: const Text(
                      'Escribe el nombre de la empresa y el título en el '
                      'encabezado del reporte.',
                    ),
                  ),
                  const Divider(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: settings.replaceLogo,
                    onChanged: loading
                        ? null
                        : (value) => controller.updateField(replaceLogo: value),
                    title: const Text('Reemplazar el logo del reporte'),
                    subtitle: const Text(
                      'Elimina el logo genérico del encabezado antes de '
                      'insertar el tuyo.',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _SectionCard(
              icon: Icons.info_outline,
              title: 'Formatos compatibles',
              child: Text(
                'Se procesan archivos .xlsx y .docx. Los documentos .doc '
                'antiguos se convierten a .docx automáticamente con Microsoft '
                'Word o LibreOffice. Los archivos .xls siguen necesitando la '
                'conversión manual: ábrelos en Excel y usa "Guardar como…".',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}
