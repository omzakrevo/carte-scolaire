import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../models.dart';
import 'student_import.dart';

/// Outils sur toute la liste : export Excel, mise à jour depuis un fichier modifié,
/// matricules automatiques, remplissage d'un champ pour tout le monde.

// ---------------------------------------------------------------------------
// Champs d'une fiche

/// Champs modifiables d'une fiche, dans l'ordre des colonnes de l'export.
const listFields = <String>[
  'matricule',
  'nom',
  'prenom',
  'classe',
  'service',
  'dateNaissance',
  'lieuNaissance',
  'sexe',
  'contact',
  'email',
  'adresse',
];

String fieldValue(Student s, String f) => switch (f) {
      'matricule' => s.matricule,
      'nom' => s.nom,
      'prenom' => s.prenom,
      'classe' => s.classe,
      'service' => s.service,
      'dateNaissance' => s.dateNaissance,
      'lieuNaissance' => s.lieuNaissance,
      'sexe' => s.sexe,
      'contact' => s.contact,
      'email' => s.email,
      'adresse' => s.adresse,
      _ => '',
    };

void setFieldValue(Student s, String f, String v) {
  switch (f) {
    case 'matricule':
      s.matricule = v;
    case 'nom':
      s.nom = v;
    case 'prenom':
      s.prenom = v;
    case 'classe':
      s.classe = v;
    case 'service':
      s.service = v;
    case 'dateNaissance':
      s.dateNaissance = v;
    case 'lieuNaissance':
      s.lieuNaissance = v;
    case 'sexe':
      s.sexe = v;
    case 'contact':
      s.contact = v;
    case 'email':
      s.email = v;
    case 'adresse':
      s.adresse = v;
  }
}

/// Libellé d'un champ (celui du modèle de carte s'il a été renommé).
String fieldLabel(String f, {CardTemplate? template}) {
  if (f == 'nom') return 'Nom';
  if (f == 'prenom') return 'Prénom(s)';
  return template?.label(f) ?? defaultLabels[f] ?? studentFieldLabels[f] ?? f;
}

// ---------------------------------------------------------------------------
// Export

/// Liste complète en Excel, dans l'ordre de l'application. La colonne « Identifiant »
/// permet de retrouver chaque fiche au réimport : photos et cartes ne sont pas touchées.
Uint8List exportListExcel(List<Student> students, {CardTemplate? template, String sheetName = 'Liste'}) {
  // Colonnes : celles du modèle de carte, plus celles qui contiennent des données.
  final keys = [
    for (final f in listFields)
      if (f == 'nom' ||
          f == 'prenom' ||
          f == 'matricule' ||
          (template?.shows(f) ?? true) ||
          students.any((s) => fieldValue(s, f).trim().isNotEmpty))
        f,
  ];
  final excel = Excel.createExcel();
  final first = excel.getDefaultSheet()!;
  excel.rename(first, sheetName);
  final sheet = excel[sheetName];
  final head = CellStyle(
    bold: true,
    fontColorHex: ExcelColor.fromHexString('#FFFFFFFF'),
    backgroundColorHex: ExcelColor.fromHexString('#FF1B2A6B'),
    horizontalAlign: HorizontalAlign.Center,
  );
  final grey = CellStyle(fontColorHex: ExcelColor.fromHexString('#FF8A8F98'));
  // Titres standard (reconnus au réimport), même si le modèle de carte les a renommés.
  final headers = ['Identifiant (ne pas modifier)', for (final k in keys) fieldLabel(k)];
  for (var i = 0; i < headers.length; i++) {
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
      ..value = TextCellValue(headers[i])
      ..cellStyle = head;
    sheet.setColumnWidth(i, i == 0 ? 24 : (keys[i - 1] == 'prenom' || keys[i - 1] == 'adresse' ? 24 : 18));
  }
  for (var r = 0; r < students.length; r++) {
    final s = students[r];
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r + 1))
      ..value = TextCellValue(s.id)
      ..cellStyle = grey;
    for (var c = 0; c < keys.length; c++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: c + 1, rowIndex: r + 1)).value =
          TextCellValue(fieldValue(s, keys[c]));
    }
  }
  excel.setDefaultSheet(sheetName);
  return Uint8List.fromList(excel.encode()!);
}

// ---------------------------------------------------------------------------
// Mise à jour depuis un fichier

String _key(String v) => v
    .toLowerCase()
    .replaceAll(RegExp('[àâä]'), 'a')
    .replaceAll(RegExp('[éèêë]'), 'e')
    .replaceAll(RegExp('[îï]'), 'i')
    .replaceAll(RegExp('[ôö]'), 'o')
    .replaceAll(RegExp('[ùûü]'), 'u')
    .replaceAll('ç', 'c')
    .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
    .trim();

class MergeChange {
  final Student target;
  final Map<String, String> values;
  const MergeChange(this.target, this.values);
}

/// Ce que l'import va faire, à montrer avant d'appliquer.
class MergePlan {
  final List<MergeChange> changes;
  final List<Student> added;
  final int unchanged;
  MergePlan(this.changes, this.added, this.unchanged);

  int get changedFields => changes.fold(0, (n, c) => n + c.values.length);

  /// Modifie les fiches existantes (photos, fond, validation et ordre conservés) et ajoute les nouvelles à la fin.
  void apply(List<Student> students) {
    for (final c in changes) {
      c.values.forEach((f, v) => setFieldValue(c.target, f, v));
    }
    students.addAll(added);
  }
}

