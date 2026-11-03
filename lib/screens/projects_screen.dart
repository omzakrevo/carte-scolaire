import 'package:flutter/material.dart';

import '../app_state.dart';
import '../card_kinds.dart';
import '../models.dart';
import '../services/license.dart';
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
    final segment = state.browsing;
    final company = segment == segmentCompany;
    final same = segment == state.segment;
    var keepTemplate = same;
    var keepSchool = false;
    final kinds = kindsOfSegment(segment);
    var kind = company ? (same && kindsOfSegment(segment).any((k) => k.id == state.template.kind) ? state.template.kind : 'pro') : 'ecole';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(company ? 'Nouveau projet entreprise' : 'Nouvel établissement'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: name,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: company ? 'Nom de l\'entreprise ou du projet' : 'Nom de l\'établissement ou du projet',
                  hintText: company ? 'Ex. OMZAKREVO – badges 2027' : 'Ex. C.P.E Maranatha 2026-2027',
                ),
              ),
              if (company) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Type de carte', style: Theme.of(c).textTheme.labelLarge),
                ),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final k in kinds)
                    ChoiceChip(
                      label: Text(k.name),
                      selected: kind == k.id,
                      onSelected: (_) => set(() => kind = k.id),
                    ),
                ]),
              ],
              const SizedBox(height: 8),
              if (same)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: keepTemplate,
                  onChanged: (v) => set(() => keepTemplate = v ?? true),
                  title: const Text('Reprendre le modèle de carte actuel'),
                  subtitle: const Text('Sinon, le projet démarre avec le modèle conseillé'),
                ),
              if (same)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: keepSchool,
                  onChanged: (v) => set(() => keepSchool = v ?? false),
                  title: Text(company ? 'Reprendre les infos de l\'entreprise' : 'Reprendre les infos de l\'établissement'),
                  subtitle: const Text('Logo, coordonnées, cachet…'),
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
    await state.createProject(n, keepTemplate: keepTemplate, keepSchool: keepSchool, segment: segment, kind: kind);
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
    final seg = state.browsing;
    final company = seg == segmentCompany;
    final list = state.projects.where((p) => p.segment == seg).toList();
    final nSchool = state.projects.where((p) => p.segment == segmentSchool).length;
    final nCompany = state.projects.length - nSchool;
    final lm = LicenseScope.of(context);
    final schoolAllowed = lm.hasModule('ecole') || lm.hasModule(bulletinModule);
    final companyAllowed = kindsOfSegment(segmentCompany).any((k) => lm.hasModule(k.id));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SegmentedButton<String>(
          segments: [
            ButtonSegment(
                value: segmentSchool,
                icon: const Icon(Icons.school_outlined),
                label: Text('Établissements ($nSchool)')),
            ButtonSegment(
                value: segmentCompany,
                icon: const Icon(Icons.business_outlined),
                label: Text('Entreprises ($nCompany)')),
          ],
          selected: {seg},
          onSelectionChanged: (v) {
            state.browsing = v.first;
            state.changed();
          },
        ),
        const SizedBox(height: 8),
        Text(
            company
                ? 'Entreprises, ONG, associations, événements : cartes professionnelles, de membre, visiteur, '
                    'cartes de visite et pointage des heures de travail.'
                : 'Écoles, collèges, lycées : cartes scolaires, présences des élèves, notes et bulletins.',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
          FilledButton.icon(
            onPressed: () {
              if (!(company ? companyAllowed : schoolAllowed)) {
                toast(context, 'L\'espace « ${segmentName(seg)} » n\'est pas activé dans votre licence.', error: true);
                return;
              }
              _create(context, state);
            },
            icon: Icon(company ? Icons.add_business_outlined : Icons.create_new_folder_outlined),
            label: Text(company ? 'Nouveau projet entreprise' : 'Nouvel établissement'),
          ),
          Text(
              company
                  ? 'Un projet par entreprise : modèle, personnes et photos sont gardés séparément.'
                  : 'Un projet par établissement : modèle, élèves, photos, notes et présences sont gardés séparément.',
              style: Theme.of(context).textTheme.bodySmall),
        ]),
        const SizedBox(height: 16),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Column(children: [
              Icon(company ? Icons.business : Icons.school, size: 56, color: scheme.outline),
              const SizedBox(height: 8),
              Text(company ? 'Aucun projet entreprise pour l\'instant.' : 'Aucun établissement pour l\'instant.',
                  textAlign: TextAlign.center),
            ]),
          ),
        for (final p in list)
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
                leading: Icon(
                    p.segment == segmentCompany
                        ? Icons.business
                        : (p.id == state.projectId ? Icons.folder_open : Icons.folder_outlined),
                    color: scheme.primary,
                    size: 30),
                title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text([
                  if (p.schoolName.isNotEmpty) p.schoolName,
                  '${p.studentCount} ${p.segment == segmentCompany ? 'personnes' : 'élèves'} · ${p.photoCount} photos',
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
