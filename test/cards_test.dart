import 'dart:io';
import 'dart:ui' as ui;

import 'package:carte_scolaire/designs/card_designs.dart';
import 'package:carte_scolaire/models.dart';
import 'package:carte_scolaire/services/student_import.dart';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Dossier où écrire les aperçus PNG (facultatif) : CARD_PREVIEW_DIR=/chemin
final previewDir = Platform.environment['CARD_PREVIEW_DIR'];

Uint8List fakePhoto() {
  final im = img.Image(width: 300, height: 400);
  for (var y = 0; y < 400; y++) {
    for (var x = 0; x < 300; x++) {
      im.setPixelRgb(x, y, 120 + x ~/ 6, 90 + y ~/ 8, 70);
    }
  }
  img.fillCircle(im, x: 150, y: 150, radius: 70, color: img.ColorRgb8(90, 60, 45));
  return Uint8List.fromList(img.encodeJpg(im));
}

Uint8List fakeStamp() {
  final im = img.Image(width: 200, height: 200, numChannels: 4);
  img.drawCircle(im, x: 100, y: 100, radius: 90, color: img.ColorRgba8(40, 60, 170, 255));
  img.drawCircle(im, x: 100, y: 100, radius: 88, color: img.ColorRgba8(40, 60, 170, 255));
  img.drawCircle(im, x: 100, y: 100, radius: 60, color: img.ColorRgba8(40, 60, 170, 255));
  img.drawLine(im, x1: 50, y1: 100, x2: 150, y2: 100, color: img.ColorRgba8(40, 60, 170, 255), thickness: 4);
  return Uint8List.fromList(img.encodePng(im));
}

void main() {
  setUpAll(() async {
    final font = Platform.environment['CARD_FONT_DIR'];
    if (font != null) {
      final loader = FontLoader('Roboto');
      for (final f in ['Roboto-Regular.ttf', 'Roboto-Bold.ttf', 'Roboto-Black.ttf', 'Roboto-Medium.ttf']) {
        final file = File('$font/$f');
        if (file.existsSync()) loader.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
      }
      await loader.load();
    }
  });

  final school = SchoolInfo(
    name: 'Collège Privé Évangélique Maranatha',
    shortName: 'C.P.E MARANATHA',
    region: 'Région des Cascades - Province de la Léraba',
    signerName: 'M. BAZIÉ',
  )..stamp = fakeStamp();
  final student = Student.sample()..photo = fakePhoto();
  final noPhoto = Student(nom: 'Kaboré', prenom: 'Jean-Baptiste Wendkouni Emmanuel', classe: '6e B');

  for (final d in cardDesigns) {
    for (final portrait in [false, true]) {
      testWidgets('rendu ${d.id} ${portrait ? 'portrait' : 'paysage'}', (tester) async {
        final t = CardTemplate(
          designId: d.id,
          primary: d.primary,
          secondary: d.secondary,
          accent: d.accent,
          widthMm: portrait ? 54 : 85.6,
          heightMm: portrait ? 85.6 : 54,
        );
        final key = GlobalKey();
        for (final s in [student, noPhoto]) {
          await tester.pumpWidget(MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              backgroundColor: Colors.grey,
              body: DefaultTextStyle(
                style: const TextStyle(fontFamily: 'Roboto'),
                child: Center(
                  child: RepaintBoundary(
                    key: key,
                    child: CardView(template: t, school: school, student: s, scale: 4),
                  ),
                ),
              ),
            ),
          ));
          await tester.runAsync(() async {
            final ctx = tester.element(find.byKey(key));
            await precacheImage(MemoryImage(student.photo!), ctx);
            await precacheImage(MemoryImage(school.stamp!), ctx);
          });
          await tester.pump();
          expect(tester.takeException(), isNull);
          if (previewDir != null && s == student) {
            await tester.runAsync(() async {
              final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
              final image = await boundary.toImage(pixelRatio: 2.5);
              final png = await image.toByteData(format: ui.ImageByteFormat.png);
              File('$previewDir/${d.id}_${portrait ? 'portrait' : 'paysage'}.png')
                  .writeAsBytesSync(png!.buffer.asUint8List());
            });
          }
        }
      });
    }
  }

  test('import Excel avec titres variés', () {
    final excel = Excel.createExcel();
    final sheet = excel[excel.getDefaultSheet()!];
    sheet.appendRow([TextCellValue('LISTE DE LA CLASSE')]);
    sheet.appendRow([
      TextCellValue('N° Matricule'),
      TextCellValue('Nom et Prénoms'),
      TextCellValue('Classe'),
      TextCellValue('Date de naissance'),
      TextCellValue('Lieu de naissance'),
      TextCellValue('Personne à prévenir'),
    ]);
    sheet.appendRow([
      const IntCellValue(1024),
      TextCellValue('Sawadogo Issa Hamidou'),
      TextCellValue('CE1'),
      const DateCellValue(year: 2017, month: 9, day: 4),
      TextCellValue('Koudougou'),
      const IntCellValue(70112233),
    ]);
    final bytes = Uint8List.fromList(excel.encode()!);
    final r = importStudents(bytes, 'liste.xlsx');
    expect(r.students, hasLength(1));
    final s = r.students.first;
    expect(s.matricule, '1024');
    expect(s.nom, 'Sawadogo');
    expect(s.prenom, 'Issa Hamidou');
    expect(s.classe, 'CE1');
    expect(s.dateNaissance, '04/09/2017');
    expect(s.lieuNaissance, 'Koudougou');
    expect(s.contact, '70112233');
    expect(r.recognizedColumns, contains('Personne à prévenir'));
  });

  test('fichier modèle fourni avec le projet', () {
    final r = importStudents(File('modele_liste_eleves.xlsx').readAsBytesSync(), 'modele_liste_eleves.xlsx');
    expect(r.students, hasLength(4));
    expect(r.students.first.prenom, 'Awa Mariam');
    expect(r.students.last.classe, '6e B');
  });

  test('import CSV point-virgule', () {
    const csv = 'Nom;Prénom;Classe;Sexe\nZongo;Aminata;CM1;féminin\n"Traoré";"Ali, Junior";CM1;M\n';
    final r = importStudents(Uint8List.fromList(csv.codeUnits.map((c) => c & 0xff).toList()), 'l.csv');
    expect(r.students.map((s) => s.nom), ['Zongo', 'Traoré']);
    expect(r.students[1].prenom, 'Ali, Junior');
    expect(r.students.first.sexe, 'F');
  });

  test('planche A4 : 10 cartes CR80 par feuille', () {
    final (c, r) = PrintLayout().grid(85.6, 54);
    expect(c * r, 10);
  });
}
