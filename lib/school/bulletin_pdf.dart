import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models.dart';
import 'school_engine.dart';
import 'school_models.dart';

/// Modèles de bulletin proposés à l'impression.
class BulletinModel {
  final String id;
  final String name;
  final String description;
  const BulletinModel(this.id, this.name, this.description);
}

const bulletinModels = <BulletinModel>[
  BulletinModel('officiel', 'Officiel', 'En-tête ministère et pays, tableau Coef / Moyenne / Rang / Appréciation, distinctions'),
  BulletinModel('detaille', 'Détaillé', 'Toutes les notes (devoirs et composition) dans le tableau, pour le post-primaire et le lycée'),
  BulletinModel('primaire', 'Primaire', 'Gros caractères, notes sur 10, observations du maître et signature des parents'),
  BulletinModel('moderne', 'Moderne', 'Bandeau couleur avec logo et photo, graphique élève / classe par matière'),
];

/// Polices du bulletin (Roboto, pour les accents).
class BulletinFonts {
  final pw.Font regular;
  final pw.Font bold;
  final pw.Font medium;
  const BulletinFonts(this.regular, this.bold, this.medium);

  static BulletinFonts? _cache;

  static Future<BulletinFonts> load() async {
    if (_cache != null) return _cache!;
    Future<pw.Font> f(String n) async => pw.Font.ttf(await rootBundle.load('assets/fonts/$n'));
    return _cache = BulletinFonts(await f('Roboto-Regular.ttf'), await f('Roboto-Bold.ttf'), await f('Roboto-Medium.ttf'));
  }

  static BulletinFonts fromBytes(ByteData regular, ByteData bold, ByteData medium) =>
      BulletinFonts(pw.Font.ttf(regular), pw.Font.ttf(bold), pw.Font.ttf(medium));
}

/// Tout ce qu'il faut pour imprimer le bulletin d'un élève.
class BulletinData {
  final StudentResult r;
  final ClassResults c;
  final SchoolSettings st;

  /// Récapitulatif annuel (bulletin de la dernière période), sinon null.
  final List<AnnualResult>? annual;

  const BulletinData(this.r, this.c, this.st, {this.annual});

  AnnualResult? get annualRow {
    for (final a in annual ?? const <AnnualResult>[]) {
      if (a.student.id == r.student.id) return a;
    }
    return null;
  }
}

/// Construit le PDF : un bulletin par page A4.
Future<Uint8List> buildBulletinsPdf({
  required List<BulletinData> items,
  required SchoolInfo school,
  required String model,
  required int primaryColor,
  required int secondaryColor,
  BulletinFonts? fonts,
  bool watermark = false,
}) async {
  final f = fonts ?? await BulletinFonts.load();
  final doc = pw.Document(title: 'Bulletins – ${school.name}', author: school.name);
  final theme = pw.ThemeData.withFont(base: f.regular, bold: f.bold, italic: f.regular, boldItalic: f.bold);
  final ctx = _Ctx(school, PdfColor.fromInt(primaryColor), PdfColor.fromInt(secondaryColor), f);
  for (final b in items) {
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(28, 24, 28, 22),
      theme: theme,
      build: (_) {
        final body = switch (model) {
          'detaille' => _officiel(ctx, b, detailed: true),
          'primaire' => _primaire(ctx, b),
          'moderne' => _moderne(ctx, b),
          _ => _officiel(ctx, b),
        };
        if (!watermark) return body;
        return pw.Stack(children: [
          body,
          pw.Positioned.fill(
            child: pw.Center(
              child: pw.Transform.rotateBox(
                angle: 0.6,
                child: pw.Text('VERSION D\'ESSAI',
                    style: pw.TextStyle(fontSize: 60, color: const PdfColor.fromInt(0x33E31E24), fontWeight: pw.FontWeight.bold)),
              ),
            ),
          ),
        ]);
      },
    ));
  }
  return doc.save();
}

// ---------------------------------------------------------------------------

