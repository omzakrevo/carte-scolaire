import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';

import '../models.dart';

class ImportResult {
  final List<Student> students;
  final List<String> recognizedColumns;
  final List<String> warnings;
  ImportResult(this.students, this.recognizedColumns, this.warnings);
}

/// Importe une liste d'élèves depuis un fichier Excel (.xlsx) ou CSV.
/// Les colonnes sont reconnues d'après leur titre (Nom, Prénom, Classe…).
ImportResult importStudents(Uint8List bytes, String fileName) {
  final lower = fileName.toLowerCase();
  final rows = (lower.endsWith('.csv') || lower.endsWith('.txt')) ? _readCsv(bytes) : _readExcel(bytes);
  return _mapRows(rows);
}

/// Certains logiciels (LibreOffice, Google Sheets, scripts) écrivent des
/// chemins internes absolus (« /xl/worksheets/… ») que la bibliothèque excel
/// ne sait pas suivre : on les rend relatifs avant la lecture.
Uint8List _normalizeXlsx(Uint8List bytes) {
  final zip = ZipDecoder().decodeBytes(bytes);
  var changed = false;
  final out = Archive();
  for (final f in zip.files) {
    if (f.isFile && f.name.endsWith('.rels')) {
      final text = utf8.decode(f.content as List<int>);
      final fixed = text.replaceAll('Target="/xl/', 'Target="');
      if (fixed != text) {
        changed = true;
        final data = utf8.encode(fixed);
        out.addFile(ArchiveFile(f.name, data.length, data));
        continue;
      }
    }
    out.addFile(f);
  }
  if (!changed) return bytes;
  return Uint8List.fromList(ZipEncoder().encode(out)!);
}

List<List<String>> _readExcel(Uint8List bytes) {
  final excel = Excel.decodeBytes(_normalizeXlsx(bytes));
  for (final name in excel.tables.keys) {
    final sheet = excel.tables[name]!;
    final rows = <List<String>>[];
    for (final row in sheet.rows) {
      rows.add(row.map((c) => _cellText(c?.value)).toList());
    }
    if (rows.any((r) => r.any((c) => c.trim().isNotEmpty))) return rows;
  }
  return [];
}

String _two(int n) => n.toString().padLeft(2, '0');

String _cellText(CellValue? v) {
  if (v == null) return '';
  switch (v) {
    case TextCellValue():
      return v.value.text ?? '';
    case IntCellValue():
      return v.value.toString();
    case DoubleCellValue():
      final d = v.value;
      return d == d.roundToDouble() ? d.toInt().toString() : d.toString();
    case DateCellValue():
      return '${_two(v.day)}/${_two(v.month)}/${v.year}';
    case DateTimeCellValue():
      return '${_two(v.day)}/${_two(v.month)}/${v.year}';
    default:
      return v.toString();
  }
}

List<List<String>> _readCsv(Uint8List bytes) {
  var text = utf8.decode(bytes, allowMalformed: true);
  if (text.startsWith('﻿')) text = text.substring(1);
  if (text.contains('�')) text = latin1.decode(bytes);
  final firstLine = text.split('\n').first;
  final sep = [';', '\t', ','].reduce((a, b) => firstLine.split(a).length >= firstLine.split(b).length ? a : b);

  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (quoted) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        cell.write(ch);
      }
    } else if (ch == '"') {
      quoted = true;
    } else if (ch == sep) {
      row.add(cell.toString());
      cell.clear();
    } else if (ch == '\n') {
      row.add(cell.toString().replaceAll('\r', ''));
      cell.clear();
      rows.add(row);
      row = <String>[];
    } else {
      cell.write(ch);
    }
  }
  if (cell.isNotEmpty || row.isNotEmpty) {
    row.add(cell.toString().replaceAll('\r', ''));
    rows.add(row);
  }
  return rows;
}

String _norm(String s) {
  const from = 'àâäáãéèêëíìîïóòôöõúùûüçñ';
  const to = 'aaaaaeeeeiiiiooooouuuucn';
  final b = StringBuffer();
  for (final r in s.toLowerCase().trim().split('')) {
    final i = from.indexOf(r);
    b.write(i >= 0 ? to[i] : r);
  }
  return b.toString().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
}

