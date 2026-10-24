import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reportes_sistempac/core/image_size_reader.dart';

import 'helpers/test_fixtures.dart';

void main() {
  group('ImageSizeReader', () {
    test('lee las dimensiones de un PNG', () {
      final bytes = buildPng(width: 120, height: 40);
      expect(ImageSizeReader.read(bytes), const ImageDimensions(120, 40));
      expect(ImageSizeReader.detectExtension(bytes), 'png');
    });

    test('lee las dimensiones de un JPEG', () {
      final bytes = buildJpeg(width: 64, height: 32);
      expect(ImageSizeReader.read(bytes), const ImageDimensions(64, 32));
      expect(ImageSizeReader.detectExtension(bytes), 'jpg');
    });

    test('lee las dimensiones de un GIF', () {
      final bytes = Uint8List.fromList([
        0x47, 0x49, 0x46, 0x38, 0x39, 0x61, // GIF89a
        0x20, 0x00, // ancho 32 (LE)
        0x10, 0x00, // alto 16 (LE)
        0x00, 0x00, 0x00,
      ]);
      expect(ImageSizeReader.read(bytes), const ImageDimensions(32, 16));
      expect(ImageSizeReader.detectExtension(bytes), 'gif');
    });

    test('lee las dimensiones de un BMP', () {
      final bytes = Uint8List(30)
        ..[0] = 0x42
        ..[1] = 0x4D
        ..[18] = 0x40
        ..[22] = 0x20;
      expect(ImageSizeReader.read(bytes), const ImageDimensions(64, 32));
      expect(ImageSizeReader.detectExtension(bytes), 'bmp');
    });

    test('devuelve null para contenido que no es imagen', () {
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      expect(ImageSizeReader.read(bytes), isNull);
      expect(ImageSizeReader.detectExtension(bytes), isNull);
    });
  });
}
