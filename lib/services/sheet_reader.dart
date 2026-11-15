import 'dart:convert';
import 'dart:math' as math;

import '../models.dart';
import 'student_import.dart';

/// Lecture d'une feuille de noms photographiée : les mots reconnus (avec leur position)
/// sont remis en lignes et en colonnes, comme un tableau Excel, puis transformés en fiches.

/// Un mot reconnu sur la photo, avec son cadre en pixels.
class OcrWord {
  final String text;
  final double left, top, width, height;
  const OcrWord(this.text, this.left, this.top, this.width, this.height);

  double get right => left + width;
  double get bottom => top + height;
  double get cy => top + height / 2;

  factory OcrWord.fromJson(Map j) => OcrWord(
        '${j['t'] ?? j['text'] ?? ''}',
        (j['x'] as num? ?? 0).toDouble(),
        (j['y'] as num? ?? 0).toDouble(),
        (j['w'] as num? ?? 0).toDouble(),
        (j['h'] as num? ?? 0).toDouble(),
      );
}

double _median(List<double> v) {
  if (v.isEmpty) return 0;
  final s = [...v]..sort();
  return s[s.length ~/ 2];
}

/// Morceau de texte d'une ligne (mots proches les uns des autres).
class _Cell {
  final List<OcrWord> words;
  _Cell(this.words);
  double get left => words.first.left;
  double get right => words.map((w) => w.right).reduce(math.max);
  String get text => words.map((w) => w.text).join(' ');
}

/// Regroupe les mots en lignes (même hauteur) puis en colonnes (mêmes positions horizontales).
List<List<String>> wordsToTable(List<OcrWord> input) {
  final words = input.where((w) => w.text.trim().isNotEmpty && w.height > 0).toList();
  if (words.isEmpty) return [];
  final h = _median(words.map((w) => w.height).toList());

  // 1. Lignes : un mot rejoint la ligne dont le centre vertical est assez proche.
  words.sort((a, b) => a.cy.compareTo(b.cy));
  final lines = <List<OcrWord>>[];
  final centers = <double>[];
  for (final w in words) {
    var best = -1;
    var dist = double.infinity;
    for (var i = math.max(0, lines.length - 3); i < lines.length; i++) {
      final d = (w.cy - centers[i]).abs();
      if (d < dist) {
        dist = d;
        best = i;
      }
    }
    if (best >= 0 && dist < h * 0.6) {
      lines[best].add(w);
      centers[best] = lines[best].map((e) => e.cy).reduce((a, b) => a + b) / lines[best].length;
    } else {
      lines.add([w]);
      centers.add(w.cy);
    }
  }

  // 2. Cellules : dans une ligne, un grand espace sépare deux colonnes.
  final rows = <List<_Cell>>[];
  for (final l in lines) {
    l.sort((a, b) => a.left.compareTo(b.left));
    final cells = <_Cell>[];
    for (final w in l) {
      if (cells.isNotEmpty && w.left - cells.last.right < h * 1.1) {
        cells.last.words.add(w);
      } else {
        cells.add(_Cell([w]));
      }
    }
    rows.add(cells);
  }

  // 3. Colonnes : bandes horizontales occupées par les cellules des lignes à plusieurs cellules.
  final multi = rows.where((r) => r.length >= 2).toList();
  final source = multi.length >= math.max(2, rows.length ~/ 3) ? multi : rows;
  final spans = [for (final r in source) for (final c in r) (c.left, c.right)]..sort((a, b) => a.$1.compareTo(b.$1));
  final bands = <(double, double)>[];
  for (final s in spans) {
    if (bands.isNotEmpty && s.$1 <= bands.last.$2 + h * 0.3) {
      bands[bands.length - 1] = (bands.last.$1, math.max(bands.last.$2, s.$2));
    } else {
      bands.add(s);
    }
  }
  if (bands.isEmpty) return [];

  int bandOf(_Cell c) {
    var best = 0;
    var score = -double.infinity;
    for (var i = 0; i < bands.length; i++) {
      final overlap = math.min(c.right, bands[i].$2) - math.max(c.left, bands[i].$1);
      final s = overlap > 0 ? overlap : -math.max(bands[i].$1 - c.right, c.left - bands[i].$2);
      if (s > score) {
        score = s;
        best = i;
      }
    }
    return best;
  }

  final table = <List<String>>[];
  for (final r in rows) {
    final out = List<String>.filled(bands.length, '');
    for (final c in r) {
      final b = bandOf(c);
      out[b] = out[b].isEmpty ? c.text : '${out[b]} ${c.text}';
    }
    table.add(out);
  }
  return cleanTable(table);
}