/// Retrouve chaque ligne du fichier dans la liste : par identifiant, puis matricule,
/// puis nom et prénom (s'il n'y a qu'une seule fiche de ce nom). Une case vide du fichier
/// ne vide jamais la fiche ; rien n'est supprimé.
MergePlan planMerge(List<Student> existing, List<Student> incoming, Set<String> fields) {
  final byId = {for (final s in existing) s.id: s};
  final byMat = <String, List<Student>>{};
  final byName = <String, List<Student>>{};
  for (final s in existing) {
    if (s.matricule.trim().isNotEmpty) byMat.putIfAbsent(_key(s.matricule), () => []).add(s);
    byName.putIfAbsent(_key('${s.nom} ${s.prenom}'), () => []).add(s);
  }
  final used = <String>{};
  final changes = <MergeChange>[];
  final added = <Student>[];
  var unchanged = 0;
  final editable = fields.where(listFields.contains).toList();

  Student? one(List<Student>? l) {
    final free = (l ?? const <Student>[]).where((s) => !used.contains(s.id)).toList();
    return free.length == 1 ? free.first : null;
  }

  for (final inc in incoming) {
    var target = byId[inc.id];
    if (target != null && used.contains(target.id)) target = null;
    if (target == null && inc.matricule.trim().isNotEmpty) target = one(byMat[_key(inc.matricule)]);
    if (target == null && '${inc.nom}${inc.prenom}'.trim().isNotEmpty) {
      final m = one(byName[_key('${inc.nom} ${inc.prenom}')]);
      // Même nom : on vérifie que le matricule ne dit pas le contraire.
      if (m != null && (inc.matricule.trim().isEmpty || m.matricule.trim().isEmpty)) target = m;
    }
    if (target == null) {
      if (byId.containsKey(inc.id) || inc.id.isEmpty) inc.id = Student.newId();
      added.add(inc);
      continue;
    }
    used.add(target.id);
    final diff = <String, String>{};
    for (final f in editable) {
      final v = fieldValue(inc, f).trim();
      if (v.isNotEmpty && v != fieldValue(target, f).trim()) diff[f] = v;
    }
    if (diff.isEmpty) {
      unchanged++;
    } else {
      changes.add(MergeChange(target, diff));
    }
  }
  return MergePlan(changes, added, unchanged);
}

// ---------------------------------------------------------------------------
// Matricules automatiques

class MatriculeRule {
  final String prefix;
  final int digits;
  final bool perClass;
  const MatriculeRule({this.prefix = '', this.digits = 3, this.perClass = false});

  factory MatriculeRule.of(SchoolInfo s) =>
      MatriculeRule(prefix: s.matPrefix, digits: s.matDigits.clamp(1, 8), perClass: s.matPerClass);

  String _classPart(String classe) =>
      classe.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9ÀÂÉÈÊÎÔÛÇ]+'), '');

  /// Début du matricule (sans le numéro) pour une fiche.
  String stem(Student s) {
    final c = perClass ? _classPart(s.classe) : '';
    var st = prefix.trim();
    if (st.isNotEmpty && !RegExp(r'[-/_.]$').hasMatch(st)) st += '-';
    if (c.isNotEmpty) st += '$c-';
    return st;
  }

  String format(Student s, int n) => '${stem(s)}${n.toString().padLeft(digits, '0')}';

  /// Numéro déjà utilisé par un matricule de cette forme (sinon null).
  int? numberOf(Student s, String matricule) {
    final st = stem(s);
    if (!matricule.startsWith(st)) return null;
    return int.tryParse(matricule.substring(st.length));
  }
}

/// Matricules à donner, dans l'ordre de la liste. Les numéros déjà pris ne sont jamais
/// réutilisés. [overwrite] : renuméroter aussi les fiches qui ont déjà un matricule.
Map<Student, String> planMatricules(List<Student> students, MatriculeRule rule,
    {bool overwrite = false, int start = 1, Iterable<Student>? only}) {
  final target = (only ?? students).toList();
  final targetSet = target.toSet();
  final taken = <String>{
    for (final s in students)
      if (!(overwrite && targetSet.contains(s)) && s.matricule.trim().isNotEmpty) s.matricule.trim(),
  };
  final next = <String, int>{};
  final out = <Student, String>{};
  for (final s in target) {
    if (!overwrite && s.matricule.trim().isNotEmpty) continue;
    final st = rule.stem(s);
    var n = next[st] ?? start;
    var m = rule.format(s, n);
    while (taken.contains(m)) {
      n++;
      m = rule.format(s, n);
    }
    taken.add(m);
    next[st] = n + 1;
    out[s] = m;
  }
  return out;
}

/// Matricule de la prochaine fiche ajoutée (mode automatique).
String nextMatricule(List<Student> students, Student s, MatriculeRule rule) =>
    planMatricules([...students.where((e) => e != s), s], rule, only: [s])[s] ?? s.matricule;

// ---------------------------------------------------------------------------
// Remplir un champ pour tout le monde

/// Fiches modifiées si l'on met [value] dans [field] ([onlyEmpty] : seulement les cases vides).
List<Student> planFill(Iterable<Student> students, String field, String value, {bool onlyEmpty = true}) => [
      for (final s in students)
        if (fieldValue(s, field).trim() != value.trim() && (!onlyEmpty || fieldValue(s, field).trim().isEmpty)) s,
    ];