class _Ctx {
  final SchoolInfo school;
  final PdfColor primary;
  final PdfColor secondary;
  final BulletinFonts fonts;
  _Ctx(this.school, this.primary, this.secondary, this.fonts);

  PdfColor get light => PdfColor(
      primary.red * 0.1 + 0.9, primary.green * 0.1 + 0.9, primary.blue * 0.1 + 0.9);
  PdfColor get ink => const PdfColor.fromInt(0xFF1B1F24);
  PdfColor get grey => const PdfColor.fromInt(0xFF5A6068);
  PdfColor get line => const PdfColor.fromInt(0xFF9AA1A9);

  pw.TextStyle t(double size, {bool bold = false, bool medium = false, PdfColor? color, bool italic = false}) =>
      pw.TextStyle(
        fontSize: size,
        font: bold ? fonts.bold : (medium ? fonts.medium : fonts.regular),
        color: color ?? ink,
        fontStyle: italic ? pw.FontStyle.italic : pw.FontStyle.normal,
      );

  pw.Widget? image(Uint8List? b, double size) =>
      b == null ? null : pw.Image(pw.MemoryImage(b), width: size, height: size, fit: pw.BoxFit.contain);
}

String _periodTitle(Period p) => 'BULLETIN DE NOTES DU ${p.name.toUpperCase()}';

String _scale(ClassConfig c) => c.scale == c.scale.roundToDouble() ? c.scale.toInt().toString() : fmt(c.scale);

pw.Widget _cell(_Ctx c, String text,
        {bool bold = false, pw.TextAlign align = pw.TextAlign.center, double size = 8.5, PdfColor? color, bool italic = false}) =>
    pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 3.6),
      child: pw.Text(text, textAlign: align, style: c.t(size, bold: bold, color: color, italic: italic)),
    );

/// En-tête officiel : ministère et établissement à gauche, pays et devise à droite, logo au centre.
pw.Widget _header(_Ctx c, {bool compact = false}) {
  final s = c.school;
  final left = pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
    if (s.ministry.isNotEmpty) pw.Text(s.ministry.toUpperCase(), textAlign: pw.TextAlign.center, style: c.t(7.5, bold: true)),
    if (s.region.isNotEmpty) pw.Text(s.region, textAlign: pw.TextAlign.center, style: c.t(7)),
    pw.SizedBox(height: 2),
    pw.Text(s.name.toUpperCase(), textAlign: pw.TextAlign.center, style: c.t(9, bold: true, color: c.primary)),
    if (s.address.isNotEmpty || s.phone.isNotEmpty)
      pw.Text([s.address, if (s.phone.isNotEmpty) 'Tél. ${s.phone}'].where((e) => e.isNotEmpty).join(' – '),
          textAlign: pw.TextAlign.center, style: c.t(7)),
  ]);
  final right = pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
    if (s.country.isNotEmpty) pw.Text(s.country.toUpperCase(), style: c.t(9, bold: true)),
    if (s.devise.isNotEmpty) pw.Text(s.devise, style: c.t(7.5, italic: true)),
    pw.SizedBox(height: 4),
    if (s.schoolYear.isNotEmpty) pw.Text('Année scolaire ${s.schoolYear}', style: c.t(8.5, bold: true)),
  ]);
  return pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
    pw.Expanded(flex: 5, child: left),
    pw.Expanded(flex: 2, child: pw.Center(child: c.image(s.logo, compact ? 44 : 56) ?? pw.SizedBox())),
    pw.Expanded(flex: 5, child: right),
  ]);
}

pw.Widget _titleBand(_Ctx c, String text) => pw.Container(
      width: double.infinity,
      margin: const pw.EdgeInsets.symmetric(vertical: 6),
      padding: const pw.EdgeInsets.symmetric(vertical: 5),
      decoration: pw.BoxDecoration(color: c.primary, borderRadius: pw.BorderRadius.circular(3)),
      child: pw.Text(text, textAlign: pw.TextAlign.center, style: c.t(12, bold: true, color: PdfColors.white)),
    );

