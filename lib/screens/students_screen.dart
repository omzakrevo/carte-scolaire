import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../services/student_import.dart';
import '../widgets/common.dart';

class StudentsScreen extends StatefulWidget {
  final VoidCallback onNext;
  const StudentsScreen({super.key, required this.onNext});

  @override
  State<StudentsScreen> createState() => _StudentsScreenState();
}

class _StudentsScreenState extends State<StudentsScreen> {
  String _query = '';
  String? _class;
  bool _busy = false;

  Future<void> _import() async {
    final state = AppScope.read(context);
    (String, Uint8List)? r;
    try {
      r = await pickOneFile(type: FileType.custom, extensions: const ['xlsx', 'csv']);
    } catch (e) {
      if (mounted) toast(context, 'Impossible d\'ouvrir le sélecteur de fichiers : $e', error: true);
      return;
    }
    if (r == null) return;
    final (name, bytes) = r;
    setState(() => _busy = true);
    try {
      final res = importStudents(bytes, name);
      if (!mounted) return;
      if (res.students.isEmpty) {
        toast(context, 'Aucun élève trouvé dans « $name ». Vérifiez qu\'il y a une colonne Nom.', error: true);
        return;
      }
      var replace = false;
      if (state.students.isNotEmpty) {
        final choice = await showDialog<String>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text('${res.students.length} élèves trouvés'),
            content: Text(
                'La liste contient déjà ${state.students.length} élèves. Voulez-vous ajouter les nouveaux à la suite ou remplacer la liste ?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
              OutlinedButton(onPressed: () => Navigator.pop(c, 'replace'), child: const Text('Remplacer')),
              FilledButton(onPressed: () => Navigator.pop(c, 'add'), child: const Text('Ajouter')),
            ],
          ),
        );
        if (choice == null) return;
        replace = choice == 'replace';
      }
      state.addStudents(res.students, replace: replace);
      if (!mounted) return;
      toast(context,
          '${res.students.length} élèves importés. Colonnes reconnues : ${res.recognizedColumns.join(', ')}.${res.warnings.isEmpty ? '' : ' ${res.warnings.join(' ')}'}');
    } catch (e) {
      if (mounted) {
        toast(context, 'Fichier illisible : enregistrez-le au format .xlsx ou .csv puis réessayez.', error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _downloadTemplate() async {
    try {
      final uri = await FilePicker.saveFile(
        dialogTitle: 'Enregistrer le modèle Excel',
        fileName: 'modele_liste_eleves.xlsx',
        bytes: buildExcelTemplate(),
        mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      if (uri != null && mounted) {
        toast(context, 'Modèle Excel enregistré. Remplissez la feuille « Élèves » puis importez-le.');
      }
    } catch (e) {
      if (mounted) toast(context, 'Enregistrement impossible : $e', error: true);
    }
  }

  void _showFormatHelp() {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Format du fichier Excel'),
        content: const SingleChildScrollView(
          child: Text(
            'La première ligne contient les titres des colonnes. Ils sont reconnus automatiquement, '
            'dans n\'importe quel ordre :\n\n'
            '• Nom  (ou « Nom et prénoms » dans une seule colonne)\n'
            '• Prénom(s)\n'
            '• Classe\n'
            '• Matricule\n'
            '• Date de naissance\n'
            '• Lieu de naissance\n'
            '• Sexe\n'
            '• Personne à prévenir / Contact / Téléphone\n\n'
            'Seule la colonne Nom est obligatoire. Les fichiers .xlsx et .csv (séparateur ; ou ,) sont acceptés.',
          ),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Compris'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final q = _query.toLowerCase();
    final list = state.students.where((s) {
      if (_class != null && s.classe.trim() != _class) return false;
      if (q.isEmpty) return true;
      return '${s.nom} ${s.prenom} ${s.matricule} ${s.classe}'.toLowerCase().contains(q);
    }).toList();
    final classes = state.classes;
    if (_class != null && !classes.contains(_class)) _class = null;

    final toolbar = Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
      FilledButton.icon(
        onPressed: _busy ? null : _import,
        icon: _busy
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.upload_file),
        label: const Text('Importer Excel / CSV'),
      ),
      OutlinedButton.icon(
        onPressed: () async {
          final s = await editStudent(context, null, classes: classes, defaultClass: _class);
          if (s != null) state.upsertStudent(s);
        },
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Saisir un élève'),
      ),
      OutlinedButton.icon(
        onPressed: _downloadTemplate,
        icon: const Icon(Icons.download),
        label: const Text('Télécharger le modèle Excel'),
      ),
      IconButton(tooltip: 'Format du fichier', onPressed: _showFormatHelp, icon: const Icon(Icons.help_outline)),
      if (state.students.isNotEmpty)
        TextButton.icon(
          onPressed: () async {
            if (await confirm(
                context, 'Vider la liste ?', 'Les ${state.students.length} élèves et leurs photos seront supprimés.',
                ok: 'Tout supprimer')) {
              state.clearStudents();
            }
          },
          icon: const Icon(Icons.delete_sweep_outlined),
          label: const Text('Vider la liste'),
        ),
    ]);

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          toolbar,
          if (state.students.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Rechercher un élève'),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              if (classes.isNotEmpty) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 170,
                  child: DropdownButtonFormField<String?>(
                    initialValue: _class,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Classe'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Toutes')),
                      for (final c in classes) DropdownMenuItem(value: c, child: Text(c)),
                    ],
                    onChanged: (v) => setState(() => _class = v),
                  ),
                ),
              ],
            ]),
          ],
        ]),
      ),
      Expanded(
        child: state.students.isEmpty
            ? _Empty(onImport: _import, onHelp: _showFormatHelp, onTemplate: _downloadTemplate)
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, i) {
                  final s = list[i];
                  return Material(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    child: ListTile(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      leading: CircleAvatar(
                        backgroundImage: s.photo != null ? MemoryImage(s.photo!) : null,
                        child: s.photo == null ? Text(s.initials) : null,
                      ),
                      title: Text(s.fullName, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        [s.classe, s.matricule, s.dateNaissance].where((e) => e.isNotEmpty).join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (s.validated)
                          const Tooltip(message: 'Carte validée', child: Icon(Icons.verified, color: Colors.green)),
                        IconButton(
                          tooltip: 'Modifier',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () async {
                            final e = await editStudent(context, s, classes: classes);
                            if (e != null) state.upsertStudent(e);
                          },
                        ),
                        IconButton(
                          tooltip: 'Supprimer',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            if (await confirm(context, 'Supprimer ${s.fullName} ?', 'Sa photo sera aussi supprimée.',
                                ok: 'Supprimer')) {
                              state.removeStudent(s);
                            }
                          },
                        ),
                      ]),
                      onTap: () {
                        state.goTo(state.students.indexOf(s));
                        widget.onNext();
                      },
                    ),
                  );
                },
              ),
      ),
      if (state.students.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: widget.onNext,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Étape suivante : les photos'),
            ),
          ),
        ),
    ]);
  }
}

