import 'package:flutter/foundation.dart';

import '../models/app_settings.dart';
import '../services/settings_service.dart';

/// Mantiene la configuración en memoria y la persiste en disco.
class SettingsController extends ChangeNotifier {
  SettingsController({SettingsService? service})
    : _service = service ?? SettingsService();

  final SettingsService _service;

  AppSettings _settings = AppSettings.empty;
  bool _isLoading = true;
  bool _isSaving = false;

  AppSettings get settings => _settings;

  bool get isLoading => _isLoading;

  bool get isSaving => _isSaving;

  /// `true` cuando la configuración mínima ya permite procesar.
  bool get isReady => !_isLoading;

  Future<void> load() async {
    _isLoading = true;
    notifyListeners();
    try {
      _settings = await _service.load();
    } catch (_) {
      _settings = AppSettings.empty;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> update(AppSettings next) async {
    if (next == _settings) {
      return;
    }
    _settings = next;
    _isSaving = true;
    notifyListeners();
    try {
      await _service.save(next);
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<void> updateField({
    String? companyName,
    String? defaultTitle,
    String? logoPath,
    String? outputDirectory,
    bool? translateContent,
    bool? addBranding,
    bool? replaceLogo,
    bool clearLogoPath = false,
    bool clearOutputDirectory = false,
  }) {
    return update(
      _settings.copyWith(
        companyName: companyName,
        defaultTitle: defaultTitle,
        logoPath: logoPath,
        outputDirectory: outputDirectory,
        translateContent: translateContent,
        addBranding: addBranding,
        replaceLogo: replaceLogo,
        clearLogoPath: clearLogoPath,
        clearOutputDirectory: clearOutputDirectory,
      ),
    );
  }
}