/// Bloc d'identité de l'élève.
pw.Widget _identity(_Ctx c, BulletinData b, {bool photo = true}) {
  final s = b.r.student;
  final cls = b.c.cls;
  pw.Widget kv(String k, String v) => pw.RichText(
        text: pw.TextSpan(children: [
          pw.TextSpan(text: '$k : ', style: c.t(8.5, color: c.grey)),
          pw.TextSpan(text: v.isEmpty ? '—' : v, style: c.t(9, bold: true)),
        ]),
      );
  final born = [s.dateNaissance, if (s.lieuNaissance.isNotEmpty) 'à ${s.lieuNaissance}'].where((e) => e.isNotEmpty).join(' ');
  return pw.Container(
    padding: const pw.EdgeInsets.all(6),
    decoration: pw.BoxDecoration(border: pw.Border.all(color: c.line, width: 0.6), borderRadius: pw.BorderRadius.circular(3)),
    child: pw.Row(children: [
      pw.Expanded(
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          kv('Nom et prénom(s)', s.fullName),
          pw.SizedBox(height: 3),
          pw.Row(children: [
            pw.Expanded(child: kv('Matricule', s.matricule)),
            pw.Expanded(child: kv('Sexe', s.sexe)),
          ]),
          pw.SizedBox(height: 3),
          kv(isFemale(s) ? 'Née le' : 'Né le', born),
          pw.SizedBox(height: 3),
          pw.Row(children: [
            pw.Expanded(child: kv('Classe', cls.name)),
            pw.Expanded(child: kv('Effectif', '${b.c.effectif}')),
          ]),
          if (cls.titulaire.isNotEmpty) ...[pw.SizedBox(height: 3), kv('Titulaire', cls.titulaire)],
        ]),
      ),
      if (photo && s.photo != null)
        pw.Container(
          width: 52,
          height: 66,
          margin: const pw.EdgeInsets.only(left: 6),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: c.line, width: 0.6)),
          child: pw.Image(pw.MemoryImage(s.photo!), fit: pw.BoxFit.cover),
        ),
    ]),
  );
}

String _penaltyText(BulletinData b) {
  final parts = <String>[];
  for (final s in b.r.subjects) {
    if (s.penalty > 0) parts.add('−${fmt(s.penalty)} pt en ${s.subject.name.toLowerCase()}');
  }
  if (b.r.averagePenalty > 0) parts.add('−${fmt(b.r.averagePenalty)} pt sur la moyenne');
  return parts.isEmpty ? '' : 'Retenue pour absences : ${parts.join(', ')}';
}

pw.Widget _box(_Ctx c, String title, List<pw.Widget> children, {PdfColor? color}) => pw.Container(
      padding: const pw.EdgeInsets.all(6),
      decoration: pw.BoxDecoration(border: pw.Border.all(color: color ?? c.line, width: 0.6), borderRadius: pw.BorderRadius.circular(3)),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text(title.toUpperCase(), style: c.t(7.5, bold: true, color: color ?? c.primary)),
        pw.SizedBox(height: 3),
        ...children,
      ]),
    );

pw.Widget _kvLine(_Ctx c, String k, String v, {bool strong = false}) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.Row(children: [
        pw.Expanded(child: pw.Text(k, style: c.t(8.5, color: c.grey))),
        pw.Text(v, style: c.t(strong ? 10.5 : 9, bold: true, color: strong ? c.primary : c.ink)),
      ]),
    );

/// Cases à cocher des distinctions et sanctions.
pw.Widget _mentions(_Ctx c, BulletinData b) {
  return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
    for (final m in b.st.mentions)
      pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 2),
        child: pw.Row(children: [
          pw.Container(
            width: 8,
            height: 8,
            decoration: pw.BoxDecoration(border: pw.Border.all(color: c.ink, width: 0.6)),
            child: b.r.mention == m.label
                ? pw.Center(child: pw.Text('X', style: c.t(7, bold: true, color: m.positive ? c.primary : PdfColors.red)))
                : null,
          ),
          pw.SizedBox(width: 4),
          pw.Text(m.label, style: c.t(8.5, bold: b.r.mention == m.label)),
        ]),
      ),
  ]);
}

