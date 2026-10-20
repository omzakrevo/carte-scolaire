import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../widgets/common.dart';

String _date(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year} à ${two(d.hour)}h${two(d.minute)}';
}

/// Un projet par établissement : on les garde de côté et on passe de l'un à l'autre.
class ProjectsScreen extends StatelessWidget {
  final VoidCallback onOpened;
  const ProjectsScreen({super.key, required this.onOpened});

  Future<void> _create(BuildContext context, AppState state) async {
    final name = TextEditingController();
    var keepTemplate = true;
    var keepSchool = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Nouveau projet'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Nom du projet',
                  hintText: 'Ex. C.P.E Maranatha 2026-2027',
                ),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: keepTemplate,
                onChanged: (v) => set(() => keepTemplate = v ?? true),
                title: const Text('Reprendre le modèle de carte actuel'),
                subtitle: const Text('Sinon, le projet démarre avec le modèle par défaut'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: keepSchool,
                onChanged: (v) => set(() => keepSchool = v ?? false),
                title: const Text('Reprendre les infos de l\'établissement'),
                subtitle: const Text('Pour un nouveau lot du même établissement'),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Créer')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final n = name.text.trim().isEmpty ? 'Nouveau projet' : name.text.trim();
    await state.createProject(n, keepTemplate: keepTemplate, keepSchool: keepSchool);
    if (context.mounted) {
      toast(context, 'Projet « $n » créé et ouvert.');
      onOpened();
    }
  }

  Future<void> _rename(BuildContext context, AppState state, ProjectInfo p) async {
    final c = TextEditingController(text: p.name);
    final n = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Renommer le projet'),
        content: TextField(controller: c, autofocus: true, onSubmitted: (v) => Navigator.pop(d, v)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(d, c.text), child: const Text('Renommer')),
        ],
      ),
    );
    if (n != null && n.trim().isNotEmpty) await state.renameProject(p, n.trim());
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
          FilledButton.icon(
            onPressed: () => _create(context, state),
            icon: const Icon(Icons.create_new_folder_outlined),
            label: const Text('Nouveau projet'),
          ),
          Text('Un projet par établissement : modèle, élèves et photos sont gardés séparément.',
              style: Theme.of(context).textTheme.bodySmall),
        ]),
        const SizedBox(height: 16),
        for (final p in state.projects)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: p.id == state.projectId ? scheme.primaryContainer : scheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: p.id == state.projectId ? scheme.primary : scheme.outlineVariant),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                leading: Icon(p.id == state.projectId ? Icons.folder_open : Icons.folder_outlined,
                    color: scheme.primary, size: 30),
                title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text([
                  if (p.schoolName.isNotEmpty) p.schoolName,
                  '${p.studentCount} élèves · ${p.photoCount} photos',
                  'Modifié le ${_date(p.updated)}',
                ].join('\n')),
                isThreeLine: true,
                onTap: () async {
                  await state.openProject(p.id);
                  onOpened();
                },
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (p.id == state.projectId)
                    const Chip(label: Text('Ouvert'))
                  else
                    TextButton(
                      onPressed: () async {
                        await state.openProject(p.id);
                        onOpened();
                      },
                      child: const Text('Ouvrir'),
                    ),
                  PopupMenuButton<String>(
                    tooltip: 'Actions',
                    onSelected: (a) async {
                      switch (a) {
                        case 'rename':
                          await _rename(context, state, p);
                        case 'duplicate':
                          await state.duplicateProject(p);
                          if (context.mounted) toast(context, 'Copie de « ${p.name} » créée.');
                        case 'delete':
                          if (await confirm(context, 'Supprimer « ${p.name} » ?',
                              'Le modèle, les ${p.studentCount} élèves et leurs photos seront définitivement supprimés de cet appareil.',
                              ok: 'Supprimer')) {
                            await state.deleteProject(p);
                          }
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'rename', child: Text('Renommer')),
                      PopupMenuItem(value: 'duplicate', child: Text('Dupliquer')),
                      PopupMenuItem(value: 'delete', child: Text('Supprimer')),
                    ],
                  ),
                ]),
              ),
            ),
          ),
      ],
    );
  }
}
