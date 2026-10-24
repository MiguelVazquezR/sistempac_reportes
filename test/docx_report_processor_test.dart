import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reportes_sistempac/models/processing_options.dart';
import 'package:reportes_sistempac/services/docx_report_processor.dart';
import 'package:xml/xml.dart';

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

  test('corrige etiquetas de la plantilla aun sin traducir', () {
    final result = DocxReportProcessor().process(
      bytes: buildReportTemplateDocx(),
      fileName: 'plantilla.docx',
      options: const ProcessingOptions(
        translateContent: false,
        addBranding: false,
      ),
    );

    expect(result.translatedItems, 0);
    final archive = ZipDecoder().decodeBytes(result.bytes);
    final body = partText(archive, 'word/document.xml');
    expect(body, contains('Tipo de prueba'));
    expect(body, contains('Nombre material'));
    expect(body, contains('Tipo material'));
    expect(body, contains('Prueba para'));
    expect(body, contains('Humedad'));
    expect(body, contains('Longitud'));
    expect(body, contains('Comentario:'));
    expect(body, isNot(contains('Test Type')));
    expect(body, isNot(contains('Mat.Name')));
    expect(body, isNot(contains('TLG001')));
    expect(malformedXmlParts(result.bytes), isEmpty);
  });

  test('normaliza un título alterno y elimina el subtítulo duplicado', () {
    final result = DocxReportProcessor().process(
      bytes: buildReportTemplateDocx(title: 'Reporte de prueba de tensión'),
      fileName: 'plantilla.docx',
      options: const ProcessingOptions(addBranding: false),
    );

    final archive = ZipDecoder().decodeBytes(result.bytes);
    final body = partText(archive, 'word/document.xml');
    expect('Reporte de ensayo'.allMatches(body).length, 1);
    expect(body, isNot(contains('>Reporte de prueba de tensión<')));
    expect(malformedXmlParts(result.bytes), isEmpty);
  });

  test('normaliza la plantilla: título, etiquetas y filas vacías', () {
    final result = DocxReportProcessor().process(
      bytes: buildReportTemplateDocx(),
      fileName: 'plantilla.docx',
      options: const ProcessingOptions(addBranding: false),
    );

    final archive = ZipDecoder().decodeBytes(result.bytes);
    final body = partText(archive, 'word/document.xml');
    final document = XmlDocument.parse(body);

    expect('Reporte de ensayo'.allMatches(body).length, 1);
    expect(body, isNot(contains('TLG001')));
    expect(body, isNot(contains('>Material<')));
    expect(body, isNot(contains('>Reporte de prueba de tensión<')));
    expect(body, contains('Tipo de prueba'));
    expect(body, contains('Nombre material'));
    expect(body, contains('Tipo material'));
    expect(body, contains('Prueba para'));
    expect(body, contains('Humedad'));
    expect(body, contains('Longitud'));
    expect(body, contains('Comentario:'));
    expect(body, isNot(contains('Test Type')));
    expect(body, isNot(contains('Mat.Name')));
    expect(body, isNot(contains('Mat.Type')));
    expect(body, isNot(contains('Test For')));
    expect(body, isNot(contains('Humi')));
    expect(body, isNot(contains('>Lo<')));
    expect(body, isNot(contains('comment:')));
    expect(body, isNot(contains('assessor')));
    expect(body, isNot(contains('ratifier')));
    expect(body, isNot(contains('test person')));
    expect(body, contains('<w:pict/>'));

    String tableText(XmlElement element) => element.descendantElements
        .where((child) => child.name.local == 't')
        .map((child) => child.innerText)
        .join();

    final tables = document.descendantElements
        .where((element) => element.name.local == 'tbl')
        .toList(growable: false);
    final resultCandidates =
        tables
            .where(
              (table) =>
                  tableText(table).contains('21.7') &&
                  tableText(table).contains('284.6'),
            )
            .toList()
          ..sort(
            (left, right) => left.descendantElements.length.compareTo(
              right.descendantElements.length,
            ),
          );
    expect(resultCandidates, isNotEmpty);
    final resultsTable = resultCandidates.first;
    final resultsRows = resultsTable.children
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'tr')
        .toList(growable: false);
    expect(resultsRows, hasLength(2));

    final topTable = tables.first;
    final topRows = topTable.children
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'tr')
        .toList(growable: false);
    bool rowHasTable(XmlElement row, bool Function(String) matches) {
      return row.descendantElements.any(
        (element) => element.name.local == 'tbl' && matches(tableText(element)),
      );
    }

    final resultsRow = topRows.indexWhere(
      (row) => rowHasTable(
        row,
        (text) => text.contains('21.7') && text.contains('284.6'),
      ),
    );
    final statsRow = topRows.indexWhere(
      (row) => rowHasTable(
        row,
        (text) => text.contains('3.94') && text.contains('13.67'),
      ),
    );
    expect(resultsRow, greaterThanOrEqualTo(0));
    expect(statsRow, greaterThanOrEqualTo(0));
    expect(statsRow, resultsRow + 1);
    expect(malformedXmlParts(result.bytes), isEmpty);
  });
}