/// Récapitulatif annuel (dernière période).
pw.Widget? _annual(_Ctx c, BulletinData b) {
  final a = b.annualRow;
  if (a == null || b.annual == null) return null;
  final periods = b.st.periods;
  return _box(c, 'Récapitulatif annuel', [
    pw.Table(
      border: pw.TableBorder.all(color: c.line, width: 0.5),
      children: [
        pw.TableRow(decoration: pw.BoxDecoration(color: c.light), children: [
          for (final p in periods) _cell(c, p.name, bold: true, size: 8),
          _cell(c, 'Moyenne annuelle', bold: true, size: 8),
          _cell(c, 'Rang', bold: true, size: 8),
          _cell(c, 'Décision', bold: true, size: 8),
        ]),
        pw.TableRow(children: [
          for (final p in periods) _cell(c, fmt(a.periodAverages[p.id])),
          _cell(c, fmt(a.average), bold: true),
          _cell(c, '${ordinal(a.rank, female: isFemale(a.student), exAequo: a.exAequo)} / ${b.annual!.length}'),
          _cell(c, a.decision, bold: true, size: 8),
        ]),
      ],
    ),
  ]);
}

pw.Widget _signatures(_Ctx c, BulletinData b, {bool parent = true}) {
  final s = c.school;
  pw.Widget sig(String title, {String name = '', pw.Widget? stamp}) => pw.Expanded(
        child: pw.Column(children: [
          pw.Text(title, style: c.t(8.5, bold: true)),
          pw.SizedBox(height: 4),
          pw.SizedBox(height: 46, child: stamp == null ? null : pw.Center(child: stamp)),
          if (name.isNotEmpty) pw.Text(name, style: c.t(8.5, bold: true)),
        ]),
      );
  return pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
    sig(b.c.cls.scale == 10 ? 'Le Maître / La Maîtresse' : 'Le Titulaire', name: b.c.cls.titulaire),
    if (parent) sig('Le Parent'),
    sig(s.directorTitle.isEmpty ? 'Le Directeur' : s.directorTitle,
        name: s.signerName, stamp: s.stamp == null ? null : pw.Opacity(opacity: 0.85, child: c.image(s.stamp, 46)!)),
  ]);
}

// ---------------------------------------------------------------------------
// Modèles « Officiel » et « Détaillé ».

