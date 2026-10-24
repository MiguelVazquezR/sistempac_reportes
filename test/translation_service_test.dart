import 'package:flutter_test/flutter_test.dart';
import 'package:reportes_sistempac/services/translation/translation_service.dart';

void main() {
  final service = TranslationService();

  group('TranslationService', () {
    test('traduce etiquetas chinas exactas', () {
      expect(service.translate('测试报告').text, 'Reporte de prueba');
      expect(service.translate('抗拉强度').text, 'Resistencia a la tracción');
      expect(service.translate('伸长率').text, 'Alargamiento');
    });

    test('traduce etiquetas inglesas exactas', () {
      expect(service.translate('Customer').text, 'Cliente');
      expect(service.translate('Test Report').text, 'Reporte de prueba');
    });

    test('conserva el valor posterior a los dos puntos', () {
      final outcome = service.translate('测试日期：2024-05-01');
      expect(outcome.changed, isTrue);
      expect(outcome.text, 'Fecha de prueba:2024-05-01');
    });

    test('conserva los dos puntos finales', () {
      expect(service.translate('报告编号:').text, 'N.º de reporte:');
      expect(service.translate('Report No.:').text, 'N.º de reporte:');
    });

    test('traduce etiquetas con unidades entre paréntesis', () {
      expect(service.translate('Max Force (N)').text, 'Fuerza máxima (N)');
      expect(service.translate('厚度 (mm)').text, 'Espesor (mm)');
    });

    test('traduce etiquetas compuestas separadas por barra', () {
      expect(service.translate('宽度/厚度').text, 'Ancho/Espesor');
    });

    test('reemplaza términos dentro de frases largas', () {
      expect(
        service.translate('抗拉强度 (MPa)').text,
        'Resistencia a la tracción (MPa)',
      );
      expect(
        service.translate('Elongation at Break (%)').text,
        'Alargamiento a la rotura (%)',
      );
    });

    test('respeta la numeración inicial', () {
      expect(service.translate('1. 测试日期').text, '1. Fecha de prueba');
    });

    test('no modifica números ni textos ya traducidos', () {
      expect(service.translate('12.5').changed, isFalse);
      expect(service.translate('Resistencia a la tracción').changed, isFalse);
      expect(service.translate('2024-05-01').changed, isFalse);
    });

    test('marca el chino que no pudo traducirse', () {
      final outcome = service.translate('未知文本');
      expect(outcome.changed, isFalse);
      expect(outcome.untranslatedCjk, isTrue);
      expect(TranslationService.containsCjk('abc'), isFalse);
    });

    test('traduce nombres de hoja con límites de Excel', () {
      expect(service.translateSheetName('测试报告'), 'Reporte de prueba');
      expect(service.translateSheetName('Data 2024'), 'Data 2024');
    });
  });
}
