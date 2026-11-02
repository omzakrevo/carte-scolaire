import 'dart:typed_data';

import 'package:carte_scolaire/attendance/attendance_export.dart';
import 'package:carte_scolaire/attendance/attendance_models.dart';
import 'package:carte_scolaire/card_kinds.dart';
import 'package:carte_scolaire/models.dart';
import 'package:carte_scolaire/services/license.dart';
import 'package:carte_scolaire/services/student_import.dart';
import 'package:carte_scolaire/services/template_package.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List png() => Uint8List.fromList(img.encodePng(img.Image(width: 20, height: 20)..clear(img.ColorRgb8(200, 0, 0))));

void main() {
  test('licence : modules lus, anciens codes = scolaire + pointage', () {
    final a = LicenseInfo.parse('CS1|L-1|ABCDE-FGHJK|Y1|20991231|20261102|visite,pro');
    expect(a!.modules, {'visite', 'pro'});
    final b = LicenseInfo.parse('CS1|L-2|ABCDE-FGHJK|LIFE|0|20261102');
    expect(b!.modules, legacyModules);
  });

  test('type de carte : libellés et champs', () {
    final t = CardTemplate();
    expect(t.shows('email'), isFalse, reason: 'nouveaux champs masqués sur une carte scolaire');
    applyKind(t, kindById('visite'));
    expect(t.designId, 'visite_bandeau_nom');
    expect(t.shows('email'), isTrue);
    expect(t.shows('dateNaissance'), isFalse);
    applyKind(t, kindById('pro'));
    expect(t.label('classe'), 'Service');
    expect(t.label('service'), 'Fonction');
    // Ancien modèle enregistré sans type : les nouveaux champs restent masqués.
    final old = CardTemplate.fromJson({
      'designId': 'identite',
      'hidden': ['sexe']
    });
    expect(old.shows('adresse'), isFalse);
    expect(old.shows('sexe'), isFalse);
  });

  test('ZIP : éléments (texte, forme, image), couleurs et galerie conservés', () async {
    final t = CardTemplate(designId: 'visite_galerie', primary: 0xFF123456, kind: 'visite')
      ..elements.addAll([
        CardElement(type: 'text', text: 'Bonjour {prenom}', color: 0xFFAA0000, fill: 0xFFFFFF00, bold: true),
        CardElement(type: 'rect', x: 1, y: 2, w: 10, h: 5, color: 0xFF00AA00, radius: 2, borderWidth: 0.5),
        CardElement(type: 'image', image: png()),
      ]);
    final school = SchoolInfo(name: 'OMZAKREVO', services: 'Réseaux\nCaméras', website: 'omzakrevo.bf')
      ..gallery = [png(), png()];
    final zip = exportTemplatePackage(SavedTemplate(name: 'Visite', template: t, school: school));
    final s = await importTemplatePackage(zip, 'Visite.zip');
    expect(s.template.kind, 'visite');
    expect(s.template.primary, 0xFF123456);
    expect(s.template.elements, hasLength(3));
    expect(s.template.elements[0].text, 'Bonjour {prenom}');
    expect(s.template.elements[0].fill, 0xFFFFFF00);
    expect(s.template.elements[1].radius, 2);
    expect(s.template.elements[2].image, isNotNull);
    expect(s.school!.serviceList, ['Réseaux', 'Caméras']);
    expect(s.school!.website, 'omzakrevo.bf');
    expect(s.school!.gallery, hasLength(2));
  });

  test('modèle Excel selon le type de carte, relu à l\'import', () {
    final t = CardTemplate();
    applyKind(t, kindById('pro'));
    final bytes = buildExcelTemplate(template: t, sheetName: 'Employés', person: 'employé');
    final x = Excel.decodeBytes(bytes);
    final head = x.tables['Employés']!.rows.first.map((c) => c?.value.toString()).toList();
    expect(head, containsAll(['Matricule', 'Nom', 'Prénom(s)', 'Fonction', 'Service', 'Téléphone']));
    final sheet = x['Employés'];
    final row = ['P-01', 'KONE', 'Moussa', 'Directeur', 'Direction', '70 11 22 33'];
    for (var i = 0; i < head.length; i++) {
      final k = head[i]!;
      final v = {
        'Matricule': row[0],
        'Nom': row[1],
        'Prénom(s)': row[2],
        'Fonction': row[3],
        'Service': row[4],
        'Téléphone': row[5]
      }[k];
      if (v != null) sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 1)).value = TextCellValue(v);
    }
    final r = importStudents(Uint8List.fromList(x.encode()!), 'employes.xlsx');
    expect(r.students, hasLength(1));
    final s = r.students.first;
    expect(s.service, 'Directeur');
    expect(s.classe, 'Direction');
    expect(s.contact, '70 11 22 33');
  });

  test('entreprise : heures travaillées, pause, retard, sortie oubliée', () {
    final st = AttendanceSettings(startTime: '07:30', endTime: '17:00', breakMin: 60, lateToleranceMin: 10);
    expect(st.expectedMinutes, 510);
    final a = Student(nom: 'A'), b = Student(nom: 'B'), c = Student(nom: 'C');
    DateTime t(int h, int m) => DateTime(2026, 11, 2, h, m);
    final day = DayRecord('2026-11-02', events: [
      // A : journée complète sans pointer à midi → pause déduite.
      ScanEvent(studentId: a.id, time: t(7, 25), entry: true),
      ScanEvent(studentId: a.id, time: t(17, 10), entry: false),
      // B : en retard, pointe à midi, part à 16 h.
      ScanEvent(studentId: b.id, time: t(8, 0), entry: true),
      ScanEvent(studentId: b.id, time: t(12, 0), entry: false),
      ScanEvent(studentId: b.id, time: t(13, 0), entry: true),
      ScanEvent(studentId: b.id, time: t(16, 0), entry: false),
      // C : arrivé, jamais ressorti.
      ScanEvent(studentId: c.id, time: t(7, 30), entry: true),
    ]);
    final later = DateTime(2026, 11, 3, 9);
    final da = computeDay(a, day, st, t(0, 0), now: later);
    expect(da.workedMin, 585 - 60);
    expect(da.status, DayStatus.present);
    final db = computeDay(b, day, st, t(0, 0), now: later);
    expect(db.workedMin, 240 + 180);
    expect(db.status, DayStatus.late);
    expect(db.lateMin, 30);
    expect(db.earlyMin, 60);
    final dc = computeDay(c, day, st, t(0, 0), now: later);
    expect(dc.missingExit, isTrue);
    expect(dc.workedMin, 570 - 60);
    expect(hoursLabel(dc.workedMin), '8 h 30');

    final bytes = buildAttendanceExcel(
      students: [a, b, c],
      days: [day],
      settings: st,
      school: SchoolInfo(name: 'X'),
      from: t(0, 0),
      to: t(0, 0),
      company: true,
      groupLabel: 'Service',
      now: later,
    );
    final x = Excel.decodeBytes(bytes);
    final rows = x.tables['Synthèse']!.rows.map((r) => r.map((c) => c?.value?.toString() ?? '').join('|')).toList();
    expect(rows.any((r) => r.contains('Heures travaillées')), isTrue);
    expect(rows.firstWhere((r) => r.contains('|B|')), contains('7 h 00'));
  });

  test('verso : modèle, texte et éléments du verso conservés', () {
    final t = CardTemplate()
      ..versoDesign = 'verso_services'
      ..versoText = 'Rendez cette carte à {ecole}'
      ..elements.add(CardElement(type: 'text', text: 'Au dos', back: true));
    final j = CardTemplate.fromJson(t.toJson());
    expect(j.versoDesign, 'verso_services');
    expect(j.hasVerso, isTrue);
    expect(j.versoText, 'Rendez cette carte à {ecole}');
    expect(j.elements.single.back, isTrue);
    expect(j.copy().elements.single.back, isTrue);
    expect(CardTemplate().hasVerso, isFalse);
  });
}