/// Associe un titre de colonne à un champ de l'élève.
String? _fieldFor(String header) {
  final h = _norm(header);
  if (h.isEmpty) return null;
  bool has(String k) => h.contains(k);
  final nomWord = RegExp(r'(^| )noms?( |$)').hasMatch(h);
  if ((nomWord && has('prenom')) || has('nom complet') || h == 'eleve' || h == 'nom de l eleve') {
    return 'nomComplet';
  }
  if (has('prenom') || has('first')) return 'prenom';
  if (has('lieu')) return 'lieuNaissance';
  if (has('naiss') || has('ne le') || h == 'ne e le' || has('date')) return 'dateNaissance';
  if (has('prevenir') ||
      has('urgence') ||
      has('contact') ||
      has('tel') ||
      has('phone') ||
      has('parent') ||
      has('tuteur')) return 'contact';
  if (has('matricule') || h == 'mat' || h == 'n' || h == 'no' || has('numero') || h == 'id' || h == 'ine') {
    return 'matricule';
  }
  if (nomWord || h == 'name' || has('last')) return 'nom';
  if (has('classe') || has('niveau') || h == 'class') return 'classe';
  if (has('sexe') || has('genre') || h == 'sex') return 'sexe';
  return null;
}

const _labels = {
  'nomComplet': 'Nom et prénom(s)',
  'nom': 'Nom',
  'prenom': 'Prénom(s)',
  'matricule': 'Matricule',
  'classe': 'Classe',
  'dateNaissance': 'Date de naissance',
  'lieuNaissance': 'Lieu de naissance',
  'sexe': 'Sexe',
  'contact': 'Personne à prévenir',
};

ImportResult _mapRows(List<List<String>> rows) {
  final warnings = <String>[];
  // Ligne d'en-tête = première ligne contenant au moins une colonne reconnue.
  var headerIndex = -1;
  Map<int, String> columns = {};
  for (var i = 0; i < rows.length && i < 15; i++) {
    final m = <int, String>{};
    for (var c = 0; c < rows[i].length; c++) {
      final f = _fieldFor(rows[i][c]);
      if (f != null && !m.containsValue(f)) m[c] = f;
    }
    if (m.values.any((f) => f == 'nom' || f == 'nomComplet')) {
      headerIndex = i;
      columns = m;
      break;
    }
  }
  if (headerIndex < 0) {
    // Pas d'en-tête reconnu : colonnes supposées Nom, Prénom, Classe.
    warnings.add('Aucun titre de colonne reconnu : colonnes lues dans l\'ordre Nom, Prénom, Classe.');
    columns = {0: 'nom', 1: 'prenom', 2: 'classe'};
  }

  final students = <Student>[];
  for (var i = headerIndex + 1; i < rows.length; i++) {
    final r = rows[i];
    if (r.every((c) => c.trim().isEmpty)) continue;
    final s = Student();
    columns.forEach((col, field) {
      if (col >= r.length) return;
      final v = r[col].trim();
      switch (field) {
        case 'nomComplet':
          final parts = v.split(RegExp(r'\s+'));
          s.nom = parts.first;
          s.prenom = parts.skip(1).join(' ');
        case 'nom':
          s.nom = v;
        case 'prenom':
          s.prenom = v;
        case 'matricule':
          s.matricule = v;
        case 'classe':
          s.classe = v;
        case 'dateNaissance':
          s.dateNaissance = _fixDate(v);
        case 'lieuNaissance':
          s.lieuNaissance = v;
        case 'sexe':
          s.sexe = v.isEmpty ? '' : v.substring(0, 1).toUpperCase();
        case 'contact':
          s.contact = v;
      }
    });
    if (s.nom.isEmpty && s.prenom.isEmpty) continue;
    students.add(s);
  }
  return ImportResult(
    students,
    columns.values.map((f) => _labels[f] ?? f).toList(),
    warnings,
  );
}

/// Les dates ISO (2015-03-12 ou 2015-03-12T00:00) deviennent 12/03/2015.
String _fixDate(String v) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(v);
  if (m != null) return '${m[3]}/${m[2]}/${m[1]}';
  return v;
}
