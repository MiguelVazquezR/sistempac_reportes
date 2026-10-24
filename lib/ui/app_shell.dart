import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../state/processing_controller.dart';
import '../state/settings_controller.dart';
import 'home_page.dart';
import 'settings_page.dart';

/// Estructura principal: barra superior, navegación lateral y páginas.
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.settingsController,
    required this.processingController,
  });

  final SettingsController settingsController;
  final ProcessingController processingController;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;

  void _goTo(int index) {
    if (_selectedIndex == index) {
      return;
    }
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        toolbarHeight: 64,
        titleSpacing: 20,
        title: Row(
          children: [
            const Icon(Icons.insights_outlined, size: 26),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Optimizador de Reportes de Tensión',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Traduce, limpia y personaliza tus reportes de flejes plásticos',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: Colors.white.withValues(alpha: 0.78)),
                ),
              ],
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Tooltip(
              message: 'Configuración',
              child: IconButton(
                onPressed: () => _goTo(1),
                icon: const Icon(Icons.settings_outlined),
              ),
            ),
          ),
        ],
      ),
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: _goTo,
            backgroundColor: Colors.white,
            labelType: NavigationRailLabelType.all,
            indicatorColor: AppTheme.accent.withValues(alpha: 0.14),
            leading: const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Icon(Icons.description_outlined, color: AppTheme.primary),
            ),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.playlist_add_outlined),
                selectedIcon: Icon(Icons.playlist_add_check),
                label: Text('Procesar'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.tune_outlined),
                selectedIcon: Icon(Icons.tune),
                label: Text('Ajustes'),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: [
                HomePage(
                  settingsController: widget.settingsController,
                  processingController: widget.processingController,
                  onOpenSettings: () => _goTo(1),
                ),
                SettingsPage(
                  settingsController: widget.settingsController,
                  onBack: () => _goTo(0),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
