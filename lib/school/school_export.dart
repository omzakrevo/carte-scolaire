import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../models.dart';
import 'school_engine.dart';
import 'school_models.dart';

/// Procès-verbal de la classe : moyennes par matière, moyenne générale, rang, absences, mention.
Uint8List buildResultsExcel(ClassResults res, SchoolInfo school, SchoolSettings st, {bool trial = false}) {
  final excel = Excel.createExcel();
  final name = excel.getDefaultSheet()!;
  excel.rename(name, 'Résultats');
  final sh = excel['Résultats'];
  final head = CellStyle(
    bold: true,
    fontColorHex: ExcelColor.fromHexString('#FFFFFFFF'),
    backgroundColorHex: ExcelColor.fromHexString('#FF1B4F8C'),
    horizontalAlign: HorizontalAlign.Center,
    textWrapping: TextWrapping.WrapText,
  );
  final bold = CellStyle(bold: true);
  void put(int r, int c, CellValue v, [CellStyle? s]) {
    final cell = sh.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r));
    cell.value = v;
    if (s != null) cell.cellStyle = s;
  }

  var r = 0;
  if (trial) put(r++, 0, TextCellValue('VERSION D\'ESSAI – document non valable'), bold);
  put(r++, 0, TextCellValue('${school.name} – Année scolaire ${school.schoolYear}'), CellStyle(bold: true, fontSize: 14));
  put(r++, 0, TextCellValue('Classe ${res.cls.name} – ${res.period.name} – barème sur ${fmt(res.cls.scale, digits: 0)}'));
  put(r++, 0,
      TextCellValue('Moyenne de la classe : ${fmt(res.classAverage)}  ·  Plus forte : ${fmt(res.best)}  ·  Plus faible : ${fmt(res.worst)}  ·  '
          'Moyenne ≥ ${fmt(res.cls.scale / 2, digits: 0)} : ${res.passing}/${res.ranked}'));
  r++;
  final cols = <String>[
    'Rang',
    'Matricule',
    'Nom et prénom(s)',
    for (final m in res.cls.subjects) '${m.name} (coef ${fmt(m.coef, digits: 0)})',
    'Total points',
    'Moyenne',
    'Abs. justifiées',
    'Abs. non justifiées',
    'Retards',
    'Mention',
    'Appréciation du conseil',
  ];
  for (var c = 0; c < cols.length; c++) {
    put(r, c, TextCellValue(cols[c]), head);
    sh.setColumnWidth(c, c == 2 ? 28 : (c == cols.length - 1 ? 34 : (c < 3 ? 12 : 14)));
  }
  r++;
  final rows = [...res.rows]..sort((a, b) => (a.rank == 0 || a.rank == null ? 9999 : a.rank!)
      .compareTo(b.rank == 0 || b.rank == null ? 9999 : b.rank!));
  for (final x in rows) {
    var c = 0;
    put(r, c++, TextCellValue(ordinal(x.rank, female: isFemale(x.student), exAequo: x.exAequo)));
    put(r, c++, TextCellValue(x.student.matricule));
    put(r, c++, TextCellValue(x.student.fullName), bold);
    for (final s in x.subjects) {
      put(r, c++, s.onScale == null ? TextCellValue('') : DoubleCellValue(round2(s.onScale!)));
    }
    put(r, c++, DoubleCellValue(round2(x.totalPoints)));
    put(r, c++, x.average == null ? TextCellValue('') : DoubleCellValue(round2(x.average!)), bold);
    put(r, c++, IntCellValue(x.absences.justified));
    put(r, c++, IntCellValue(x.absences.unjustified));
    put(r, c++, IntCellValue(x.absences.lates));
    put(r, c++, TextCellValue(x.mention ?? ''));
    put(r, c++, TextCellValue(x.council));
    r++;
  }
  // Moyennes de la classe par matière.
  var c = 3;
  put(r, 2, TextCellValue('Moyenne de la classe'), bold);
  for (final m in res.cls.subjects) {
    final i = res.cls.subjects.indexOf(m);
    final ca = res.rows.isEmpty ? null : res.rows.first.subjects[i].classAverage;
    put(r, c++, ca == null ? TextCellValue('') : DoubleCellValue(round2(ca * res.cls.scale / res.cls.maxOf(m))), bold);
  }
  excel.setDefaultSheet('Résultats');
  return Uint8List.fromList(excel.encode()!);
}
