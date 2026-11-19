import 'dart:typed_data';

import 'package:carte_scolaire/app_state.dart';
import 'package:carte_scolaire/models.dart';
import 'package:carte_scolaire/services/list_tools.dart';
import 'package:carte_scolaire/services/student_import.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

List<Student> sample() => [
      Student(nom: 'OUÉDRAOGO', prenom: 'Awa', classe: '6A', matricule: '', contact: '')
        ..photo = Uint8List.fromList([1, 2, 3])
        ..photoBg = 0xFF1565C0
        ..validated = true,
      Student(nom: 'KABORÉ', prenom: 'Jean', classe: '6A', matricule: 'M-7'),
      Student(nom: 'SOMÉ', prenom: 'Léa', classe: '6B', contact: '70 11 22 33'),
    ];

void main() {
  test('exporter, modifier dans Excel, réimporter : les fiches et photos ne bougent pas', () {
    final list = sample();
    final ids = list.map((e) => e.id).toList();
    final bytes = exportListExcel(list, template: CardTemplate());

    // Dans Excel : on trie autrement, on corrige un prénom, on ajoute un matricule et une ligne.
    final excel = Excel.decodeBytes(bytes);
    final sheet = excel.tables[excel.getDefaultSheet()]!;
    final head = sheet.rows.first.map((c) => '${c?.value ?? ''}').toList();
    int col(String t) => head.indexOf(t);
    expect(head.first, 'Identifiant (ne pas modifier)');
    sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: col('Prénom(s)'), rowIndex: 1), TextCellValue('Awa Marie'));
    sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: col('Matricule'), rowIndex: 3), TextCellValue('M-9'));
    // Case vidée par erreur : la fiche garde sa valeur.
    sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: col('Personne à prévenir'), rowIndex: 3), TextCellValue(''));
    final n = sheet.maxRows;
    sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: col('Nom'), rowIndex: n), TextCellValue('ZONGO'));
    sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: col('Prénom(s)'), rowIndex: n), TextCellValue('Ali'));
    final edited = Uint8List.fromList(excel.encode()!);

    final res = importStudents(edited, 'liste.xlsx');
    expect(res.students.length, 4);
    expect(res.fields, containsAll(['nom', 'prenom', 'matricule', 'contact', 'classe']));
    final plan = planMerge(list, res.students, res.fields);
    expect(plan.changes.length, 2);
    expect(plan.added.single.nom, 'ZONGO');
    expect(plan.unchanged, 1);

    plan.apply(list);
    expect(list.map((e) => e.id).take(3), ids);
    expect(list[0].prenom, 'Awa Marie');
    expect(list[0].photo, [1, 2, 3]);
    expect(list[0].validated, isTrue);
    expect(list[0].photoBg, 0xFF1565C0);
    expect(list[2].matricule, 'M-9');
    expect(list[2].contact, '70 11 22 33');
    expect(list.last.nom, 'ZONGO');
    expect(ids, isNot(contains(list.last.id)));
  });

  test('fichier sans identifiant : fiches retrouvées par matricule puis par nom', () {
    final list = sample();
    final incoming = [
      Student(matricule: 'M-7', nom: 'KABORÉ', prenom: 'Jean', classe: '5A'),
      Student(nom: 'Ouedraogo', prenom: 'awa', contact: '76 00 00 00'),
      Student(nom: 'SOMÉ', prenom: 'Léa', matricule: 'AUTRE'), // pas de matricule chez nous : même personne
    ];
    final plan = planMerge(list, incoming, {'nom', 'prenom', 'matricule', 'classe', 'contact'});
    expect(plan.added, isEmpty);
    plan.apply(list);
    expect(list[1].classe, '5A');
    expect(list[0].contact, '76 00 00 00');
    expect(list[0].nom, 'Ouedraogo'); // orthographe du fichier
    expect(list[2].matricule, 'AUTRE');
    // Deux fiches du même nom : on ne devine pas, la ligne est ajoutée.
    final twins = [Student(nom: 'DIALLO', prenom: 'Ali'), Student(nom: 'DIALLO', prenom: 'Ali')];
    final p2 = planMerge(twins, [Student(nom: 'DIALLO', prenom: 'Ali', contact: 'x')], {'nom', 'prenom', 'contact'});
    expect(p2.added.length, 1);
  });

  test('matricules automatiques : ordre de la liste, par classe, sans doublon', () {
    final list = [
      Student(nom: 'A', classe: '6e A'),
      Student(nom: 'B', classe: '6e A', matricule: '2026-002'),
      Student(nom: 'C', classe: '6e B'),
      Student(nom: 'D', classe: '6e A'),
    ];
    var plan = planMatricules(list, const MatriculeRule(prefix: '2026'));
    expect(plan.values, ['2026-001', '2026-003', '2026-004']);
    expect(plan.containsKey(list[1]), isFalse);

    plan = planMatricules(list, const MatriculeRule(prefix: 'CSE/', digits: 4, perClass: true), overwrite: true);
    expect([for (final s in list) plan[s]], ['CSE/6EA-0001', 'CSE/6EA-0002', 'CSE/6EB-0001', 'CSE/6EA-0003']);

    // Seulement une classe.
    plan = planMatricules(list, const MatriculeRule(), only: list.where((s) => s.classe == '6e B'));
    expect(plan.keys.single.nom, 'C');
    expect(plan.values.single, '001');
  });

  test('mode automatique : chaque nouvelle fiche reçoit le numéro suivant', () async {
    final app = AppState()..loaded = true;
    app.school
      ..matPrefix = 'MAT-'
      ..matAuto = true;
    app.addStudents([Student(nom: 'A'), Student(nom: 'B', matricule: 'X1')]);
    app.upsertStudent(Student(nom: 'C'));
    expect(app.students.map((e) => e.matricule), ['MAT-001', 'X1', 'MAT-002']);
    final existing = app.students.first;
    app.upsertStudent(existing..matricule = '');
    expect(existing.matricule, '', reason: 'une fiche modifiée n\'est pas renumérotée');
    await Future<void>.delayed(const Duration(seconds: 1));
  });

  test('remplir « personne à prévenir » pour tout le monde', () async {
    final app = AppState()..loaded = true;
    app.students.addAll(sample());
    final empty = planFill(app.students, 'contact', 'Direction 70 00 00 00');
    expect(empty.length, 2);
    final all = planFill(app.students, 'contact', 'Direction 70 00 00 00', onlyEmpty: false);
    expect(all.length, 3);
    app.fillField(empty, 'contact', ' Direction 70 00 00 00 ');
    expect(app.students.map((e) => e.contact), ['Direction 70 00 00 00', 'Direction 70 00 00 00', '70 11 22 33']);
    expect(planFill(app.students, 'contact', 'Direction 70 00 00 00'), isEmpty);
    await Future<void>.delayed(const Duration(seconds: 1));
  });
}
