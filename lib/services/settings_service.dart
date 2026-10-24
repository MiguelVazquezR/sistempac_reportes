import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';

/// Persistencia de la configuración en `shared_preferences`.
class SettingsService {
  static const String storageKey = 'reportes_sistempac.settings.v1';

  /// Carga la configuración; devuelve valores por defecto si no existe o está
  /// corrupta. Un logo eliminado del disco se descarta silenciosamente.
  Future<AppSettings> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(storageKey);
    if (raw == null || raw.isEmpty) {
      return AppSettings.empty;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return AppSettings.empty;
      }
      final settings = AppSettings.fromJson(decoded);
      if (settings.hasLogo && !File(settings.logoPath!).existsSync()) {
        return settings.copyWith(clearLogoPath: true);
      }
      return settings;
    } on FormatException {
      return AppSettings.empty;
    }
  }

  Future<void> save(AppSettings settings) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(storageKey, jsonEncode(settings.toJson()));
  }

  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(storageKey);
  }
}
