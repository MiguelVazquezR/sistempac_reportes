/// Dimensiones en píxeles de una imagen.
class ImageDimensions {
  const ImageDimensions(this.width, this.height);

  final int width;
  final int height;

  double get aspectRatio => height == 0 ? 1 : width / height;

  @override
  String toString() => '${width}x$height';

  @override
  bool operator ==(Object other) =>
      other is ImageDimensions &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(width, height);
}

/// Lector de cabeceras de imagen sin dependencias externas.
///
/// Se usa para calcular el tamaño del logo en EMU sin decodificar la imagen
/// completa (PNG, JPEG, GIF y BMP).
abstract final class ImageSizeReader {
  static const List<int> _pngSignature = [
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
  ];

  /// Devuelve las dimensiones o `null` si el formato no se reconoce.
  static ImageDimensions? read(List<int> bytes) {
    final extension = detectExtension(bytes);
    switch (extension) {
      case 'png':
        return _readPng(bytes);
      case 'jpg':
        return _readJpeg(bytes);
      case 'gif':
        return _readGif(bytes);
      case 'bmp':
        return _readBmp(bytes);
      default:
        return null;
    }
  }

  /// Detecta el tipo real de imagen a partir de su firma binaria.
  static String? detectExtension(List<int> bytes) {
    if (bytes.length >= 8 && _matches(bytes, 0, _pngSignature)) {
      return 'png';
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'jpg';
    }
    if (bytes.length >= 6 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46) {
      return 'gif';
    }
    if (bytes.length >= 2 && bytes[0] == 0x42 && bytes[1] == 0x4D) {
      return 'bmp';
    }
    return null;
  }

  static ImageDimensions? _readPng(List<int> bytes) {
    if (bytes.length < 24 || !_matches(bytes, 0, _pngSignature)) {
      return null;
    }
    final width = _readUint32BigEndian(bytes, 16);
    final height = _readUint32BigEndian(bytes, 20);
    if (width <= 0 || height <= 0) {
      return null;
    }
    return ImageDimensions(width, height);
  }

  static ImageDimensions? _readGif(List<int> bytes) {
    if (bytes.length < 10) {
      return null;
    }
    final width = bytes[6] | (bytes[7] << 8);
    final height = bytes[8] | (bytes[9] << 8);
    if (width <= 0 || height <= 0) {
      return null;
    }
    return ImageDimensions(width, height);
  }

  static ImageDimensions? _readBmp(List<int> bytes) {
    if (bytes.length < 26) {
      return null;
    }
    final width = _readInt32LittleEndian(bytes, 18);
    final height = _readInt32LittleEndian(bytes, 22).abs();
    if (width <= 0 || height <= 0) {
      return null;
    }
    return ImageDimensions(width, height);
  }

  /// Recorre los segmentos JPEG hasta encontrar un SOF (inicio de cuadro).
  static ImageDimensions? _readJpeg(List<int> bytes) {
    var offset = 2;
    while (offset + 3 < bytes.length) {
      if (bytes[offset] != 0xFF) {
        offset++;
        continue;
      }
      final marker = bytes[offset + 1];
      // Marcadores sin longitud asociada.
      if (marker == 0xFF) {
        offset++;
        continue;
      }
      if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD9)) {
        offset += 2;
        continue;
      }
      final length = (bytes[offset + 2] << 8) | bytes[offset + 3];
      if (length < 2) {
        return null;
      }
      final isStartOfFrame =
          marker >= 0xC0 &&
          marker <= 0xCF &&
          marker != 0xC4 &&
          marker != 0xC8 &&
          marker != 0xCC;
      if (isStartOfFrame) {
        if (offset + 8 >= bytes.length) {
          return null;
        }
        final height = (bytes[offset + 5] << 8) | bytes[offset + 6];
        final width = (bytes[offset + 7] << 8) | bytes[offset + 8];
        if (width <= 0 || height <= 0) {
          return null;
        }
        return ImageDimensions(width, height);
      }
      offset += 2 + length;
    }
    return null;
  }

  static bool _matches(List<int> bytes, int start, List<int> signature) {
    if (bytes.length < start + signature.length) {
      return false;
    }
    for (var i = 0; i < signature.length; i++) {
      if (bytes[start + i] != signature[i]) {
        return false;
      }
    }
    return true;
  }

  static int _readUint32BigEndian(List<int> bytes, int offset) {
    return (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
  }

  static int _readInt32LittleEndian(List<int> bytes, int offset) {
    final value =
        bytes[offset] |
        (bytes[offset + 1] << 8) |
        (bytes[offset + 2] << 16) |
        (bytes[offset + 3] << 24);
    // Convierte a entero con signo de 32 bits.
    return value >= 0x80000000 ? value - 0x100000000 : value;
  }
}
