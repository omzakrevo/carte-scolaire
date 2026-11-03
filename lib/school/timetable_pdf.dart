import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models.dart';
import 'bulletin_pdf.dart';
import 'school_models.dart';
import 'timetable_engine.dart';

const subjectPalette = [
  0xFFFFE0B2, 0xFFC8E6C9, 0xFFBBDEFB, 0xFFF8BBD0, 0xFFD1C4E9, 0xFFFFF59D,
  0xFFB2EBF2, 0xFFFFCCBC, 0xFFDCEDC8, 0xFFE1BEE7, 0xFFCFD8DC, 0xFFF0F4C3,
];

/// Couleur pastel d'une matière : selon sa place dans la classe (toutes différentes),
/// ou selon son nom quand la classe n'est pas connue.
int subjectColor(String name, {int? index}) {
  if (index != null && index >= 0) return subjectPalette[index % subjectPalette.length];
  var h = 7;
  for (final c in name.toLowerCase().codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return subjectPalette[h % subjectPalette.length];
}

/// Une page par classe ([classes]) puis une page par professeur ([teachers]), A4 paysage.
Future<Uint8List> buildTimetablePdf({
  required GradeBook gb,
  required SchoolInfo school,
  List<String> classes = const [],
  List<Teacher> teachers = const [],
  BulletinFonts? fonts,
  int color = 0xFF1B4F8C,
}) async {
  final f = fonts ?? await BulletinFonts.load();
  final doc = pw.Document(title: 'Emplois du temps – ${school.name}');
  final theme = pw.ThemeData.withFont(base: f.regular, bold: f.bold);
  final main = PdfColor.fromInt(color);

  pw.Widget page(String title, String subtitle, pw.Widget Function(String slot) cell) {
    final tt = gb.tt;
    final head = pw.Row(children: [
      if (school.logo != null) pw.Image(pw.MemoryImage(school.logo!), width: 40, height: 40),
      pw.SizedBox(width: 10),
      pw.Expanded(
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(school.name.toUpperCase(), style: pw.TextStyle(font: f.bold, fontSize: 12, color: main)),
          if (school.schoolYear.isNotEmpty) pw.Text('Année scolaire ${school.schoolYear}', style: const pw.TextStyle(fontSize: 9)),
        ]),
      ),
      pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
        pw.Text('EMPLOI DU TEMPS', style: pw.TextStyle(font: f.bold, fontSize: 16)),
        pw.Text(title, style: pw.TextStyle(font: f.bold, fontSize: 13, color: main)),
        if (subtitle.isNotEmpty) pw.Text(subtitle, style: const pw.TextStyle(fontSize: 9)),
      ]),
    ]);
    final rows = <pw.TableRow>[
      pw.TableRow(decoration: pw.BoxDecoration(color: main), children: [
        _c('Horaires', f, bold: true, color: PdfColors.white),
        for (final d in tt.days) _c(weekDays[d - 1], f, bold: true, color: PdfColors.white),
      ]),
    ];
    for (var i = 0; i < tt.slots.length; i++) {
      final s = tt.slots[i];
      if (s.isBreak) {
        rows.add(pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.grey200), children: [
          _c(s.text, f, size: 8),
          for (final _ in tt.days) _c(s.label.isEmpty ? 'Pause' : s.label, f, size: 8, color: PdfColors.grey700),
        ]));
        continue;
      }
      rows.add(pw.TableRow(children: [
        _c(s.text, f, bold: true, size: 9),
        for (final d in tt.days)
          tt.closed.contains('$d|$i')
              ? pw.Container(color: PdfColors.grey300, height: 44)
              : pw.SizedBox(height: 44, child: cell('$d|$i')),
      ]));
    }
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      head,
      pw.SizedBox(height: 10),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey600, width: 0.5),
        columnWidths: {0: const pw.FixedColumnWidth(78)},
        defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
        children: rows,
      ),
    ]);
  }

  for (final name in classes) {
    final cls = gb.classes[name];
    if (cls == null) continue;
    final t = gb.timetable[name] ?? {};
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(22),
      theme: theme,
      build: (_) => page('Classe $name', cls.titulaire.isEmpty ? '' : 'Titulaire : ${cls.titulaire}', (slot) {
        final l = t[slot];
        if (l == null) return pw.SizedBox();
        final s = cls.subjects.where((x) => x.id == l.subjectId).firstOrNull;
        if (s == null) return pw.SizedBox();
        return _lesson(s.name, gb.teacherName(s), f, subjectColor(s.name, index: cls.subjects.indexOf(s)));
      }),
    ));
  }
  for (final tch in teachers) {
    final sched = teacherSchedule(gb, tch.id);
    final hours = sched.length;
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(22),
      theme: theme,
      build: (_) => page(tch.name, '$hours h par semaine', (slot) {
        final e = sched[slot];
        if (e == null) return pw.SizedBox();
        final cls = gb.classes[e.$1];
        return _lesson(e.$2.name, 'Classe ${e.$1}', f, subjectColor(e.$2.name, index: cls?.subjects.indexOf(e.$2)));
      }),
    ));
  }
  return doc.save();
}

pw.Widget _c(String t, BulletinFonts f, {bool bold = false, double size = 9.5, PdfColor? color}) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: pw.Text(t,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(font: bold ? f.bold : f.regular, fontSize: size, color: color ?? PdfColors.black)),
    );

pw.Widget _lesson(String subject, String sub, BulletinFonts f, int color) => pw.Container(
      color: PdfColor.fromInt(color),
      padding: const pw.EdgeInsets.all(2),
      alignment: pw.Alignment.center,
      child: pw.Column(mainAxisAlignment: pw.MainAxisAlignment.center, children: [
        pw.Text(subject, textAlign: pw.TextAlign.center, maxLines: 2, style: pw.TextStyle(font: f.bold, fontSize: 8.5)),
        if (sub.isNotEmpty)
          pw.Text(sub, textAlign: pw.TextAlign.center, maxLines: 1, style: pw.TextStyle(font: f.regular, fontSize: 7)),
      ]),
    );
