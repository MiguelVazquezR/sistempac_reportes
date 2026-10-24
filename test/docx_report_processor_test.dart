import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reportes_sistempac/models/processing_options.dart';
import 'package:reportes_sistempac/services/docx_report_processor.dart';

import 'helpers/test_fixtures.dart';

String partText(Archive archive, String name) {
  final file = archive.findFile(name);
  expect(file, isNotNull, reason: 'Falta la parte $name');
  return utf8.decode(file!.content as List<int>, allowMalformed: true);
}

void main() {
  test('traduce el cuerpo e inserta marca y logo en el encabezado', () {
    final bytes = buildDocx(
      bodyParagraphs: ['测试报告', '报告编号: A-1', '抗拉强度 (MPa)'],
      headerText: 'Test Report',
      headerWithPicture: true,
    );

    final result = DocxReportProcessor().process(
      bytes: bytes,
      fileName: 'reporte.docx',
      options: ProcessingOptions(
        companyName: 'SISTEMPAC',
        title: 'Reporte de Prueba de Tensión',
        logoBytes: buildPng(),
      ),
    );

    expect(result.warnings, isEmpty);
    expect(result.branding?.headerPlaced, isTrue);
    expect(result.branding?.logoPlaced, isTrue);
    expect(result.translatedItems, greaterThanOrEqualTo(3));

    final archive = ZipDecoder().decodeBytes(result.bytes);
    final body = partText(archive, 'word/document.xml');
    expect(body, contains('Reporte de prueba'));
    expect(body, contains('N.º de reporte: A-1'));
    expect(body, contains('Resistencia a la tracción (MPa)'));
    expect(
      body,
      contains('<w:b/>'),
      reason: 'Debe conservar el estilo del run',
    );

    final header = partText(archive, 'word/header1.xml');
    expect(header, contains('SISTEMPAC'));
    expect(header, contains('Reporte de Prueba de Tensión'));
    expect(header, contains('<w:drawing>'));
    expect(header, contains('logo.png'));
    expect(
      '<w:drawing>'.allMatches(header).length,
      1,
      reason: 'El logo de plantilla debe eliminarse',
    );

    expect(archive.findFile('word/media/logo.png'), isNotNull);
    expect(
      partText(archive, 'word/_rels/header1.xml.rels'),
      contains('media/logo.png'),
    );
    expect(partText(archive, '[Content_Types].xml'), contains('image/png'));
    expect(malformedXmlParts(result.bytes), isEmpty);
  });

  test('con reemplazo desactivado conserva el logo de plantilla', () {
    final bytes = buildDocx(
      bodyParagraphs: ['测试报告'],
      headerText: 'Encabezado',
      headerWithPicture: true,
    );

    final result = DocxReportProcessor().process(
      bytes: bytes,
      fileName: 'reporte.docx',
      options: ProcessingOptions(
        companyName: 'SISTEMPAC',
        title: 'Reporte',
        logoBytes: buildPng(),
        replaceLogo: false,
      ),
    );

    expect(result.branding?.logoPlaced, isTrue);
    final archive = ZipDecoder().decodeBytes(result.bytes);
    final header = partText(archive, 'word/header1.xml');
    expect(
      '<w:drawing>'.allMatches(header).length,
      2,
      reason: 'Debe conservar la imagen original y agregar la nueva',
    );
    expect(archive.findFile('word/media/old-logo.png'), isNotNull);
  });

  test('sin encabezado inserta la marca en el cuerpo y avisa', () {
    final bytes = buildDocx(bodyParagraphs: ['测试报告']);

    final result = DocxReportProcessor().process(
      bytes: bytes,
      fileName: 'reporte.docx',
      options: ProcessingOptions(
        companyName: 'SISTEMPAC',
        title: 'Reporte de Prueba de Tensión',
        logoBytes: buildPng(),
      ),
    );

    expect(result.warnings, isNotEmpty);
    expect(result.warnings.first, contains('no tiene encabezado'));
    expect(result.branding?.headerPlaced, isTrue);
    expect(result.branding?.logoPlaced, isTrue);

    final archive = ZipDecoder().decodeBytes(result.bytes);
    final body = partText(archive, 'word/document.xml');
    expect(body.indexOf('SISTEMPAC'), greaterThan(-1));
    expect(
      body.indexOf('SISTEMPAC'),
      lessThan(body.indexOf('Reporte de prueba')),
      reason: 'La marca debe quedar antes del contenido original',
    );
  });

  test('sin traducción conserva el texto original', () {
    final bytes = buildDocx(bodyParagraphs: ['测试报告', 'Report No.: 42']);

    final result = DocxReportProcessor().process(
      bytes: bytes,
      fileName: 'reporte.docx',
      options: const ProcessingOptions(
        translateContent: false,
        addBranding: false,
      ),
    );

    expect(result.translatedItems, 0);
    final archive = ZipDecoder().decodeBytes(result.bytes);
    final body = partText(archive, 'word/document.xml');
    expect(body, contains('测试报告'));
    expect(body, contains('Report No.: 42'));
    expect(body, isNot(contains('<w:drawing>')));
  });
}
