import 'package:flutter/material.dart';

import 'core/app_theme.dart';
import 'state/processing_controller.dart';
import 'state/settings_controller.dart';
import 'ui/app_shell.dart';

/// Raíz de la aplicación.
class ReportesSistempacApp extends StatefulWidget {
  const ReportesSistempacApp({super.key});

  @override
  State<ReportesSistempacApp> createState() => _ReportesSistempacAppState();
}

class _ReportesSistempacAppState extends State<ReportesSistempacApp> {
  late final SettingsController _settingsController;
  late final ProcessingController _processingController;

  @override
  void initState() {
    super.initState();
    _settingsController = SettingsController();
    _processingController = ProcessingController();
    _settingsController.load();
  }

  @override
  void dispose() {
    _settingsController.dispose();
    _processingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Optimizador de Reportes de Tensión',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: AppShell(
        settingsController: _settingsController,
        processingController: _processingController,
      ),
    );
  }
}
