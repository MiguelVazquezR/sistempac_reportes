/// Configuración persistente de la aplicación.
class AppSettings {
  const AppSettings({
    this.companyName = '',
    this.defaultTitle = 'Reporte de Prueba de Tensión',
    this.logoPath,
    this.outputDirectory,
    this.translateContent = true,
    this.addBranding = true,
    this.replaceLogo = true,
  });

  /// Nombre de la empresa que se estampa en los reportes.
  final String companyName;

  /// Título sugerido para nuevos lotes de procesamiento.
  final String defaultTitle;

  /// Ruta absoluta del logo (PNG, JPG, GIF o BMP).
  final String? logoPath;

  /// Carpeta destino. `null` significa "junto al archivo original".
  final String? outputDirectory;

  /// Traduce etiquetas chinas/inglesas al español.
  final bool translateContent;

  /// Escribe empresa y título en el documento.
  final bool addBranding;

  /// Sustituye el logo genérico del reporte por el logo configurado.
  final bool replaceLogo;

  bool get hasLogo => logoPath != null && logoPath!.trim().isNotEmpty;

  bool get hasCompanyName => companyName.trim().isNotEmpty;

  AppSettings copyWith({
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
    return AppSettings(
      companyName: companyName ?? this.companyName,
      defaultTitle: defaultTitle ?? this.defaultTitle,
      logoPath: clearLogoPath ? null : (logoPath ?? this.logoPath),
      outputDirectory: clearOutputDirectory
          ? null
          : (outputDirectory ?? this.outputDirectory),
      translateContent: translateContent ?? this.translateContent,
      addBranding: addBranding ?? this.addBranding,
      replaceLogo: replaceLogo ?? this.replaceLogo,
    );
  }

  Map<String, Object?> toJson() => {
    'companyName': companyName,
    'defaultTitle': defaultTitle,
    'logoPath': logoPath,
    'outputDirectory': outputDirectory,
    'translateContent': translateContent,
    'addBranding': addBranding,
    'replaceLogo': replaceLogo,
  };

  factory AppSettings.fromJson(Map<String, Object?> json) {
    return AppSettings(
      companyName: (json['companyName'] as String?)?.trim() ?? '',
      defaultTitle:
          (json['defaultTitle'] as String?) ?? 'Reporte de Prueba de Tensión',
      logoPath: _nonEmpty(json['logoPath']),
      outputDirectory: _nonEmpty(json['outputDirectory']),
      translateContent: json['translateContent'] as bool? ?? true,
      addBranding: json['addBranding'] as bool? ?? true,
      replaceLogo: json['replaceLogo'] as bool? ?? true,
    );
  }

  static String? _nonEmpty(Object? value) {
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static const AppSettings empty = AppSettings();

  @override
  bool operator ==(Object other) {
    return other is AppSettings &&
        other.companyName == companyName &&
        other.defaultTitle == defaultTitle &&
        other.logoPath == logoPath &&
        other.outputDirectory == outputDirectory &&
        other.translateContent == translateContent &&
        other.addBranding == addBranding &&
        other.replaceLogo == replaceLogo;
  }

  @override
  int get hashCode => Object.hash(
    companyName,
    defaultTitle,
    logoPath,
    outputDirectory,
    translateContent,
    addBranding,
    replaceLogo,
  );
}
