import 'dart:typed_data';

import 'package:carte_scolaire/services/photo_batch.dart';
import 'package:carte_scolaire/services/sheet_reader.dart';
import 'package:carte_scolaire/services/student_import.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Mots d'une ligne : (texte, x) sur une ligne de hauteur 20 à la position y.
List<OcrWord> line(double y, List<(String, double)> words) => [
      for (final (t, x) in words) OcrWord(t, x, y + (x % 3), t.length * 10.0, 20),
    ];

void main() {
  group('Feuille de noms → tableau', () {
    test('lignes et colonnes reconstruites à partir des positions', () {
      final words = [
        ...line(10, [('N°', 10), ('NOM', 60), ('ET', 100), ('PRÉNOMS', 125), ('CLASSE', 400), ('NÉ(E)', 520), ('LE', 575)]),
        ...line(50, [('1', 10), ('OUÉDRAOGO', 60), ('Awa', 160), ('Marie', 200), ('6e', 400), ('A', 425), ('12/03/2014', 520)]),
        ...line(90, [('2', 10), ('SAWADOGO', 60), ('Issa', 150), ('6e', 400), ('B', 425), ('01/01/2013', 520)]),
        // Ligne légèrement penchée et mots dans le désordre.
        ...line(131, [('05/06/2014', 521), ('3', 11), ('KABORÉ', 61), ('Jean', 130), ('Paul', 175), ('6e', 401), ('A', 426)]),
      ];
      final t = wordsToTable(words);
      expect(t.length, 4);
      expect(t[0], ['N°', 'NOM ET PRÉNOMS', 'CLASSE', 'NÉ(E) LE']);
      expect(t[1], ['1', 'OUÉDRAOGO Awa Marie', '6e A', '12/03/2014']);
      expect(t[3], ['3', 'KABORÉ Jean Paul', '6e A', '05/06/2014']);

      final g = guessColumns(t);
      expect(g.headerRow, 0);
      expect(g.fields, ['', 'nomComplet', 'classe', 'dateNaissance']);
      final s = buildStudents(t, g.fields, headerRow: g.headerRow);
      expect(s.length, 3);
      expect(s[0].nom, 'OUÉDRAOGO');
      expect(s[0].prenom, 'Awa Marie');
      expect(s[0].classe, '6e A');
      expect(s[2].dateNaissance, '05/06/2014');
    });

    test('sans titres : colonnes devinées d\'après leur contenu', () {
      final t = [
        ['1', 'ZONGO Fatimata', 'F', '70 12 34 56'],
        ['2', 'TRAORÉ Moussa', 'M', '76 00 11 22'],
        ['3', 'DIALLO Aminata Sali', 'F', '65 44 33 22'],
      ];
      final g = guessColumns(t);
      expect(g.headerRow, isNull);
      expect(g.fields, ['', 'nomComplet', 'sexe', 'contact']);
      final s = buildStudents(t, g.fields, defaultClass: 'CM2');
      expect(s.map((e) => e.nom), ['ZONGO', 'TRAORÉ', 'DIALLO']);
      expect(s[2].prenom, 'Aminata Sali');
      expect(s.every((e) => e.classe == 'CM2'), isTrue);
      expect(s[1].sexe, 'M');
    });

    test('colonnes Nom et Prénom séparées, lignes décochées', () {
      final t = [
        ['Nom', 'Prénom(s)', 'Classe'],
        ['BAZIÉ', 'Jean', '5e'],
        ['......', '', ''],
        ['SOMÉ', 'Léa', '5e'],
      ];
      final clean = cleanTable(t);
      expect(clean.length, 3);
      final g = guessColumns(clean);
      expect(g.fields, ['nom', 'prenom', 'classe']);
      final s = buildStudents(clean, g.fields, headerRow: 0, skip: {2});
      expect(s.single.nom, 'BAZIÉ');
    });

    test('texte collé et réponse de l\'IA', () {
      final t = textToTable('BAZIÉ Jean\t5e\nSOMÉ Léa\t4e\n');
      expect(t, [
        ['BAZIÉ Jean', '5e'],
        ['SOMÉ Léa', '4e'],
      ]);
      final ai = parseAiTable('Voici le tableau :\n```json\n{"rows": [["Nom", "Prénom"], ["KONÉ", "Ali"], ["SANOU", null]]}\n```');
      expect(ai, [
        ['Nom', 'Prénom'],
        ['KONÉ', 'Ali'],
        ['SANOU', ''],
      ]);
      expect(parseAiTable('[{"Nom":"KONÉ","Classe":"6e"}]'), [
        ['Nom', 'Classe'],
        ['KONÉ', '6e'],
      ]);
      expect(() => parseAiTable('Désolé, illisible.'), throwsFormatException);
    });

    test('découpe du nom complet', () {
      expect(splitFullName('DE SOUZA Jean Marc'), ('DE SOUZA', 'Jean Marc'));
      expect(splitFullName('OUEDRAOGO AWA'), ('OUEDRAOGO', 'AWA'));
      expect(splitFullName('Kaboré Paul'), ('Kaboré', 'Paul'));
    });
  });

  group('Photos en lot', () {
    test('heure de prise : EXIF, nom du fichier', () {
      final im = img.Image(width: 8, height: 8);
      im.exif.exifIfd[0x9003] = img.IfdValueAscii('2026:11:14 09:30:12');
      final jpg = Uint8List.fromList(img.encodeJpg(im));
      expect(exifTakenDate(jpg), DateTime(2026, 11, 14, 9, 30, 12));
      expect(exifTakenDate(Uint8List.fromList(img.encodePng(im))), isNull);
      expect(fileNameDate('IMG_20261114_093012.jpg'), DateTime(2026, 11, 14, 9, 30, 12));
      expect(fileNameDate('PXL_20261114_093012345.jpg'), DateTime(2026, 11, 14, 9, 30, 12));
      expect(fileNameDate('WhatsApp Image 2026-11-14 at 09.30.12.jpeg'), DateTime(2026, 11, 14, 9, 30, 12));
      expect(fileNameDate('DSC_0042.JPG'), isNull);
    });

    test('tri par heure puis attribution corrigée à la main', () {
      BatchPhoto p(String n, [int? min]) =>
          BatchPhoto(n, taken: min == null ? null : DateTime(2026, 1, 1, 9, min), source: TakenSource.exif);
      final photos = [p('c', 3), p('a', 1), p('z'), p('b', 2), p('IMG_10'), p('IMG_2')];
      sortByTaken(photos);
      expect(photos.map((e) => e.name), ['a', 'b', 'c', 'IMG_2', 'IMG_10', 'z']);

      final a = PhotoAssignment(4, photos);
      expect(a.slots.map((e) => e?.name), ['a', 'b', 'c', 'IMG_2']);
      expect(a.spare.map((e) => e.name), ['IMG_10', 'z']);

      // La 2e personne était absente : les photos descendent.
      a.insertGap(1);
      expect(a.slots.map((e) => e?.name), ['a', null, 'b', 'c']);
      expect(a.spare.map((e) => e.name), ['IMG_2', 'IMG_10', 'z']);

      // Photo « b » ratée : retirée, les suivantes remontent.
      a.removeAt(2);
      expect(a.slots.map((e) => e?.name), ['a', null, 'c', 'IMG_2']);
      expect(a.discarded.single.name, 'b');

      a.swap(0, 3);
      expect(a.slots.first?.name, 'IMG_2');
      a.assignSpare(a.discarded.single, 1);
      expect(a.slots[1]?.name, 'b');
      expect(a.discarded, isEmpty);
      a.clear(0);
      expect(a.slots.first, isNull);
      expect(a.spare.first.name, 'IMG_2');
      expect(a.assigned, 3);

      // Moins de photos que de personnes.
      final b = PhotoAssignment(3, [p('x', 1)]);
      expect(b.slots.map((e) => e?.name), ['x', null, null]);
      b.removeAt(0);
      expect(b.slots, [null, null, null]);
    });

    test('champ reconnu d\'après le titre', () {
      expect(studentFieldFor('NOM ET PRÉNOMS'), 'nomComplet');
      expect(studentFieldFor('Date de naissance'), 'dateNaissance');
    });
  });
}
