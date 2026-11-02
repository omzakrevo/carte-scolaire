import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../models.dart';
import 'attendance_models.dart';

/// Rapport de présences au format Excel, trois feuilles :
///  - Synthèse : une ligne par élève (présences, retards, absences, taux) ;
///  - Par jour : une ligne par élève et par jour (statut, arrivée, sortie, SMS) ;
///  - Pointages : chaque passage de carte.
Uint8List buildAttendanceExcel({
  required List<Student> students,
  required List<DayRecord> days,
  required AttendanceSettings settings,
  required SchoolInfo school,
  required DateTime from,
  required DateTime to,
  String? classFilter,
  bool trial = false,
  bool company = false,
  String groupLabel = 'Classe',
  DateTime? now,
}) {
  now ??= DateTime.now();
  final list =
      students.where((s) => classFilter == null || classFilter.isEmpty || s.classe.trim() == classFilter).toList()
        ..sort((a, b) {
          final c = a.classe.compareTo(b.classe);
          return c != 0 ? c : a.fullName.compareTo(b.fullName);
        });
  final schoolDays = days.where((d) => !d.closed && (d.events.isNotEmpty || d.overrides.isNotEmpty)).toList();
  final byId = {for (final s in students) s.id: s};

  final excel = Excel.createExcel();
  final defaultName = excel.getDefaultSheet()!;
  excel.rename(defaultName, 'Synthèse');

  final head = CellStyle(
    bold: true,
    fontColorHex: ExcelColor.fromHexString('#FFFFFFFF'),
    backgroundColorHex: ExcelColor.fromHexString('#FF1B2A6B'),
    horizontalAlign: HorizontalAlign.Center,
  );
  final title = CellStyle(bold: true, fontSize: 14);
  final red = CellStyle(fontColorHex: ExcelColor.fromHexString('#FFC62828'), bold: true);
  final orange = CellStyle(fontColorHex: ExcelColor.fromHexString('#FFB25E00'), bold: true);
  final green = CellStyle(fontColorHex: ExcelColor.fromHexString('#FF0B6B3A'), bold: true);

  int writeHeader(Sheet sh, String t, List<String> cols, List<double> widths) {
    var r = 0;
    if (trial) {
      sh.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r++))
        ..value = TextCellValue('VERSION D\'ESSAI – rapport non valable. Activez une licence Carte Scolaire.')
        ..cellStyle = red;
    }
    sh.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r++))
      ..value = TextCellValue('$t – ${school.name}')
      ..cellStyle = title;
    sh.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r++)).value = TextCellValue(
        'Période du ${frDate(from)} au ${frDate(to)}${classFilter?.isNotEmpty == true ? ' · $groupLabel $classFilter' : ''}'
        ' · Édité le ${frDate(now!)} à ${hhmm(now)}');
    r++;
    for (var i = 0; i < cols.length; i++) {
      sh.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: r))
        ..value = TextCellValue(cols[i])
        ..cellStyle = head;
      sh.setColumnWidth(i, widths[i]);
    }
    return r + 1;
  }

  void put(Sheet sh, int r, int c, CellValue v, [CellStyle? st]) {
    final cell = sh.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r));
    cell.value = v;
    if (st != null) cell.cellStyle = st;
  }

  // ---------- Synthèse ----------
  final syn = excel['Synthèse'];
  var r = company
      ? writeHeader(syn, 'Synthèse des heures de travail', [
          'Matricule',
          'Nom',
          'Prénom(s)',
          groupLabel,
          'Jours ouvrés',
          'Jours présents',
          'Absences',
          'Absences justifiées',
          'Retards',
          'Total retards',
          'Heures travaillées',
          'Heures prévues',
          'Écart (heures sup.)',
          'Départs anticipés',
          'Sorties non pointées'
        ], [
          14,
          18,
          22,
          14,
          12,
          13,
          11,
          18,
          10,
          13,
          17,
          15,
          18,
          16,
          19
        ])
      : writeHeader(syn, 'Synthèse des présences', [
          'Matricule',
          'Nom',
          'Prénom(s)',
          groupLabel,
          'Jours de classe',
          'Présences',
          'Dont retards',
          'Absences',
          'Absences justifiées',
          'Taux de présence',
          'Contact parent'
        ], [
          14,
          18,
          22,
          10,
          14,
          12,
          12,
          12,
          18,
          16,
          18
        ]);
  for (final s in list) {
    var p = 0, late = 0, abs = 0, exc = 0, worked = 0, lateMin = 0, early = 0, missing = 0;
    for (final d in schoolDays) {
      final sd = computeDay(s, d, settings, parseDateKey(d.date), now: now);
      worked += sd.workedMin;
      lateMin += sd.lateMin;
      if (sd.earlyMin > 0) early++;
      if (sd.missingExit) missing++;
      switch (sd.status) {
        case DayStatus.present:
          p++;
        case DayStatus.late:
          p++;
          late++;
        case DayStatus.absent:
          abs++;
        case DayStatus.excused:
          exc++;
        case DayStatus.notYet:
          break;
      }
    }
    final counted = p + abs + exc;
    final rate = counted == 0 ? 0.0 : p / counted;
    put(syn, r, 0, TextCellValue(s.matricule));
    put(syn, r, 1, TextCellValue(s.nom.toUpperCase()));
    put(syn, r, 2, TextCellValue(s.prenom));
    put(syn, r, 3, TextCellValue(s.classe));
    put(syn, r, 4, IntCellValue(counted));
    if (company) {
      final expected = p * settings.expectedMinutes;
      final diff = worked - expected;
      put(syn, r, 5, IntCellValue(p));
      put(syn, r, 6, IntCellValue(abs), abs > 0 ? red : null);
      put(syn, r, 7, IntCellValue(exc));
      put(syn, r, 8, IntCellValue(late), late > 0 ? orange : null);
      put(syn, r, 9, TextCellValue(hoursLabel(lateMin)), lateMin > 0 ? orange : null);
      put(syn, r, 10, TextCellValue(hoursLabel(worked)), green);
      put(syn, r, 11, TextCellValue(hoursLabel(expected)));
      put(syn, r, 12, TextCellValue(diff >= 0 ? '+${hoursLabel(diff)}' : hoursLabel(diff)), diff < 0 ? red : green);
      put(syn, r, 13, IntCellValue(early), early > 0 ? orange : null);
      put(syn, r, 14, IntCellValue(missing), missing > 0 ? red : null);
    } else {
      put(syn, r, 5, IntCellValue(p));
      put(syn, r, 6, IntCellValue(late), late > 0 ? orange : null);
      put(syn, r, 7, IntCellValue(abs), abs > 0 ? red : null);
      put(syn, r, 8, IntCellValue(exc));
      put(syn, r, 9, TextCellValue('${(rate * 100).round()} %'), rate >= 0.9 ? green : (rate < 0.75 ? red : orange));
      put(syn, r, 10, TextCellValue(s.contact));
    }
    r++;
  }

  // ---------- Par jour ----------
  final per = excel['Par jour'];
  r = writeHeader(per, company ? 'Heures par jour' : 'Présences par jour', [
    'Date',
    'Jour',
    'Matricule',
    'Nom',
    'Prénom(s)',
    groupLabel,
    'Statut',
    'Arrivée',
    'Sortie',
    if (company) ...['Heures travaillées', 'Retard', 'Départ anticipé', 'Remarque'] else 'SMS au parent',
  ], [
    12,
    11,
    14,
    18,
    22,
    12,
    18,
    9,
    9,
    if (company) ...[17.0, 10.0, 15.0, 22.0] else 26.0
  ]);
  for (final d in schoolDays) {
    final date = parseDateKey(d.date);
    for (final s in list) {
      final sd = computeDay(s, d, settings, date, now: now);
      final st = switch (sd.status) {
        DayStatus.absent => red,
        DayStatus.late => orange,
        DayStatus.present => green,
        _ => null,
      };
      put(per, r, 0, TextCellValue(frDate(date)));
      put(per, r, 1, TextCellValue(frWeekdays[date.weekday - 1]));
      put(per, r, 2, TextCellValue(s.matricule));
      put(per, r, 3, TextCellValue(s.nom.toUpperCase()));
      put(per, r, 4, TextCellValue(s.prenom));
      put(per, r, 5, TextCellValue(s.classe));
      put(per, r, 6, TextCellValue(dayStatusLabel[sd.status]!), st);
      put(per, r, 7, TextCellValue(sd.arrival == null ? '' : hhmm(sd.arrival!)));
      put(per, r, 8, TextCellValue(sd.departure == null ? '' : hhmm(sd.departure!)));
      if (company) {
        put(per, r, 9, TextCellValue(sd.workedMin > 0 ? hoursLabel(sd.workedMin) : ''));
        put(per, r, 10, TextCellValue(sd.lateMin > 0 ? '${sd.lateMin} min' : ''), sd.lateMin > 0 ? orange : null);
        put(per, r, 11, TextCellValue(sd.earlyMin > 0 ? '${sd.earlyMin} min' : ''), sd.earlyMin > 0 ? orange : null);
        put(per, r, 12, TextCellValue(sd.missingExit ? 'Sortie non pointée' : (sd.sms ?? '')),
            sd.missingExit ? red : null);
      } else {
        put(per, r, 9, TextCellValue(sd.sms ?? ''));
      }
      r++;
    }
  }

  // ---------- Pointages ----------
  final scans = excel['Pointages'];
  r = writeHeader(
      scans,
      'Tous les passages de carte',
      ['Date', 'Heure', 'Passage', 'Matricule', 'Nom', 'Prénom(s)', groupLabel, 'Lecture'],
      [12, 9, 10, 14, 18, 22, 10, 12]);
  final ids = list.map((s) => s.id).toSet();
  for (final d in days) {
    final ev = d.events.where((e) => ids.contains(e.studentId)).toList()..sort((a, b) => a.time.compareTo(b.time));
    for (final e in ev) {
      final s = byId[e.studentId]!;
      put(scans, r, 0, TextCellValue(frDate(e.time)));
      put(scans, r, 1, TextCellValue(hhmm(e.time)));
      put(scans, r, 2, TextCellValue(e.entry ? 'Entrée' : 'Sortie'), e.entry ? green : null);
      put(scans, r, 3, TextCellValue(s.matricule));
      put(scans, r, 4, TextCellValue(s.nom.toUpperCase()));
      put(scans, r, 5, TextCellValue(s.prenom));
      put(scans, r, 6, TextCellValue(s.classe));
      put(scans, r, 7,
          TextCellValue(switch (e.source) { 'douchette' => 'Douchette', 'manuel' => 'Manuel', _ => 'Caméra' }));
      r++;
    }
  }

  excel.setDefaultSheet('Synthèse');
  return Uint8List.fromList(excel.encode()!);
}
