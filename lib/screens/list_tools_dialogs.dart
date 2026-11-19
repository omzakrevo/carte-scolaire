import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../card_kinds.dart';
import '../models.dart';
import '../services/list_tools.dart';
import '../widgets/common.dart';

/// Enregistre la liste complète en Excel (à modifier puis réimporter avec « Mettre à jour »).
Future<void> exportList(BuildContext context, AppState state) async {
  final kind = kindById(state.template.kind);
  final name = (state.currentProject?.name ?? 'liste').replaceAll(RegExp(r'[^A-Za-z0-9À-ÿ _-]+'), '').trim();
  try {
    final uri = await FilePicker.saveFile(
      dialogTitle: 'Exporter la liste',
      fileName: '${name.isEmpty ? 'liste' : name}.xlsx',
      bytes: exportListExcel(state.students, template: state.template, sheetName: kind.people),
      mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
    if (uri != null && context.mounted) {
      toast(context,
          'Liste exportée (${state.students.length} fiches). Modifiez-la puis réimportez-la avec « Mettre à jour » : '
          'les photos ne bougent pas.');
    }
  } catch (e) {
    if (context.mounted) toast(context, 'Enregistrement impossible : $e', error: true);
  }
}

List<Student> _scope(AppState state, String? onlyClass, bool classOnly) =>
    classOnly && onlyClass != null ? state.students.where((s) => s.classe.trim() == onlyClass).toList() : state.students;

/// Matricules automatiques pour toute la liste (ou une classe).
Future<void> showMatriculeDialog(BuildContext context, AppState state, {String? onlyClass}) async {
  final school = state.school;
  final prefix = TextEditingController(text: school.matPrefix.isEmpty ? '${DateTime.now().year}-' : school.matPrefix);
  var digits = school.matDigits;
  var perClass = school.matPerClass;
  var auto = school.matAuto;
  var overwrite = false;
  var classOnly = onlyClass != null;
  final group = kindById(state.template.kind).group.toLowerCase();

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      final rule = MatriculeRule(prefix: prefix.text, digits: digits, perClass: perClass);
      final list = _scope(state, onlyClass, classOnly);
      final plan = planMatricules(state.students, rule, overwrite: overwrite, only: list);
      final preview = plan.entries.take(3).map((e) => '${e.key.fullName} → ${e.value}').join('\n');
      return AlertDialog(
        title: const Text('Matricules automatiques'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Numéros donnés dans l\'ordre de la liste. Un numéro déjà utilisé n\'est jamais repris.'),
              const SizedBox(height: 12),
              TextField(
                controller: prefix,
                decoration: const InputDecoration(labelText: 'Début du matricule', hintText: '2026-, CSE/, MAT…'),
                onChanged: (_) => set(() {}),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                initialValue: digits,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Chiffres du numéro'),
                items: [for (final d in [2, 3, 4, 5]) DropdownMenuItem(value: d, child: Text('$d (${'0' * (d - 1)}1)'))],
                onChanged: (v) => set(() => digits = v ?? 3),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: perClass,
                title: Text('Numéroter par $group'),
                subtitle: Text('Ex. ${prefix.text}6A-001, puis ${prefix.text}6B-001…'),
                onChanged: (v) => set(() => perClass = v),
              ),
              if (onlyClass != null)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: classOnly,
                  title: Text('Seulement « $onlyClass »'),
                  onChanged: (v) => set(() => classOnly = v),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: overwrite,
                title: const Text('Renuméroter aussi ceux qui ont déjà un matricule'),
                onChanged: (v) => set(() => overwrite = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: auto,
                title: const Text('Nouvelles fiches : matricule automatique'),
                subtitle: const Text('Chaque fiche ajoutée ou importée sans matricule en reçoit un.'),
                onChanged: (v) => set(() => auto = v),
              ),
              const Divider(),
              Text(plan.isEmpty ? 'Aucune fiche à numéroter.' : '${plan.length} fiche(s) recevront un matricule :',
                  style: Theme.of(ctx).textTheme.titleSmall),
              if (preview.isNotEmpty) Text('$preview${plan.length > 3 ? '\n…' : ''}'),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(plan.isEmpty ? 'Enregistrer' : 'Numéroter ${plan.length} fiche(s)'),
          ),
        ],
      );
    }),
  );
  if (ok != true) return;
  school
    ..matPrefix = prefix.text.trim()
    ..matDigits = digits
    ..matPerClass = perClass
    ..matAuto = auto;
  final plan = planMatricules(state.students, MatriculeRule.of(school),
      overwrite: overwrite, only: _scope(state, onlyClass, classOnly));
  state.setMatricules(plan);
  if (context.mounted && plan.isNotEmpty) toast(context, '${plan.length} matricule(s) attribué(s).');
}

/// Même valeur dans un champ pour toute la liste (ex. personne à prévenir, classe, lieu…).
Future<void> showFillDialog(BuildContext context, AppState state, {String? onlyClass, String field = 'contact'}) async {
  final value = TextEditingController();
  var f = field;
  var onlyEmpty = true;
  var classOnly = onlyClass != null;
  const fields = ['contact', 'classe', 'service', 'lieuNaissance', 'adresse', 'email', 'dateNaissance', 'sexe'];

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      final list = planFill(_scope(state, onlyClass, classOnly), f, value.text, onlyEmpty: onlyEmpty);
      return AlertDialog(
        title: const Text('Remplir pour tout le monde'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              initialValue: f,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Champ'),
              items: [
                for (final k in fields) DropdownMenuItem(value: k, child: Text(fieldLabel(k, template: state.template))),
              ],
              onChanged: (v) => set(() => f = v ?? f),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: value,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Valeur pour tous',
                hintText: f == 'contact' ? 'Ex. Direction : 70 00 00 00' : null,
              ),
              onChanged: (_) => set(() {}),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: onlyEmpty,
              title: const Text('Seulement les fiches où ce champ est vide'),
              subtitle: const Text('Sinon, la valeur remplace celle de chaque fiche.'),
              onChanged: (v) => set(() => onlyEmpty = v),
            ),
            if (onlyClass != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: classOnly,
                title: Text('Seulement « $onlyClass »'),
                onChanged: (v) => set(() => classOnly = v),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('${list.length} fiche(s) modifiée(s).', style: Theme.of(ctx).textTheme.titleSmall),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(
            onPressed: value.text.trim().isEmpty || list.isEmpty ? null : () => Navigator.pop(ctx, true),
            child: const Text('Appliquer'),
          ),
        ],
      );
    }),
  );
  if (ok != true) return;
  final list = planFill(_scope(state, onlyClass, classOnly), f, value.text, onlyEmpty: onlyEmpty);
  state.fillField(list, f, value.text);
  if (context.mounted) toast(context, '« ${fieldLabel(f, template: state.template)} » rempli pour ${list.length} fiche(s).');
}
