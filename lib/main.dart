import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';

const Size _initialWindowSize = Size(1020, 780);
const Size _minimumWindowSize = Size(880, 660);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    size: _initialWindowSize,
    minimumSize: _minimumWindowSize,
    center: true,
    title: 'Optimizador de Reportes de Tensión',
    titleBarStyle: TitleBarStyle.normal,
  );

  // La ventana se muestra cuando Flutter ya tiene el primer frame listo,
  // evitando el destello con el tamaño por defecto del runner nativo.
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const ReportesSistempacApp());
}
