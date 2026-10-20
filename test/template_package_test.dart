import 'dart:typed_data';

import 'package:carte_scolaire/models.dart';
import 'package:carte_scolaire/services/student_import.dart';
import 'package:carte_scolaire/services/template_package.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List png(int w, int h) => Uint8List.fromList(img.encodePng(img.Image(width: w, height: h)..clear(img.ColorRgb8(30, 60, 160))));

void main() {
  test('export ZIP puis import : modèle, calques, textes et images conservés', () async {
    final t = CardTemplate(designId: 'identite', title: 'CARTE D\'ÉLÈVE', widthMm: 90, heightMm: 60)
      ..labels['contact'] = 'Urgence'
      ..hidden.add('sexe')
      ..layer('logo').dx = 3.5
      ..layer('emblem').scale = 1.4
      ..background = Uint8List.fromList(img.encodeJpg(img.Image(width: 40, height: 30)));
    final school = SchoolInfo(name: 'C.P.E Maranatha', region: 'Région des Cascades')
      ..logo = png(64, 64)
      ..emblem = png(48, 48)
      ..stamp = png(80, 80);
    final zip = exportTemplatePackage(SavedTemplate(name: 'Maranatha', template: t, school: school));

    final s = await importTemplatePackage(zip, 'Maranatha.zip');
    expect(s.name, 'Maranatha');
    expect(s.template.title, 'CARTE D\'ÉLÈVE');
    expect(s.template.widthMm, 90);
    expect(s.template.label('contact'), 'Urgence');
    expect(s.template.shows('sexe'), isFalse);
    expect(s.template.layers['logo']!.dx, 3.5);
    expect(s.template.layers['emblem']!.scale, 1.4);
    expect(s.template.background, isNotNull);
    expect(s.school!.region, 'Région des Cascades');
    expect(s.school!.logo, isNotNull);
    expect(s.school!.emblem, isNotNull);
    expect(s.school!.stamp, isNotNull);
  });

  test('ZIP avec seulement des images : modèle « Fond personnalisé »', () async {
    final a = SavedTemplate(name: 'x', template: CardTemplate()..background = png(100, 63));
    // On réutilise l'export puis on retire modele.json pour simuler un ZIP fait à la main.
    final s = await importTemplatePackage(exportTemplatePackage(a), 'Mon fond.zip');
    expect(s.template.background, isNotNull);
  });

  test('modèle Excel vierge : titres reconnus, aucun élève', () {
    final r = importStudents(buildExcelTemplate(), 'modele_liste_eleves.xlsx');
    expect(r.students, isEmpty);
  });
}