pw.Widget _officiel(_Ctx c, BulletinData b, {bool detailed = false}) {
  final r = b.r;
  final cls = b.c.cls;
  final sc = _scale(cls);
  final evals = b.st.evals;
  final rankCol = b.st.rankPerSubject;
  final headers = <String>[
    'Matières',
    'Coef',
    if (detailed) ...evals.map((e) => e.name),
    'Moy./$sc',
    'Moy. × Coef',
    if (rankCol) 'Rang',
    'Appréciations',
    if (!detailed) 'Professeur',
  ];
  final widths = <int, pw.TableColumnWidth>{};
  var i = 0;
  widths[i++] = const pw.FlexColumnWidth(3.2);
  widths[i++] = const pw.FixedColumnWidth(26);
  if (detailed) {
    for (final _ in evals) {
      widths[i++] = const pw.FixedColumnWidth(36);
    }
  }
  widths[i++] = const pw.FixedColumnWidth(40);
  widths[i++] = const pw.FixedColumnWidth(42);
  if (rankCol) widths[i++] = const pw.FixedColumnWidth(32);
  widths[i++] = const pw.FlexColumnWidth(2.2);
  if (!detailed) widths[i++] = const pw.FlexColumnWidth(1.8);

  final rows = <pw.TableRow>[
    pw.TableRow(
      decoration: pw.BoxDecoration(color: c.primary),
      children: [for (final h in headers) _cell(c, h, bold: true, size: 8, color: PdfColors.white)],
    ),
  ];
  var k = 0;
  for (final s in r.subjects) {
    final max = cls.maxOf(s.subject);
    final on20 = s.average == null ? null : s.average! * 20 / max;
    rows.add(pw.TableRow(
      decoration: pw.BoxDecoration(color: (k++).isOdd ? c.light : null),
      children: [
        _cell(c, s.subject.name, align: pw.TextAlign.left, bold: true),
        _cell(c, fmt(s.subject.coef, digits: s.subject.coef == s.subject.coef.roundToDouble() ? 0 : 1)),
        if (detailed) for (final e in evals) _cell(c, fmt(s.evals[e.id])),
        _cell(c, fmt(s.onScale), bold: true),
        _cell(c, fmt(s.weighted())),
        if (rankCol) _cell(c, ordinal(s.rank, female: isFemale(r.student), exAequo: s.exAequo)),
        _cell(c, [appreciation(on20), if (s.penalty > 0) '(−${fmt(s.penalty)} abs.)'].where((e) => e.isNotEmpty).join(' '),
            align: pw.TextAlign.left, size: 8),
        if (!detailed) _cell(c, s.subject.teacher, align: pw.TextAlign.left, size: 7.5),
      ],
    ));
  }
  rows.add(pw.TableRow(
    decoration: pw.BoxDecoration(color: c.light),
    children: [
      _cell(c, 'TOTAUX', bold: true, align: pw.TextAlign.left),
      _cell(c, fmt(r.coefSum, digits: 0), bold: true),
      if (detailed) for (final _ in evals) _cell(c, ''),
      _cell(c, ''),
      _cell(c, fmt(r.totalPoints), bold: true),
      if (rankCol) _cell(c, ''),
      _cell(c, ''),
      if (!detailed) _cell(c, ''),
    ],
  ));

  final table = pw.Table(border: pw.TableBorder.all(color: c.line, width: 0.5), columnWidths: widths, children: rows);
  final pen = _penaltyText(b);
  final annual = _annual(c, b);
  return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
    _header(c),
    _titleBand(c, _periodTitle(b.c.period)),
    _identity(c, b),
    pw.SizedBox(height: 6),
    table,
    pw.SizedBox(height: 6),
    pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Expanded(
        flex: 5,
        child: _box(c, 'Résultats', [
          _kvLine(c, 'Moyenne générale', '${fmt(r.average)} / $sc', strong: true),
          _kvLine(c, 'Rang', '${ordinal(r.rank, female: isFemale(r.student), exAequo: r.exAequo)} sur ${b.c.ranked}'),
          _kvLine(c, 'Moyenne de la classe', fmt(b.c.classAverage)),
          _kvLine(c, 'Plus forte / plus faible', '${fmt(b.c.best)} / ${fmt(b.c.worst)}'),
        ]),
      ),
      pw.SizedBox(width: 6),
      pw.Expanded(
        flex: 5,
        child: _box(c, 'Assiduité', [
          _kvLine(c, 'Absences justifiées', '${r.absences.justified} ${b.st.absenceUnit}'),
          _kvLine(c, 'Absences non justifiées', '${r.absences.unjustified} ${b.st.absenceUnit}'),
          _kvLine(c, 'Retards', '${r.absences.lates}'),
          if (pen.isNotEmpty) pw.Text(pen, style: c.t(7.5, italic: true, color: PdfColors.red800)),
        ]),
      ),
      pw.SizedBox(width: 6),
      pw.Expanded(flex: 4, child: _box(c, 'Distinctions / sanctions', [_mentions(c, b)])),
    ]),
    pw.SizedBox(height: 6),
    _box(c, 'Appréciation du conseil de classe', [
      pw.SizedBox(
        height: 22,
        child: pw.Text(r.council.isEmpty ? (r.mention ?? '') : r.council, style: c.t(9, italic: true)),
      ),
    ]),
    if (annual != null) ...[pw.SizedBox(height: 6), annual],
    pw.Spacer(),
    _signatures(c, b),
    pw.SizedBox(height: 4),
    pw.Text('Bulletin à conserver soigneusement. Aucun duplicata ne sera délivré.',
        textAlign: pw.TextAlign.center, style: c.t(7, italic: true, color: c.grey)),
  ]);
}

