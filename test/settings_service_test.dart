import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:reportes_sistempac/models/app_settings.dart';
import 'package:reportes_sistempac/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('devuelve la configuración vacía cuando no hay datos', () async {
    expect(await SettingsService().load(), AppSettings.empty);
  });

  test('guarda y recupera la configuración', () async {
    final service = SettingsService();
    const settings = AppSettings(
      companyName: 'SISTEMPAC',
      defaultTitle: 'Reporte de Prueba de Tensión',
      translateContent: false,
      addBranding: true,
      replaceLogo: false,
    );

    await service.save(settings);
    final loaded = await service.load();

    expect(loaded.companyName, 'SISTEMPAC');
    expect(loaded.defaultTitle, 'Reporte de Prueba de Tensión');
    expect(loaded.translateContent, isFalse);
    expect(loaded.addBranding, isTrue);
    expect(loaded.replaceLogo, isFalse);
  });

  test('descarta un logo que ya no existe en el disco', () async {
    SharedPreferences.setMockInitialValues({
      SettingsService.storageKey: jsonEncode({
        'companyName': 'SISTEMPAC',
        'defaultTitle': 'Reporte',
        'logoPath': r'C:\carpeta\que no existe\logo.png',
      }),
    });

    final settings = await SettingsService().load();
    expect(settings.companyName, 'SISTEMPAC');
    expect(settings.logoPath, isNull);
  });

  test('tolera JSON corrupto', () async {
    SharedPreferences.setMockInitialValues({
      SettingsService.storageKey: 'esto no es json',
    });

    expect(await SettingsService().load(), AppSettings.empty);
  });

  test('AppSettings ignora rutas vacías', () {
    final settings = AppSettings.fromJson({
      'logoPath': '   ',
      'outputDirectory': '',
      'companyName': '  SISTEMPAC  ',
    });
    expect(settings.logoPath, isNull);
    expect(settings.outputDirectory, isNull);
    expect(settings.companyName, 'SISTEMPAC');
  });
}
