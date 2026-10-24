import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

/// Vista mutable y mínima de un paquete OOXML (`.xlsx`/`.docx`) en memoria.
///
/// Permite leer y reemplazar partes XML sin perder el resto del ZIP, algo que
/// las librerías de alto nivel (`excel`) no cubren.
class OoxmlPackage {
  OoxmlPackage._(this._files, this._order);

  /// Decodifica el ZIP. Lanza `ArchiveException` si el archivo no es válido.
  static OoxmlPackage decode(List<int> bytes) {
    final archive = ZipDecoder().decodeBytes(bytes, verify: false);
    final files = <String, Uint8List>{};
    final order = <String>[];
    for (final file in archive.files) {
      if (!file.isFile) {
        continue;
      }
      final content = file.content as List<int>;
      files[file.name] = Uint8List.fromList(content);
      order.add(file.name);
    }
    return OoxmlPackage._(files, order);
  }

  final Map<String, Uint8List> _files;
  final List<String> _order;

  /// Nombres de las partes en su orden original.
  List<String> get names => List.unmodifiable(_order);

  bool contains(String path) => _files.containsKey(path);

  Uint8List? readBytes(String path) => _files[path];

  String? readText(String path) {
    final content = _files[path];
    return content == null ? null : utf8.decode(content, allowMalformed: true);
  }

  XmlDocument? readXml(String path) {
    final text = readText(path);
    if (text == null || text.trim().isEmpty) {
      return null;
    }
    return XmlDocument.parse(text);
  }

  void writeText(String path, String text) =>
      writeBytes(path, utf8.encode(text));

  void writeBytes(String path, List<int> bytes) {
    if (!_files.containsKey(path)) {
      _order.add(path);
    }
    _files[path] = Uint8List.fromList(bytes);
  }

  void remove(String path) {
    if (_files.remove(path) != null) {
      _order.remove(path);
    }
  }

  /// Vuelve a comprimir el paquete completo.
  List<int> encode() {
    final archive = Archive();
    for (final name in _order) {
      final content = _files[name];
      if (content == null) {
        continue;
      }
      archive.addFile(
        ArchiveFile(name, content.length, content)..compress = true,
      );
    }
    final encoded = ZipEncoder().encode(archive);
    if (encoded == null) {
      throw StateError('No se pudo recomprimir el documento.');
    }
    return encoded;
  }

  /// Ruta del archivo de relaciones correspondiente a una parte.
  static String relationshipsPathFor(String partPath) {
    return p.posix.join(
      p.posix.dirname(partPath),
      '_rels',
      '${p.posix.basename(partPath)}.rels',
    );
  }

  /// Resuelve un `Target` de relaciones relativo a la parte [fromPart].
  static String resolvePartPath(String fromPart, String target) {
    if (target.startsWith('/')) {
      return target.substring(1);
    }
    return p.posix.normalize(p.posix.join(p.posix.dirname(fromPart), target));
  }

  /// Ruta relativa de [toPart] vista desde [fromPart].
  static String relativeTarget(String fromPart, String toPart) {
    return p.posix.relative(toPart, from: p.posix.dirname(fromPart));
  }
}