// ---------------------------------------------------------------------------
// Modèle « Primaire » : lisible, notes sur le barème de chaque matière.

pw.Widget _primaire(_Ctx c, BulletinData b) {
  final r = b.r;
  final cls = b.c.cls;
  final sc = _scale(cls);
  final rows = <pw.TableRow>[
    pw.TableRow(decoration: pw.BoxDecoration(color: c.primary), children: [
      _cell(c, 'Matières', bold: true, size: 10, color: PdfColors.white),
      _cell(c, 'Note', bold: true, size: 10, color: PdfColors.white),
      _cell(c, 'Sur', bold: true, size: 10, color: PdfColors.white),
      _cell(c, 'Moy. classe', bold: true, size: 10, color: PdfColors.white),
      _cell(c, 'Observations', bold: true, size: 10, color: PdfColors.white),
    ]),
  ];
  var k = 0;
  for (final s in r.subjects) {
    final max = cls.maxOf(s.subject);
    rows.add(pw.TableRow(decoration: pw.BoxDecoration(color: (k++).isOdd ? c.light : null), children: [
      _cell(c, s.subject.name, align: pw.TextAlign.left, bold: true, size: 10),
      _cell(c, fmt(s.average), bold: true, size: 10.5),
      _cell(c, fmt(max, digits: 0), size: 10),
      _cell(c, fmt(s.classAverage), size: 9.5),
      _cell(c, appreciation(s.average == null ? null : s.average! * 20 / max), align: pw.TextAlign.left, size: 9.5),
    ]));
  }
  final annual = _annual(c, b);
  final pen = _penaltyText(b);
  return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
    _header(c),
    _titleBand(c, 'BULLETIN DE NOTES – ${b.c.period.name.toUpperCase()}'),
    _identity(c, b),
    pw.SizedBox(height: 8),
    pw.Table(
      border: pw.TableBorder.all(color: c.line, width: 0.6),
      columnWidths: const {
        0: pw.FlexColumnWidth(3.2),
        1: pw.FixedColumnWidth(48),
        2: pw.FixedColumnWidth(36),
        3: pw.FixedColumnWidth(58),
        4: pw.FlexColumnWidth(2.2),
      },
      children: rows,
    ),
    pw.SizedBox(height: 10),
    pw.Row(children: [
      _bigStat(c, 'MOYENNE', '${fmt(r.average)} / $sc'),
      pw.SizedBox(width: 8),
      _bigStat(c, 'RANG', '${ordinal(r.rank, female: isFemale(r.student), exAequo: r.exAequo)} / ${b.c.ranked}'),
      pw.SizedBox(width: 8),
      _bigStat(c, 'MOY. CLASSE', fmt(b.c.classAverage)),
      pw.SizedBox(width: 8),
      _bigStat(c, 'ABSENCES', '${r.absences.total}', sub: '${r.absences.unjustified} non justifiée(s)'),
    ]),
    if (pen.isNotEmpty) ...[pw.SizedBox(height: 4), pw.Text(pen, style: c.t(8.5, italic: true, color: PdfColors.red800))],
    pw.SizedBox(height: 8),
    _box(c, 'Observations du maître', [
      pw.SizedBox(
        height: 30,
        child: pw.Text(r.council.isEmpty ? (r.mention ?? appreciation(r.average == null ? null : r.average! * 20 / cls.scale)) : r.council,
            style: c.t(10, italic: true)),
      ),
    ]),
    if (annual != null) ...[pw.SizedBox(height: 8), annual],
    pw.Spacer(),
    _signatures(c, b),
  ]);
}

