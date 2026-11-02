import 'package:carte_scolaire/app_state.dart';
import 'package:carte_scolaire/attendance/attendance_controller.dart';
import 'package:carte_scolaire/attendance/attendance_export.dart';
import 'package:carte_scolaire/attendance/attendance_models.dart';
import 'package:carte_scolaire/models.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppState app;
  late AttendanceController ctrl;
  late DateTime now;
  late Student awa, jean, paul;
  final sent = <(String, String)>[];

  setUp(() {
    app = AppState()..loaded = true;
    awa = Student(matricule: 'M001', nom: 'Ouédraogo', prenom: 'Awa', classe: '6e A', contact: '70 11 22 33');
    jean = Student(matricule: 'M002', nom: 'Kaboré', prenom: 'Jean', classe: '6e A', contact: '+226 76 00 00 01');
    paul = Student(matricule: 'M003', nom: 'Sawadogo', prenom: 'Paul', classe: '5e B');
    app.students.addAll([awa, jean, paul]);
    app.school.name = 'Complexe scolaire Maranatha';
    now = DateTime(2026, 11, 2, 7, 15); // lundi
    sent.clear();
    ctrl = AttendanceController(app)
      ..clock = (() => now)
      ..smsGap = Duration.zero
      ..sender = (to, text) async => sent.add((to, text));
  });

  tearDown(() => ctrl.dispose());

  test('le QR contient le matricule, sinon l\'identifiant', () {
    expect(awa.qrData, 'M001');
    expect(Student(nom: 'X').qrData, startsWith('CS:'));
  });

  test('retrouver un élève à partir du code lu', () {
    expect(findStudentByCode('M002', app.students), jean);
    expect(findStudentByCode(' m002 \n', app.students), jean);
    expect(findStudentByCode('CS:${paul.id}', app.students), paul);
    expect(findStudentByCode('inconnu', app.students), isNull);
  });

  test('entrée, anti-doublon, sortie automatique, retard', () {
    final r1 = ctrl.scan('M001');
    expect(r1.entry, isTrue);
    expect(r1.late, isFalse);

    now = now.add(const Duration(seconds: 20));
    final dup = ctrl.scan('M001');
    expect(dup.duplicate, isTrue);
    expect(ctrl.today.events.length, 1);

    now = DateTime(2026, 11, 2, 12, 0);
    final r2 = ctrl.scan('M001');
    expect(r2.entry, isFalse, reason: 'le 2e passage est une sortie');

    now = DateTime(2026, 11, 2, 7, 50);
    final late = ctrl.scan('M002');
    expect(late.entry, isTrue);
    expect(late.late, isTrue, reason: 'après 07:30 + 10 min');

    expect(ctrl.scan('???').unknown, isTrue);

    now = DateTime(2026, 11, 2, 12, 5);
    final days = {for (final d in ctrl.todaySummary()) d.student: d};
    expect(days[awa]!.status, DayStatus.present);
    expect(days[awa]!.isOut, isTrue);
    expect(days[jean]!.status, DayStatus.late);
    expect(days[paul]!.status, DayStatus.absent);
  });

  test('mode Entrée forcé et correction manuelle', () {
    ctrl.settings.mode = ScanMode.entry;
    ctrl.scan('M001');
    now = now.add(const Duration(minutes: 5));
    expect(ctrl.scan('M001').entry, isTrue);
    ctrl.setOverride(paul, DayOverride.excused);
    now = DateTime(2026, 11, 2, 10, 0);
    final d = ctrl.todaySummary().firstWhere((d) => d.student == paul);
    expect(d.status, DayStatus.excused);
  });

  test('SMS automatique aux parents des absents, une seule fois', () async {
    ctrl.scan('M001');
    now = DateTime(2026, 11, 2, 8, 30);
    await ctrl.checkAutoAbsences();
    expect(sent, isEmpty, reason: 'avant l\'heure des absences');

    now = DateTime(2026, 11, 2, 9, 1);
    await ctrl.checkAutoAbsences();
    expect(sent.length, 1, reason: 'Jean absent avec numéro ; Paul sans numéro');
    expect(sent.first.$1, '+22676000001');
    expect(sent.first.$2, contains('Jean KABORÉ'));
    expect(sent.first.$2, contains('6e A'));
    expect(ctrl.today.sms[jean.id], startsWith('Envoyé'));
    expect(ctrl.today.sms[paul.id], 'Pas de numéro');
    expect(ctrl.today.absencesProcessed, isTrue);

    await ctrl.checkAutoAbsences();
    expect(sent.length, 1, reason: 'pas de 2e envoi');
  });

  test('pas de SMS sans licence, un jour sans pointage ou un jour sans école', () async {
    now = DateTime(2026, 11, 2, 9, 30);
    await ctrl.checkAutoAbsences();
    expect(sent, isEmpty, reason: 'personne n\'a pointé');

    ctrl.scan('M001');
    ctrl.smsAllowed = () => false;
    await ctrl.checkAutoAbsences();
    expect(sent, isEmpty);
    expect(ctrl.today.absencesProcessed, isTrue);
  });

  test('un samedi n\'est pas un jour de classe', () async {
    now = DateTime(2026, 11, 7, 9, 30);
    ctrl.scan('M001');
    await ctrl.checkAutoAbsences();
    expect(sent, isEmpty);
  });

  test('numéros et message', () {
    expect(normalizePhone('70 11 22 33', '226'), '+22670112233');
    expect(normalizePhone('0022670112233', '226'), '+22670112233');
    expect(normalizePhone('', '226'), isNull);
    expect(normalizePhone('Papa', '226'), isNull);
    final m =
        buildSms(AttendanceSettings.defaultTemplate, awa, app.school, DateTime(2026, 11, 2), withoutAccents: true);
    expect(m, isNot(contains('é')));
    expect(m, contains('Awa OUEDRAOGO'));
    expect(smsSegments('a' * 160), 1);
    expect(smsSegments('é' * 71), 1);
    expect(smsSegments('ê' * 71), 2);
  });

  test('export Excel : trois feuilles, statuts corrects', () {
    final d1 = DayRecord('2026-11-02', events: [
      ScanEvent(studentId: awa.id, time: DateTime(2026, 11, 2, 7, 10), entry: true),
      ScanEvent(studentId: awa.id, time: DateTime(2026, 11, 2, 12, 0), entry: false),
      ScanEvent(studentId: jean.id, time: DateTime(2026, 11, 2, 7, 55), entry: true),
    ]);
    final d2 = DayRecord('2026-11-03', events: [
      ScanEvent(studentId: awa.id, time: DateTime(2026, 11, 3, 7, 20), entry: true),
    ], overrides: {
      paul.id: DayOverride.excused
    });
    final bytes = buildAttendanceExcel(
      students: app.students,
      days: [d1, d2],
      settings: AttendanceSettings(),
      school: app.school,
      from: DateTime(2026, 11, 1),
      to: DateTime(2026, 11, 30),
      trial: true,
      now: DateTime(2026, 11, 4),
    );
    final x = Excel.decodeBytes(bytes);
    expect(x.tables.keys, containsAll(['Synthèse', 'Par jour', 'Pointages']));
    final syn = x.tables['Synthèse']!;
    String row(int r) => syn.rows[r].map((c) => c?.value?.toString() ?? '').join('|');
    final all = [for (var r = 0; r < syn.maxRows; r++) row(r)];
    expect(all.first, contains('VERSION D\'ESSAI'));
    final awaRow = all.firstWhere((r) => r.startsWith('M001'));
    expect(awaRow, contains('|2|2|0|0|0|100 %'));
    final jeanRow = all.firstWhere((r) => r.startsWith('M002'));
    expect(jeanRow, contains('|2|1|1|1|0|50 %'));
    final paulRow = all.firstWhere((r) => r.startsWith('M003'));
    expect(paulRow, contains('|2|0|0|1|1|0 %'));
    expect(x.tables['Pointages']!.maxRows, greaterThanOrEqualTo(4 + 4));
  });
}
