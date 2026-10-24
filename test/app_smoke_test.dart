import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reportes_sistempac/app.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('muestra la pantalla principal y navega a ajustes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const ReportesSistempacApp());
    await tester.pumpAndSettle();

    expect(find.text('Arrastra aquí tus reportes'), findsOneWidget);
    expect(find.textContaining('Generar reportes'), findsOneWidget);
    expect(find.textContaining('Personaliza la marca'), findsOneWidget);

    await tester.tap(find.text('Ajustes'));
    await tester.pumpAndSettle();

    expect(find.text('Configuración de la marca'), findsOneWidget);
    expect(find.text('Nombre de la empresa'), findsOneWidget);
    expect(find.text('Traducir textos al español'), findsOneWidget);

    final settingsList = find.ancestor(
      of: find.text('Configuración de la marca'),
      matching: find.byType(ListView),
    );
    await tester.drag(settingsList, const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(find.text('Formatos compatibles'), findsOneWidget);
  });
}
