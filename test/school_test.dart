import 'package:carte_scolaire/attendance/attendance_models.dart';
import 'package:carte_scolaire/models.dart';
import 'package:carte_scolaire/school/school_controller.dart';
import 'package:carte_scolaire/school/school_engine.dart';
import 'package:carte_scolaire/school/school_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late GradeBook gb;
  late ClassConfig cls;
  late Period t1;
  late Student awa, jean, paul;
  late Subject fr, maths, conduite;
  late String d1, d2, compo;

  setUp(() {
    gb = GradeBook(settings: SchoolSettings(latesPerAbsence: 3, conductPenalty: 1));
    t1 = gb.settings.periods.first;
    d1 = gb.settings.evals[0].id;
    d2 = gb.settings.evals[1].id;
    compo = gb.settings.evals[2].id; // poids 2
    cls = gb.classOf('3e A');
    fr = Subject(name: 'Français', coef: 3);
    maths = Subject(name: 'Mathématiques', coef: 2);
    conduite = Subject(name: 'Conduite', coef: 1, conduct: true);
    cls.subjects.addAll([fr, maths, conduite]);
    awa = Student(nom: 'Ouédraogo', prenom: 'Awa', classe: '3e A', sexe: 'F');
    jean = Student(nom: 'Kaboré', prenom: 'Jean', classe: '3e A', sexe: 'M');
    paul = Student(nom: 'Sawadogo', prenom: 'Paul', classe: '3e A', sexe: 'M');
  });

  test('barème deviné d\'après la classe', () {
    expect(guessScale('CM2 A'), 10);
    expect(guessScale('CE1'), 10);
    expect(guessScale('6e B'), 20);
    expect(guessScale('Tle D'), 20);
  });

  test('moyennes pondérées, coefficients, rangs et ex aequo', () {
    // Awa : Français (12 + 14 + 2×16)/4 = 14.5 ; Maths (10, -, 2×13)/3 = 12 ; Conduite 18.
    gb.setNote(t1.id, awa.id, fr.id, d1, 12);
    gb.setNote(t1.id, awa.id, fr.id, d2, 14);
    gb.setNote(t1.id, awa.id, fr.id, compo, 16);
    gb.setNote(t1.id, awa.id, maths.id, d1, 10);
    gb.setNote(t1.id, awa.id, maths.id, compo, 13);
    gb.setNote(t1.id, awa.id, conduite.id, compo, 18);
    // Jean et Paul : 11 partout.
    for (final s in [jean, paul]) {
      for (final m in [fr, maths, conduite]) {
        gb.setNote(t1.id, s.id, m.id, compo, 11);
      }
    }
    final r = computeClass(gb, cls, [awa, jean, paul], t1);
    final a = r.of(awa.id)!;
    expect(a.subjects[0].average, 14.5);
    expect(a.subjects[1].average, 12);
    // (14.5×3 + 12×2 + 18×1) / 6 = 14.25
    expect(a.average, closeTo(14.25, 1e-9));
    expect(a.rank, 1);
    expect(a.mention, 'Encouragements');
    expect(r.of(jean.id)!.rank, 2);
    expect(r.of(jean.id)!.exAequo, isTrue);
    expect(r.of(paul.id)!.rank, 2);
    expect(r.classAverage, closeTo((14.25 + 11 + 11) / 3, 1e-9));
    expect(r.best, 14.25);
    expect(a.subjects[0].rank, 1);
    expect(a.subjects[0].classAverage, closeTo((14.5 + 11 + 11) / 3, 1e-9));
    expect(ordinal(1, female: true), '1re');
    expect(ordinal(2, exAequo: true), '2e ex');
  });

  test('absences : retenue sur la conduite (absences non justifiées + retards convertis)', () {
    gb.setNote(t1.id, awa.id, fr.id, compo, 12);
    gb.setNote(t1.id, awa.id, conduite.id, compo, 18);
    // 2 absences non justifiées saisies + 4 retards du pointage (3 retards = 1 absence) → 3 unités.
    gb.setManualAbsences(t1.id, awa.id, AbsenceCount(unjustified: 2, justified: 1));
    final r = computeClass(gb, cls, [awa], t1, auto: {awa.id: AbsenceCount(lates: 4)});
    final a = r.of(awa.id)!;
    expect(a.absences.unjustified, 2);
    expect(a.absences.justified, 1);
    expect(a.absences.lates, 4);
    expect(penaltyUnits(a.absences, gb.settings), 3);
    expect(a.subjects[2].penalty, 3);
    expect(a.subjects[2].average, 15);
    // Conduite non notée : on part de la note maximale.
    gb.notes[t1.id]![awa.id]!.remove(conduite.id);
    final b = computeClass(gb, cls, [awa], t1, auto: {awa.id: AbsenceCount(lates: 4)}).of(awa.id)!;
    expect(b.subjects[2].average, 17);
  });

  test('absences : retenue possible sur la moyenne générale, barème sur 10', () {
    final cm2 = gb.classOf('CM2');
    expect(cm2.scale, 10);
    final calc = Subject(name: 'Calcul');
    cm2.subjects.add(calc);
    gb.settings.averagePenalty = 1; // 1 point sur 20 = 0,5 sur 10
    gb.setNote(t1.id, awa.id, calc.id, compo, 8);
    gb.setManualAbsences(t1.id, awa.id, AbsenceCount(unjustified: 2));
    final a = computeClass(gb, cm2, [awa], t1).of(awa.id)!;
    expect(a.averagePenalty, 1);
    expect(a.average, 7);
  });

  test('moyenne annuelle et décision', () {
    final t2 = gb.settings.periods[1];
    gb.setNote(t1.id, awa.id, fr.id, compo, 9);
    gb.setNote(t2.id, awa.id, fr.id, compo, 13);
    gb.setNote(t1.id, jean.id, fr.id, compo, 8);
    final per = [for (final p in gb.settings.periods) computeClass(gb, cls, [awa, jean], p)];
    final an = computeAnnual(gb, cls, per);
    final a = an.firstWhere((x) => x.student == awa);
    expect(a.average, closeTo(11, 1e-9)); // conduite non notée sans absence : ignorée
    expect(a.decision, 'Admise en classe supérieure');
    expect(a.rank, 1);
    expect(an.firstWhere((x) => x.student == jean).decision, 'Redouble');
    gb.decisions[jean.id] = 'Admis au rattrapage';
    expect(computeAnnual(gb, cls, per).firstWhere((x) => x.student == jean).decision, 'Admis au rattrapage');
  });

  test('comptage des absences depuis le pointage', () {
    final st = AttendanceSettings();
    final day = DayRecord('2026-11-02', events: [
      ScanEvent(studentId: awa.id, time: DateTime(2026, 11, 2, 7, 10), entry: true),
      ScanEvent(studentId: jean.id, time: DateTime(2026, 11, 2, 8, 10), entry: true),
    ], overrides: {
      paul.id: DayOverride.excused
    });
    final empty = DayRecord('2026-11-03'); // personne n'a pointé : jour ignoré
    final closed = DayRecord('2026-11-04', closed: true);
    final day2 = DayRecord('2026-11-05', events: [
      ScanEvent(studentId: awa.id, time: DateTime(2026, 11, 5, 7, 10), entry: true),
    ]);
    final c = countAbsences([day, empty, closed, day2], [awa, jean, paul], st);
    expect(c[awa.id]!.total, 0);
    expect(c[jean.id]!.lates, 1);
    expect(c[jean.id]!.unjustified, 1);
    expect(c[paul.id]!.justified, 1);
    expect(c[paul.id]!.unjustified, 1);
  });

  test('sauvegarde et relecture du carnet', () {
    gb.setNote(t1.id, awa.id, fr.id, d1, 12.5);
    gb.setManualAbsences(t1.id, awa.id, AbsenceCount(unjustified: 1));
    gb.council[t1.id] = {awa.id: 'Bon trimestre'};
    gb.decisions[awa.id] = 'Admise';
    final j = GradeBook.fromJson(gb.toJson());
    expect(j.note(t1.id, awa.id, fr.id, d1), 12.5);
    expect(j.manualAbsences(t1.id, awa.id).unjustified, 1);
    expect(j.council[t1.id]![awa.id], 'Bon trimestre');
    expect(j.classes['3e A']!.subjects.length, 3);
    expect(j.classes['3e A']!.subjects[2].conduct, isTrue);
    expect(j.settings.periods.length, 3);
    expect(parseNote(' 12,75 '), 12.75);
    expect(parseNote(''), isNull);
    expect(fmt(12.5), '12,50');
  });
}