class _Empty extends StatelessWidget {
  final VoidCallback onImport;
  final VoidCallback onHelp;
  final VoidCallback onTemplate;
  const _Empty({required this.onImport, required this.onHelp, required this.onTemplate});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.table_view_outlined, size: 56, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text('Aucun élève pour l\'instant', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            const Text(
              'Importez la liste de classe depuis Excel (colonnes Nom, Prénom, Classe…) ou saisissez les élèves un par un.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
                onPressed: onImport,
                icon: const Icon(Icons.upload_file),
                label: const Text('Importer un fichier Excel')),
            const SizedBox(height: 8),
            OutlinedButton.icon(
                onPressed: onTemplate,
                icon: const Icon(Icons.download),
                label: const Text('Télécharger le modèle Excel à remplir')),
            const SizedBox(height: 4),
            TextButton(onPressed: onHelp, child: const Text('Voir le format attendu')),
          ]),
        ),
      );
}

/// Formulaire de saisie / modification d'un élève.
Future<Student?> editStudent(BuildContext context, Student? s,
    {List<String> classes = const [], String? defaultClass}) {
  final e = s == null
      ? Student(classe: defaultClass ?? '')
      : (Student.fromJson(s.toJson())
        ..photo = s.photo
        ..original = s.original
        ..photoVersion = s.photoVersion);
  final form = GlobalKey<FormState>();
  return showDialog<Student>(
    context: context,
    builder: (c) {
      Widget field(String label, String value, void Function(String) set,
              {bool required = false, String? hint, TextInputType? kb}) =>
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: TextFormField(
              initialValue: value,
              keyboardType: kb,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: label, hintText: hint),
              validator: required ? (v) => (v == null || v.trim().isEmpty) ? 'Champ obligatoire' : null : null,
              onSaved: (v) => set((v ?? '').trim()),
            ),
          );
      return AlertDialog(
        title: Text(s == null ? 'Nouvel élève' : 'Modifier l\'élève'),
        content: SizedBox(
          width: 420,
          child: Form(
            key: form,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                field('Nom', e.nom, (v) => e.nom = v, required: true),
                field('Prénom(s)', e.prenom, (v) => e.prenom = v),
                Autocomplete<String>(
                  initialValue: TextEditingValue(text: e.classe),
                  optionsBuilder: (v) => classes.where((c) => c.toLowerCase().contains(v.text.toLowerCase())),
                  onSelected: (v) => e.classe = v,
                  fieldViewBuilder: (ctx, ctrl, focus, onSubmit) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TextFormField(
                      controller: ctrl,
                      focusNode: focus,
                      decoration: const InputDecoration(labelText: 'Classe', hintText: 'CM2 A, 6e B, Tle D…'),
                      onSaved: (v) => e.classe = (v ?? '').trim(),
                    ),
                  ),
                ),
                field('Matricule', e.matricule, (v) => e.matricule = v),
                field('Date de naissance', e.dateNaissance, (v) => e.dateNaissance = v,
                    hint: 'jj/mm/aaaa', kb: TextInputType.datetime),
                field('Lieu de naissance', e.lieuNaissance, (v) => e.lieuNaissance = v),
                field('Sexe', e.sexe, (v) => e.sexe = v.isEmpty ? '' : v.substring(0, 1).toUpperCase(), hint: 'M ou F'),
                field('Personne à prévenir (téléphone)', e.contact, (v) => e.contact = v, kb: TextInputType.phone),
              ]),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              if (!form.currentState!.validate()) return;
              form.currentState!.save();
              Navigator.pop(c, e);
            },
            child: const Text('Enregistrer'),
          ),
        ],
      );
    },
  );
}
