import 'dart:io';
import 'dart:typed_data';

import 'package:carte_scolaire/models.dart';
import 'package:carte_scolaire/school/bulletin_pdf.dart';
import 'package:carte_scolaire/school/school_models.dart';
import 'package:carte_scolaire/school/timetable_pdf.dart';
import 'package:carte_scolaire/school/timetable_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  GradeBook build() {
    final gb = GradeBook();
    final maths = Teacher(name: 'M. Ouédraogo');
    final fr = Teacher(name: 'Mme Kaboré');
    final ang = Teacher(name: 'M. Traoré', unavailable: {'1|0', '1|1'});
    gb.teachers.addAll([maths, fr, ang]);
    for (final c in ['6e A', '6e B', '5e A']) {
      final cls = gb.classOf(c)..subjects = subjectPresets[2].build();
      for (final s in cls.subjects) {
        if (s.name == 'Mathématiques') gb.assign(s, maths);
        if (s.name == 'Français') gb.assign(s, fr);
        if (s.name == 'Anglais') gb.assign(s, ang);
      }
    }
    return gb;
  }

  test('volumes horaires par défaut', () {
    final s = subjectPresets[2].build();
    expect(s.firstWhere((x) => x.name == 'Français').hours, 5);
    expect(s.firstWhere((x) => x.name == 'Conduite').hours, 0);
    final total = s.fold(0, (a, x) => a + x.hours);
    expect(total, lessThanOrEqualTo(TimetableSettings().usable().length));
  });

  test('génération : tout est placé, sans conflit de professeur ni indisponibilité', () {
    final gb = build();
    final classes = gb.classes.keys.toList();
    final r = generateTimetable(gb, classes);
    gb.timetable = r.table;
    expect(r.unplaced, isEmpty);
    expect(findConflicts(gb), isEmpty);
    for (final c in classes) {
      for (final e in classCoverage(gb, c).values) {
        expect(e.$2, e.$1);
      }
      // Pas de cours pendant la récréation ni le mercredi après-midi.
      final keys = gb.timetable[c]!.keys;
      expect(keys.any((k) => k.endsWith('|3')), isFalse);
      expect(keys.contains('3|6') || keys.contains('3|7'), isFalse);
    }
    final ang = gb.teachers[2];
    final sched = teacherSchedule(gb, ang.id);
    expect(sched.keys.toSet().intersection(ang.unavailable), isEmpty);
    expect(sched.length, 9, reason: '3 h d\'anglais × 3 classes');
    // Une matière n'apparaît pas plus de 2 fois le même jour.
    for (final c in classes) {
      final perDay = <String, int>{};
      for (final e in gb.timetable[c]!.entries) {
        final k = '${e.key.split('|').first}-${e.value.subjectId}';
        perDay[k] = (perDay[k] ?? 0) + 1;
      }
      expect(perDay.values.every((v) => v <= 2), isTrue);
    }
  });

  test('séances verrouillées gardées, professeur saturé signalé', () {
    final gb = build();
    final c = gb.classOf('6e A');
    final fr = c.subjects.firstWhere((s) => s.name == 'Français');
    gb.timetable['6e A'] = {'2|0': Lesson(fr.id, locked: true)};
    final r = generateTimetable(gb, ['6e A']);
    expect(r.table['6e A']!['2|0']!.subjectId, fr.id);
    expect(r.table['6e A']!.values.where((l) => l.subjectId == fr.id).length, 5);
    // Un professeur limité à 4 h ne peut pas tout prendre.
    gb.teachers[0].maxHours = 4;
    final r2 = generateTimetable(gb, gb.classes.keys.toList());
    expect(r2.unplaced.join(), contains('Mathématiques'));
  });

  test('sauvegarde des professeurs et de l\'emploi du temps', () {
    final gb = build();
    gb.timetable = generateTimetable(gb, ['6e A']).table;
    final j = GradeBook.fromJson(gb.toJson());
    expect(j.teachers.length, 3);
    expect(j.teachers[2].unavailable, {'1|0', '1|1'});
    expect(j.timetable['6e A']!.length, gb.timetable['6e A']!.length);
    expect(j.classes['6e A']!.subjects.firstWhere((s) => s.name == 'Français').teacherId, gb.teachers[1].id);
    expect(j.teacherName(j.classes['6e A']!.subjects.first), 'Mme Kaboré');
    expect(j.teacherHours(gb.teachers[0].id), 15);
    j.renameClass('6e A', '6e A1');
    expect(j.classes.containsKey('6e A1'), isTrue);
    expect(j.timetable.containsKey('6e A1'), isTrue);
  });

  test('PDF de l\'emploi du temps : une page par classe et par professeur', () async {
    final gb = build();
    gb.timetable = generateTimetable(gb, gb.classes.keys.toList()).table;
    ByteData f(String n) => ByteData.sublistView(File('assets/fonts/$n').readAsBytesSync());
    final bytes = await buildTimetablePdf(
      gb: gb,
      school: SchoolInfo(name: 'Lycée Municipal'),
      classes: gb.classes.keys.toList(),
      teachers: gb.teachers,
      fonts: BulletinFonts.fromBytes(f('Roboto-Regular.ttf'), f('Roboto-Bold.ttf'), f('Roboto-Medium.ttf')),
    );
    final pages = RegExp(r'/Type\s*/Page[^s]').allMatches(String.fromCharCodes(bytes)).length;
    expect(pages, 6);
    final out = Platform.environment['BULLETIN_DIR'];
    if (out != null) File('$out/emploi_du_temps.pdf').writeAsBytesSync(bytes);
  });
}
