import 'app_settings.dart';

/// Opciones concretas de una ejecución de procesamiento.
class ProcessingOptions {
  const ProcessingOptions({
    this.companyName = '',
    this.title = '',
    this.translateContent = true,
    this.addBranding = true,
    this.replaceLogo = true,
    this.logoPath,
    this.logoBytes,
  });

  final String companyName;
  final String title;
  final bool translateContent;
  final bool addBranding;
  final bool replaceLogo;

  /// Ruta del logo en disco (para poder informarla en mensajes de error).
  final String? logoPath;

  /// Contenido del logo ya leído, se inyecta tal cual en el documento.
  final List<int>? logoBytes;

  factory ProcessingOptions.fromSettings(
    AppSettings settings, {
    String? title,
    List<int>? logoBytes,
    String? logoPath,
  }) {
    return ProcessingOptions(
      companyName: settings.companyName.trim(),
      title: (title ?? settings.defaultTitle).trim(),
      translateContent: settings.translateContent,
      addBranding: settings.addBranding,
      replaceLogo: settings.replaceLogo,
      logoPath: logoPath ?? settings.logoPath,
      logoBytes: logoBytes,
    );
  }

  bool get hasLogo => logoBytes != null && logoBytes!.isNotEmpty;

  bool get hasCompanyName => companyName.trim().isNotEmpty;

  bool get hasTitle => title.trim().isNotEmpty;

  /// `true` cuando hay algo de marca que aplicar al documento.
  bool get hasBranding =>
      (addBranding && (hasCompanyName || hasTitle)) || hasLogo;

  /// Encabezados a estampar, de arriba hacia abajo.
  List<String> get brandingLines {
    if (!addBranding) {
      return const [];
    }
    return [if (hasCompanyName) companyName, if (hasTitle) title];
  }

  ProcessingOptions copyWith({
    String? companyName,
    String? title,
    bool? translateContent,
    bool? addBranding,
    bool? replaceLogo,
    String? logoPath,
    List<int>? logoBytes,
  }) {
    return ProcessingOptions(
      companyName: companyName ?? this.companyName,
      title: title ?? this.title,
      translateContent: translateContent ?? this.translateContent,
      addBranding: addBranding ?? this.addBranding,
      replaceLogo: replaceLogo ?? this.replaceLogo,
      logoPath: logoPath ?? this.logoPath,
      logoBytes: logoBytes ?? this.logoBytes,
    );
  }
}

/// Metadatos de la marca aplicada a un documento.
class BrandingPlacement {
  const BrandingPlacement({
    required this.headerPlaced,
    required this.logoPlaced,
    this.detail,
  });

  final bool headerPlaced;
  final bool logoPlaced;
  final String? detail;
}

/// Resultado del procesamiento de un archivo (antes de guardarlo).
class ProcessedReport {
  const ProcessedReport({
    required this.bytes,
    required this.warnings,
    this.translatedItems = 0,
    this.untranslatedItems = 0,
    this.branding,
  });

  final List<int> bytes;
  final List<String> warnings;
  final int translatedItems;
  final int untranslatedItems;
  final BrandingPlacement? branding;

  bool get hasWarnings => warnings.isNotEmpty;
}