pw.Widget _bigStat(_Ctx c, String label, String value, {String? sub}) => pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        decoration: pw.BoxDecoration(color: c.light, borderRadius: pw.BorderRadius.circular(4)),
        child: pw.Column(children: [
          pw.Text(label, style: c.t(8, bold: true, color: c.primary)),
          pw.Text(value, style: c.t(14, bold: true)),
          if (sub != null) pw.Text(sub, style: c.t(7.5, color: c.grey)),
        ]),
      ),
    );

// ---------------------------------------------------------------------------
// Modèle « Moderne » : bandeau couleur, cartes et graphique.

pw.Widget _moderne(_Ctx c, BulletinData b) {
  final r = b.r;
  final s = c.school;
  final cls = b.c.cls;
  final sc = _scale(cls);
  final st = r.student;
  final band = pw.Container(
    padding: const pw.EdgeInsets.fromLTRB(12, 10, 12, 10),
    decoration: pw.BoxDecoration(
      gradient: pw.LinearGradient(colors: [c.primary, c.secondary]),
      borderRadius: pw.BorderRadius.circular(6),
    ),
    child: pw.Row(children: [
      if (s.logo != null)
        pw.Container(
          width: 46,
          height: 46,
          padding: const pw.EdgeInsets.all(3),
          decoration: const pw.BoxDecoration(color: PdfColors.white, shape: pw.BoxShape.circle),
          child: pw.Image(pw.MemoryImage(s.logo!), fit: pw.BoxFit.contain),
        ),
      pw.SizedBox(width: 10),
      pw.Expanded(
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(s.name.toUpperCase(), style: c.t(12, bold: true, color: PdfColors.white)),
          pw.Text([s.address, s.phone].where((e) => e.isNotEmpty).join(' · '), style: c.t(8, color: PdfColors.white)),
          pw.SizedBox(height: 4),
          pw.Text('Bulletin du ${b.c.period.name} · ${s.schoolYear}', style: c.t(10, medium: true, color: PdfColors.white)),
        ]),
      ),
      if (st.photo != null)
        pw.Container(
          width: 50,
          height: 62,
          decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.white, width: 1.5), borderRadius: pw.BorderRadius.circular(4)),
          child: pw.ClipRRect(horizontalRadius: 3, verticalRadius: 3, child: pw.Image(pw.MemoryImage(st.photo!), fit: pw.BoxFit.cover)),
        ),
    ]),
  );
  final who = pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 8),
    child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
      pw.Expanded(
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(st.fullName, style: c.t(15, bold: true)),
          pw.Text(
              ['Classe ${cls.name}', if (st.matricule.isNotEmpty) 'Matricule ${st.matricule}', 'Effectif ${b.c.effectif}']
                  .join('  ·  '),
              style: c.t(9, color: c.grey)),
        ]),
      ),
      _pill(c, 'Moyenne', '${fmt(r.average)} / $sc', strong: true),
      pw.SizedBox(width: 6),
      _pill(c, 'Rang', '${ordinal(r.rank, female: isFemale(st), exAequo: r.exAequo)} / ${b.c.ranked}'),
      pw.SizedBox(width: 6),
      _pill(c, 'Classe', fmt(b.c.classAverage)),
    ]),
  );
  final rows = <pw.TableRow>[
    pw.TableRow(
      decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: c.primary, width: 1.2))),
      children: [
        for (final h in ['Matière', 'Coef', 'Moyenne', 'Classe', 'Rang', 'Appréciation'])
          _cell(c, h, bold: true, size: 8.5, color: c.primary, align: h == 'Matière' || h == 'Appréciation' ? pw.TextAlign.left : pw.TextAlign.center),
      ],
    ),
  ];
  var k = 0;
  for (final x in r.subjects) {
    final max = cls.maxOf(x.subject);
    rows.add(pw.TableRow(decoration: pw.BoxDecoration(color: (k++).isOdd ? c.light : null), children: [
      _cell(c, x.subject.name, align: pw.TextAlign.left, bold: true),
      _cell(c, fmt(x.subject.coef, digits: 0)),
      _cell(c, fmt(x.onScale), bold: true),
      _cell(c, x.classAverage == null ? '' : fmt(x.classAverage! * cls.scale / max)),
      _cell(c, ordinal(x.rank, female: isFemale(st), exAequo: x.exAequo)),
      _cell(c, appreciation(x.average == null ? null : x.average! * 20 / max), align: pw.TextAlign.left, size: 8),
    ]));
  }
  final chart = _chart(c, b);
  final pen = _penaltyText(b);
  final annual = _annual(c, b);
  return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
    band,
    who,
    pw.Table(columnWidths: const {
      0: pw.FlexColumnWidth(3),
      1: pw.FixedColumnWidth(30),
      2: pw.FixedColumnWidth(48),
      3: pw.FixedColumnWidth(42),
      4: pw.FixedColumnWidth(34),
      5: pw.FlexColumnWidth(2),
    }, children: rows),
    pw.SizedBox(height: 8),
    pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Expanded(flex: 6, child: _box(c, 'Élève / moyenne de la classe', [chart])),
      pw.SizedBox(width: 8),
      pw.Expanded(
        flex: 4,
        child: pw.Column(children: [
          _box(c, 'Assiduité', [
            _kvLine(c, 'Absences justifiées', '${r.absences.justified}'),
            _kvLine(c, 'Non justifiées', '${r.absences.unjustified}'),
            _kvLine(c, 'Retards', '${r.absences.lates}'),
            if (pen.isNotEmpty) pw.Text(pen, style: c.t(7.5, italic: true, color: PdfColors.red800)),
          ]),
          pw.SizedBox(height: 6),
          _box(c, 'Distinction', [
            pw.Text(r.mention ?? '—', style: c.t(11, bold: true, color: r.mentionPositive ? c.primary : PdfColors.red800)),
          ]),
        ]),
      ),
    ]),
    pw.SizedBox(height: 6),
    _box(c, 'Appréciation du conseil', [
      pw.SizedBox(height: 20, child: pw.Text(r.council.isEmpty ? '' : r.council, style: c.t(9, italic: true))),
    ]),
    if (annual != null) ...[pw.SizedBox(height: 6), annual],
    pw.Spacer(),
    _signatures(c, b),
  ]);
}