/// Retire les colonnes vides et les lignes vides, nettoie les points de conduite (……).
List<List<String>> cleanTable(List<List<String>> rows) {
  final cleaned = [
    for (final r in rows)
      [for (final c in r) c.replaceAll(RegExp(r'[.…_]{3,}'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim()]
  ].where((r) => r.any((c) => c.isNotEmpty)).toList();
  if (cleaned.isEmpty) return cleaned;
  final width = cleaned.map((r) => r.length).reduce(math.max);
  final keep = [
    for (var c = 0; c < width; c++)
      if (cleaned.any((r) => c < r.length && r[c].isNotEmpty)) c
  ];
  return [
    for (final r in cleaned) [for (final c in keep) c < r.length ? r[c] : '']
  ];
}

/// Une liste « tapée » ou recopiée ligne par ligne (une personne par ligne, colonnes
/// séparées par des tabulations, des points-virgules ou plusieurs espaces).
List<List<String>> textToTable(String text) {
  final lines = const LineSplitter().convert(text).where((l) => l.trim().isNotEmpty).toList();
  final sep = lines.any((l) => l.contains('\t'))
      ? RegExp(r'\t')
      : lines.where((l) => l.contains(';')).length > lines.length / 2
          ? RegExp(r';')
          : RegExp(r' {2,}|\s+\|\s+');
  return cleanTable([for (final l in lines) l.split(sep).map((e) => e.trim()).toList()]);
}

// ---------------------------------------------------------------------------
// Colonnes : titres reconnus ou contenu deviné.

/// Champs proposés pour chaque colonne ('' = ignorer la colonne).
const sheetFields = <String>[
  '',
  'nomComplet',
  'nom',
  'prenom',
  'classe',
  'matricule',
  'dateNaissance',
  'lieuNaissance',
  'sexe',
  'contact',
  'service',
  'email',
  'adresse',
];

String sheetFieldLabel(String f) => f.isEmpty ? 'Ignorer' : (studentFieldLabels[f] ?? f);

class SheetGuess {
  /// Ligne des titres (null s'il n'y en a pas).
  final int? headerRow;
  final List<String> fields;
  const SheetGuess(this.headerRow, this.fields);
}

final _date = RegExp(r'^\d{1,2}[/.\-]\d{1,2}[/.\-]\d{2,4}$|^\d{4}-\d{2}-\d{2}$');
final _phone = RegExp(r'^[+(]?\d[\d\s().-]{6,}$');
final _sex = RegExp(r'^(m|f|g|masculin|féminin|feminin|garçon|fille|h)$', caseSensitive: false);
final _number = RegExp(r'^\d{1,3}[.)°]?$');
final _classe = RegExp(
    r'^(cp|ce|cm|6|5|4|3|2|1|t|tle|term|seconde|première|premiere|terminale)[a-z0-9 èéme°]{0,6}$',
    caseSensitive: false);
final _matricule = RegExp(r'^(?=.*\d)[A-Z0-9/\-]{4,}$');

String _guessByContent(List<String> values) {
  final v = values.where((e) => e.trim().isNotEmpty).toList();
  if (v.isEmpty) return '';
  double share(RegExp r) => v.where((e) => r.hasMatch(e.trim())).length / v.length;
  if (share(_number) > 0.7) return ''; // numéro d'ordre
  if (share(_date) > 0.6) return 'dateNaissance';
  if (share(_sex) > 0.7) return 'sexe';
  if (share(_phone) > 0.6) return 'contact';
  if (share(_matricule) > 0.6) return 'matricule';
  if (share(_classe) > 0.6) return 'classe';
  final words = v.map((e) => e.trim().split(RegExp(r'\s+')).length).reduce((a, b) => a + b) / v.length;
  return words >= 1.8 ? 'nomComplet' : 'nom';
}

/// Devine la ligne de titres et le champ de chaque colonne.
SheetGuess guessColumns(List<List<String>> rows) {
  if (rows.isEmpty) return const SheetGuess(null, []);
  final width = rows.map((r) => r.length).reduce(math.max);
  for (var i = 0; i < rows.length && i < 8; i++) {
    final fields = List<String>.filled(width, '');
    var found = 0;
    for (var c = 0; c < rows[i].length; c++) {
      final f = studentFieldFor(rows[i][c]);
      if (f != null && !fields.contains(f)) {
        fields[c] = f;
        found++;
      }
    }
    if (fields.contains('nom') || fields.contains('nomComplet') || found >= 2) {
      // « N° » : simple numéro d'ordre, pas un matricule.
      for (var c = 0; c < width; c++) {
        if (fields[c] == 'matricule' &&
            _guessByContent([for (final r in rows.skip(i + 1)) c < r.length ? r[c] : '']).isEmpty) {
          fields[c] = '';
        }
      }
      // Colonnes sans titre reconnu : d'après leur contenu.
      for (var c = 0; c < width; c++) {
        if (fields[c].isNotEmpty) continue;
        final g = _guessByContent([for (final r in rows.skip(i + 1)) c < r.length ? r[c] : '']);
        if (g.isNotEmpty && !fields.contains(g)) fields[c] = g;
      }
      return SheetGuess(i, fields);
    }
  }
  // Pas de titres : tout se devine d'après le contenu.
  final fields = <String>[];
  for (var c = 0; c < width; c++) {
    var g = _guessByContent([for (final r in rows) c < r.length ? r[c] : '']);
    if (g == 'nom' && fields.contains('nom')) g = 'prenom';
    if ((g == 'nom' || g == 'nomComplet') && fields.contains('nomComplet')) g = 'prenom';
    if (g.isNotEmpty && g != 'prenom' && fields.contains(g)) g = '';
    if (g == 'prenom' && fields.contains('prenom')) g = '';
    fields.add(g);
  }
  return SheetGuess(null, fields);
}

/// Transforme le tableau relu en fiches (la ligne de titres est sautée).
List<Student> buildStudents(List<List<String>> rows, List<String> fields,
    {int? headerRow, Set<int> skip = const {}, String defaultClass = ''}) {
  final out = <Student>[];
  for (var i = 0; i < rows.length; i++) {
    // Les lignes au-dessus des titres sont l'en-tête de la feuille (nom de la classe…).
    if ((headerRow != null && i <= headerRow) || skip.contains(i)) continue;
    final r = rows[i];
    final s = Student();
    for (var c = 0; c < fields.length && c < r.length; c++) {
      if (fields[c].isNotEmpty && r[c].trim().isNotEmpty) applyStudentField(s, fields[c], r[c]);
    }
    if (s.nom.isEmpty && s.prenom.isEmpty && s.matricule.isEmpty) continue;
    if (s.classe.isEmpty) s.classe = defaultClass;
    out.add(s);
  }
  return out;
}

// ---------------------------------------------------------------------------
// Lecture IA : la réponse du modèle est un tableau JSON.

const aiSheetPrompt = '''Cette photo montre une liste de personnes (élèves, employés ou membres), imprimée ou écrite à la main.
Recopie-la fidèlement sous forme de tableau, ligne par ligne, dans l'ordre de la feuille.
- Garde exactement l'orthographe des noms (accents, majuscules). N'invente rien : une case illisible reste vide "".
- La première ligne du tableau contient les titres des colonnes (ceux de la feuille, ou à défaut : Nom, Prénom(s), Classe, Date de naissance, Lieu de naissance, Sexe, Matricule, Contact).
- Si les noms et prénoms sont dans la même colonne, garde-les ensemble dans une colonne « Nom et prénom(s) ».
Réponds uniquement avec du JSON, sans texte autour : {"rows": [["titre1","titre2"], ["valeur","valeur"]]}''';

/// Extrait le tableau de la réponse du modèle (JSON éventuellement entouré de texte).
List<List<String>> parseAiTable(String reply) {
  var t = reply.trim();
  final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(t);
  if (fence != null) t = fence.group(1)!.trim();
  final start = t.indexOf(RegExp(r'[\[{]'));
  final end = math.max(t.lastIndexOf('}'), t.lastIndexOf(']'));
  if (start < 0 || end <= start) throw const FormatException('Réponse sans tableau');
  final j = jsonDecode(t.substring(start, end + 1));
  final raw = j is Map ? (j['rows'] ?? j['table'] ?? j.values.firstWhere((e) => e is List, orElse: () => [])) : j;
  if (raw is! List) throw const FormatException('Réponse sans tableau');
  final rows = <List<String>>[];
  for (final r in raw) {
    if (r is List) {
      rows.add([for (final c in r) c == null ? '' : '$c']);
    } else if (r is Map) {
      if (rows.isEmpty) rows.add([for (final k in r.keys) '$k']);
      rows.add([for (final v in r.values) v == null ? '' : '$v']);
    }
  }
  return cleanTable(rows);
}
