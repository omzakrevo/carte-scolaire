import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:carte_scolaire/models.dart';
import 'package:carte_scolaire/school/bulletin_pdf.dart';
import 'package:carte_scolaire/school/school_engine.dart';
import 'package:carte_scolaire/school/school_models.dart';
import 'package:flutter_test/flutter_test.dart';

BulletinFonts fonts() {
  ByteData f(String n) => ByteData.sublistView(File('assets/fonts/$n').readAsBytesSync());
  return BulletinFonts.fromBytes(f('Roboto-Regular.ttf'), f('Roboto-Bold.ttf'), f('Roboto-Medium.ttf'));
}

/// Classe d'exemple : notes aléatoires mais reproductibles.
(GradeBook, ClassConfig, List<Student>) sampleClass(String name, SubjectPreset preset, {int n = 12}) {
  final gb = GradeBook();
  final cls = gb.classOf(name)
    ..scale = preset.scale
    ..subjects = preset.build()
    ..titulaire = 'M. TRAORÉ Issa';
  final rnd = Random(4);
  final noms = ['Ouédraogo', 'Kaboré', 'Sawadogo', 'Compaoré', 'Traoré', 'Zongo', 'Ilboudo', 'Somé', 'Kambou', 'Diallo', 'Nikiéma', 'Bationo'];
  final prenoms = ['Awa', 'Jean', 'Mariam', 'Paul', 'Aïcha', 'Issouf', 'Fatimata', 'Boris', 'Salimata', 'Ousmane', 'Rasmata', 'Éric'];
  final students = [
    for (var i = 0; i < n; i++)
      Student(
          nom: noms[i % noms.length],
          prenom: prenoms[i % prenoms.length],
          classe: name,
          sexe: i.isEven ? 'F' : 'M',
          matricule: '2026-${100 + i}',
          dateNaissance: '1${i % 9}/0${1 + i % 9}/2012',
          lieuNaissance: 'Ouagadougou')
  ];
  for (final p in gb.settings.periods) {
    for (final s in students) {
      final level = 0.35 + rnd.nextDouble() * 0.55;
      for (final m in cls.subjects) {
        if (m.conduct) {
          gb.setNote(p.id, s.id, m.id, gb.settings.evals.last.id, (cls.maxOf(m) * (0.7 + rnd.nextDouble() * 0.3)).roundToDouble());
          continue;
        }
        for (final e in gb.settings.evals) {
          final v = (cls.maxOf(m) * (level + (rnd.nextDouble() - 0.5) * 0.3)).clamp(0, cls.maxOf(m));
          gb.setNote(p.id, s.id, m.id, e.id, (v * 4).roundToDouble() / 4);
        }
      }
    }
  }
  gb.setManualAbsences(gb.settings.periods.last.id, students.first.id, AbsenceCount(unjustified: 2, justified: 1, lates: 3));
  gb.council[gb.settings.periods.last.id] = {students.first.id: 'Excellent travail. Continuez ainsi !'};
  return (gb, cls, students);
}

void main() {
  final out = Platform.environment['BULLETIN_DIR'];
  final school = SchoolInfo(
    name: 'Collège Privé Évangélique Maranatha',
    shortName: 'C.P.E MARANATHA',
    ministry: 'Ministère de l\'Enseignement de Base',
    region: 'Région des Cascades – Province de la Léraba',
    signerName: 'M. BAZIÉ Jean',
    directorTitle: 'Le Directeur des études',
  );
  for (final model in bulletinModels) {
    test('bulletins ${model.id}', () async {
      final preset = model.id == 'primaire' ? subjectPresets[1] : subjectPresets[2];
      final (gb, cls, students) = sampleClass(model.id == 'primaire' ? 'CM2 A' : '3e A', preset);
      final last = gb.settings.periods.last;
      final per = [for (final p in gb.settings.periods) computeClass(gb, cls, students, p)];
      final annual = computeAnnual(gb, cls, per);
      final res = per.last;
      final items = [for (final r in res.rows.take(3)) BulletinData(r, res, gb.settings, annual: annual)];
      final bytes = await buildBulletinsPdf(
        items: items,
        school: school,
        model: model.id,
        primaryColor: 0xFF1B4F8C,
        secondaryColor: 0xFF0D2B52,
        fonts: fonts(),
      );
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      final pages = RegExp(r'/Type\s*/Page[^s]').allMatches(String.fromCharCodes(bytes)).length;
      expect(pages, 3, reason: 'un bulletin par page, sans débordement');
      expect(last.id, isNotEmpty);
      if (out != null) File('$out/bulletin_${model.id}.pdf').writeAsBytesSync(bytes);
    });
  }
}
