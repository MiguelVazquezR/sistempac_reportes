# Optimizador de Reportes de Tensión

Aplicación de escritorio para Windows que toma reportes de pruebas de tensión
(en chino o inglés), traduce las etiquetas al español, elimina el logo genérico
y aplica la identidad de la empresa (nombre, título opcional y logo propio).

- Entrada: `.xlsx` (Excel) y `.docx` (Word).
- Salida: copia del reporte con sufijo `_ES`, en la misma carpeta del original o
  en la carpeta que definas en **Ajustes**.
- Sin dependencia de Office, LibreOffice ni servicios en línea: todo el
  procesamiento ocurre localmente.

## Requisitos

1. **Flutter 3.47 o superior** (probado con Flutter 3.47.4 / Dart 3.13.3).
2. **Visual Studio 2022** con la carga de trabajo **"Desarrollo para el
escritorio con C++"** (incluye MSVC v143 y Windows SDK). Sin esa carga de
trabajo, `flutter run -d windows` falla con `Unable to find suitable Visual
Studio toolchain`.

```powershell
flutter doctor
flutter pub get
flutter run -d windows
```

Para generar el ejecutable:

```powershell
flutter build windows --release
# Resultado: build\windows\x64\runner\Release\reportes_sistempac.exe
```

## Cómo se usa

1. **Ajustes**: escribe el nombre de la empresa, el título predeterminado y
   selecciona el logo (PNG o JPG). Opcionalmente elige una carpeta de salida.
2. **Procesar**: arrastra uno o varios reportes a la ventana o usa
   *Seleccionar archivos*.
3. Pulsa **Generar reportes**. Cada archivo produce una copia traducida y
   personalizada; el panel de resultados muestra los textos traducidos, las
   advertencias y permite *Guardar como…* o abrir la carpeta del archivo.

## Qué hace exactamente

### Excel (`.xlsx`)

- Traduce las celdas de texto conservando el estilo de cada celda
  (`cellStyle`) y sin tocar números, fechas ni fórmulas.
- Renombra las hojas con nombres chinos conocidos (por ejemplo `测试报告` →
  `Reporte de prueba`).
- Escribe el nombre de la empresa y el título en las filas libres del
  encabezado. Si el reporte empieza en la fila 1, la marca se agrega al final de
  la hoja y se muestra una advertencia (insertar filas rompería las celdas
  combinadas y el área de impresión).
- Inserta el logo manipulando el paquete OOXML: reutiliza el dibujo de la hoja,
  lo agrega en `xl/media/` con su relación y la entrada en
  `[Content_Types].xml`. Los gráficos y curvas se conservan. Si la opción
  *Reemplazar el logo del reporte* está activa, elimina antes las imágenes
  ancladas en las primeras filas (logo de plantilla).

### Word (`.docx`)

- Traduce los párrafos del cuerpo, encabezados y pies de página. El texto
  traducido se coloca en el primer `w:t` del párrafo, por lo que se conserva el
  formato del primer run.
- Omite párrafos con imágenes, campos, tabulaciones o saltos para no destruir
  contenido.
- Inserta empresa, título y logo al inicio del encabezado (o del cuerpo si el
  documento no tiene encabezado) y elimina las imágenes del encabezado para no
  duplicar el logo.

### Formatos antiguos

Los archivos `.xls` y `.doc` **no se convierten**. La aplicación los detecta por
su firma OLE (`D0 CF 11 E0`), los marca y muestra una guía para guardarlos como
`.xlsx`/`.docx` desde Excel o Word. Así se evita depender de Office o de
conversores externos y se conserva el formato original del reporte.

## Arquitectura

```text
lib/
  core/          Tema, utilidades de formato, lector de dimensiones de imagen,
                 excepción de dominio.
  models/        Configuración, opciones, archivo seleccionado y resultados.
  services/      Procesadores de Excel y Word, inyector de logo, diccionario y
                 servicio de traducción, acceso a disco y configuración.
  state/         Controladores ChangeNotifier (ajustes y procesamiento).
  ui/            Shell, páginas y widgets.
test/            Pruebas con archivos OOXML sintéticos.
```

- Gestión de estado: `ChangeNotifier` + `ListenableBuilder`, sin paquetes de
  terceros.
- Excel: `excel` 4.0.6 para leer y reescribir celdas; el logo se agrega después
  de guardar, manipulando el ZIP con `archive` 3.6.1 y `xml` 6.
- Word: lectura y escritura directa de las partes OOXML.
- Diálogos nativos: `file_picker` 13.2. La ventana se centra con
  `window_manager` 0.5.2.

## Pruebas

```powershell
flutter test
flutter analyze
```

Las pruebas construyen libros y documentos sintéticos (incluido un PNG válido
generado en memoria) y verifican la traducción, la marca, la inyección del logo,
la validez del XML de todas las partes y el manejo de errores. No requieren
Office ni archivos externos.

## Limitaciones conocidas

- La posición del logo y de la marca es heurística (fila 0 y columna siguiente
  al contenido en Excel; inicio del encabezado en Word). Calibra con un reporte
  real y ajusta `ExcelLogoInjector` o `DocxReportProcessor` si tu plantilla
  necesita otra ubicación.
- El diccionario cubre los términos habituales de pruebas de tracción; los
  textos no reconocidos se informan como "sin traducir" en el panel de
  resultados.
- Al reescribir el libro con `excel`, algunas funciones avanzadas (macros,
  formato condicional complejo, tablas dinámicas) pueden perderse. Si el libro
  las usa, conserva una copia del original antes de procesarlo.
- Un párrafo de Word con varios formatos internos hereda el formato del primer
  run al traducirse.

