import 'package:path/path.dart' as p;

import '../core/format_utils.dart';

/// Archivo seleccionado por el usuario para procesar.
class SelectedReport {
  const SelectedReport({
    required this.path,
    required this.name,
    required this.sizeBytes,
    required this.format,
  });

  final String path;
  final String name;
  final int sizeBytes;
  final ReportFormat format;

  String get extension => FormatUtils.extensionOf(name);

  bool get isSupported => FormatUtils.isSupported(format);

  bool get isLegacy => FormatUtils.isLegacy(format);

  String get readableSize => FormatUtils.formatFileSize(sizeBytes);

  String get directory => p.dirname(path);

  String get formatLabel => FormatUtils.label(format);

  SelectedReport copyWith({
    String? path,
    String? name,
    int? sizeBytes,
    ReportFormat? format,
  }) {
    return SelectedReport(
      path: path ?? this.path,
      name: name ?? this.name,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      format: format ?? this.format,
    );
  }

  /// Evita duplicados cuando el usuario arrastra el mismo archivo dos veces.
  String get identityKey => p.canonicalize(path).toLowerCase();

  @override
  bool operator ==(Object other) =>
      other is SelectedReport && other.identityKey == identityKey;

  @override
  int get hashCode => identityKey.hashCode;
}