pw.Widget _pill(_Ctx c, String label, String value, {bool strong = false}) => pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: pw.BoxDecoration(
        color: strong ? c.primary : c.light,
        borderRadius: pw.BorderRadius.circular(10),
      ),
      child: pw.Column(children: [
        pw.Text(label, style: c.t(7, color: strong ? PdfColors.white : c.grey)),
        pw.Text(value, style: c.t(11, bold: true, color: strong ? PdfColors.white : c.ink)),
      ]),
    );

/// Barres horizontales : moyenne de l'élève et moyenne de la classe par matière.
pw.Widget _chart(_Ctx c, BulletinData b) {
  final cls = b.c.cls;
  const barW = 150.0;
  return pw.Column(children: [
    for (final x in b.r.subjects)
      pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 3),
        child: pw.Row(children: [
          pw.SizedBox(
            width: 82,
            child: pw.Text(x.subject.name, maxLines: 1, overflow: pw.TextOverflow.clip, style: c.t(7.5)),
          ),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Container(
              width: barW * ((x.average ?? 0) / cls.maxOf(x.subject)).clamp(0.0, 1.0),
              height: 5,
              color: c.primary,
            ),
            pw.SizedBox(height: 1),
            pw.Container(
              width: barW * ((x.classAverage ?? 0) / cls.maxOf(x.subject)).clamp(0.0, 1.0),
              height: 3,
              color: c.line,
            ),
          ]),
          pw.SizedBox(width: 4),
          pw.Text(fmt(x.onScale), style: c.t(7.5, bold: true)),
        ]),
      ),
  ]);
}
