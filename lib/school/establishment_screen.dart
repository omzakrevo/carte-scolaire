import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';

import '../app_state.dart';
import '../widgets/common.dart';
import '../widgets/org_info_form.dart';
import 'school_controller.dart';
import 'school_engine.dart';
import 'school_models.dart';
import 'timetable_engine.dart';
import 'timetable_pdf.dart';

String _n(double v) => v == v.roundToDouble() ? v.toInt().toString() : fmt(v);

/// Onglet « Établissement » : infos, classes et matières, professeurs, emploi du temps.
class EstablishmentScreen extends StatelessWidget {
  const EstablishmentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = SchoolScope.of(context);
    AppScope.of(context);
    if (!ctrl.loaded) return const Center(child: CircularProgressIndicator());
    return DefaultTabController(
      length: 4,
      child: Column(children: [
        Material(
          color: Theme.of(context).colorScheme.surface,
          child: const TabBar(isScrollable: true, tabAlignment: TabAlignment.center, tabs: [
            Tab(icon: Icon(Icons.apartment), text: 'Infos'),
            Tab(icon: Icon(Icons.class_outlined), text: 'Classes'),
            Tab(icon: Icon(Icons.person_pin_outlined), text: 'Professeurs'),
            Tab(icon: Icon(Icons.calendar_view_week), text: 'Emploi du temps'),
          ]),
        ),
        const Expanded(
          child: TabBarView(physics: NeverScrollableScrollPhysics(), children: [
            _InfoTab(),
            _ClassesTab(),
            _TeachersTab(),
            _TimetableTab(),
          ]),
        ),
      ]),
    );
  }
}

// =====================================================================
// Infos : tableau de bord + fiche de l'établissement
// =====================================================================

class _InfoTab extends StatelessWidget {
  const _InfoTab();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final ctrl = SchoolScope.of(context);
    final b = ctrl.book;
    final scheme = Theme.of(context).colorScheme;
    final subjects = b.classes.values.fold(0, (a, c) => a + c.subjects.length);
    final unassigned = b.classes.values.fold(0, (a, c) => a + c.subjects.where((s) => s.teacherId == null && !s.conduct).length);
    Widget stat(IconData i, String label, String value, int tab) => InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: tab < 0 ? null : () => DefaultTabController.of(context).animateTo(tab),
          child: Container(
            width: 170,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              Icon(i, color: scheme.primary, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                  Text(label, style: Theme.of(context).textTheme.bodySmall),
                ]),
              ),
            ]),
          ),
        );
    final logo = app.school.logo;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        if (logo != null)
          Padding(padding: const EdgeInsets.only(right: 12), child: Image.memory(logo, width: 56, height: 56)),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(app.school.name.isEmpty ? 'Votre établissement' : app.school.name,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            Text(
                [if (app.school.schoolYear.isNotEmpty) 'Année scolaire ${app.school.schoolYear}', app.school.address]
                    .where((e) => e.isNotEmpty)
                    .join(' · '),
                style: Theme.of(context).textTheme.bodyMedium),
          ]),
        ),
      ]),
      const SizedBox(height: 14),
      Wrap(spacing: 10, runSpacing: 10, children: [
        stat(Icons.groups, 'Élèves', '${app.students.length}', -1),
        stat(Icons.class_outlined, 'Classes', '${ctrl.classNames.length}', 1),
        stat(Icons.menu_book, 'Matières', '$subjects', 1),
        stat(Icons.person_pin_outlined, 'Professeurs', '${b.teachers.length}', 2),
      ]),
      if (ctrl.classNames.isEmpty || b.teachers.isEmpty || unassigned > 0) ...[
        const SizedBox(height: 12),
        Card(
          color: scheme.secondaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Pour bien démarrer', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              _step(context, app.school.name.isNotEmpty && app.school.name != 'Complexe Scolaire Les Étoiles',
                  '1. Renseignez le nom, le logo et la direction ci-dessous'),
              _step(context, ctrl.classNames.isNotEmpty, '2. Créez les classes (onglet Classes) avec leurs matières'),
              _step(context, b.teachers.isNotEmpty, '3. Ajoutez les professeurs (onglet Professeurs)'),
              _step(context, b.teachers.isNotEmpty && unassigned == 0,
                  '4. Attribuez un professeur à chaque matière${unassigned > 0 ? ' ($unassigned sans professeur)' : ''}'),
              _step(context, b.timetable.isNotEmpty, '5. Générez l\'emploi du temps'),
            ]),
          ),
        ),
      ],
      const SizedBox(height: 16),
      OrgInfoForm(state: app),
    ]);
  }

  Widget _step(BuildContext context, bool done, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(children: [
          Icon(done ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 18, color: done ? const Color(0xFF0B6B3A) : Theme.of(context).colorScheme.outline),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(decoration: done ? TextDecoration.lineThrough : null))),
        ]),
      );
}

// =====================================================================
// Classes
// =====================================================================

/// Cycles proposés pour créer plusieurs classes d'un coup.
const _cycles = <(String, List<String>, int)>[
  ('Primaire (CP1 à CM2)', ['CP1', 'CP2', 'CE1', 'CE2', 'CM1', 'CM2'], 1),
  ('Post-primaire (6e à 3e)', ['6e', '5e', '4e', '3e'], 2),
  ('Lycée (2nde à Tle, séries A et D)', ['2nde A', '2nde C', '1re A', '1re D', 'Tle A', 'Tle D'], 3),
];

SubjectPreset? _presetFor(String className) {
  final c = className.toUpperCase();
  if (RegExp(r'^(CP|CE)').hasMatch(c)) return subjectPresets[0];
  if (c.startsWith('CM')) return subjectPresets[1];
  if (RegExp(r'^[3456]E').hasMatch(c)) return subjectPresets[2];
  if (RegExp(r'(^|\s)A\d?$').hasMatch(c) && RegExp(r'^(2NDE|1RE|TLE)').hasMatch(c)) return subjectPresets[3];
  if (RegExp(r'(^|\s)C\d?$').hasMatch(c) && RegExp(r'^(2NDE|1RE|TLE)').hasMatch(c)) return subjectPresets[4];
  if (RegExp(r'(^|\s)D\d?$').hasMatch(c) && RegExp(r'^(2NDE|1RE|TLE)').hasMatch(c)) return subjectPresets[5];
  return null;
}

class _ClassesTab extends StatelessWidget {
  const _ClassesTab();

  Future<void> _newClass(BuildContext context, SchoolController ctrl) async {
    final name = TextEditingController();
    SubjectPreset? preset;
    var auto = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: const Text('Nouvelle classe'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Nom de la classe', hintText: '6e A, CM2, Tle D…'),
                onChanged: (v) {
                  if (auto) set(() => preset = _presetFor(v));
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<SubjectPreset?>(
                initialValue: preset,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Matières'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Aucune (je les ajoute moi-même)')),
                  for (final p in subjectPresets) DropdownMenuItem(value: p, child: Text(p.name)),
                ],
                onChanged: (v) => set(() {
                  auto = false;
                  preset = v;
                }),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Créer')),
          ],
        ),
      ),
    );
    final n = name.text.trim();
    if (ok != true || n.isEmpty) return;
    if (ctrl.classNames.contains(n)) {
      if (context.mounted) toast(context, 'La classe « $n » existe déjà.', error: true);
      return;
    }
    ctrl.addClass(n, preset: preset);
    if (context.mounted) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ClassDetailPage(className: n)));
    }
  }

  Future<void> _addCycle(BuildContext context, SchoolController ctrl) async {
    final cycle = await showDialog<(String, List<String>, int)>(
      context: context,
      builder: (d) => SimpleDialog(
        title: const Text('Ajouter les classes d\'un cycle'),
        children: [
          for (final c in _cycles)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(d, c),
              child: ListTile(title: Text(c.$1), subtitle: Text(c.$2.join(', '))),
            ),
        ],
      ),
    );
    if (cycle == null) return;
    var n = 0;
    for (final c in cycle.$2) {
      if (ctrl.classNames.contains(c)) continue;
      ctrl.addClass(c, preset: _presetFor(c) ?? subjectPresets[cycle.$3]);
      n++;
    }
    if (context.mounted) toast(context, '$n classe(s) créée(s) avec leurs matières. Renommez-les si besoin (6e A, 6e B…).');
  }

  Future<void> _rename(BuildContext context, SchoolController ctrl, String name) async {
    final c = TextEditingController(text: name);
    final v = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Renommer la classe'),
        content: TextField(controller: c, autofocus: true, onSubmitted: (x) => Navigator.pop(d, x)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(d, c.text), child: const Text('Renommer')),
        ],
      ),
    );
    if (v == null || v.trim().isEmpty || v.trim() == name) return;
    if (ctrl.classNames.contains(v.trim())) {
      if (context.mounted) toast(context, 'La classe « ${v.trim()} » existe déjà.', error: true);
      return;
    }
    ctrl.renameClass(name, v);
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = SchoolScope.of(context);
    final classes = ctrl.classNames;
    final scheme = Theme.of(context).colorScheme;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.icon(
          onPressed: () => _newClass(context, ctrl),
          icon: const Icon(Icons.add),
          label: const Text('Nouvelle classe'),
        ),
        OutlinedButton.icon(
          onPressed: () => _addCycle(context, ctrl),
          icon: const Icon(Icons.playlist_add),
          label: const Text('Ajouter un cycle complet'),
        ),
      ]),
      const SizedBox(height: 6),
      Text('Touchez une classe pour régler ses matières, coefficients, heures et professeurs.',
          style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 12),
      if (classes.isEmpty)
        Padding(
          padding: const EdgeInsets.all(32),
          child: Column(children: [
            Icon(Icons.class_outlined, size: 56, color: scheme.outline),
            const SizedBox(height: 8),
            const Text('Aucune classe. Créez-en une, ou ajoutez tout un cycle (6e à 3e…) en un geste.',
                textAlign: TextAlign.center),
          ]),
        ),
      for (final name in classes)
        Builder(builder: (context) {
          final c = ctrl.classOf(name);
          final hours = c.subjects.fold(0, (a, s) => a + s.hours);
          final missing = c.subjects.where((s) => s.teacherId == null && !s.conduct && s.hours > 0).length;
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: scheme.primaryContainer,
                child: Text(name.length <= 3 ? name : name.substring(0, 3), style: const TextStyle(fontSize: 12)),
              ),
              title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text([
                '${ctrl.studentsOf(name).length} élèves',
                '${c.subjects.length} matières',
                '$hours h/semaine',
                'notes sur ${_n(c.scale)}',
                if (c.titulaire.isNotEmpty) 'titulaire ${c.titulaire}',
                if (missing > 0) '$missing sans professeur',
              ].join(' · ')),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ClassDetailPage(className: name))),
              trailing: PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'rename') await _rename(context, ctrl, name);
                  if (v == 'delete' &&
                      context.mounted &&
                      await confirm(
                          context,
                          'Supprimer la classe $name ?',
                          'Matières, coefficients et emploi du temps de la classe seront supprimés. '
                              'Les ${ctrl.studentsOf(name).length} élèves restent dans la liste, sans classe.',
                          ok: 'Supprimer')) {
                    ctrl.deleteClass(name);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rename', child: Text('Renommer')),
                  PopupMenuItem(value: 'delete', child: Text('Supprimer')),
                ],
              ),
            ),
          );
        }),
    ]);
  }
}

/// Fiche d'une classe : barème, titulaire, matières (coef, heures, professeur).
class ClassDetailPage extends StatelessWidget {
  final String className;
  const ClassDetailPage({super.key, required this.className});

  Future<void> _editSubject(BuildContext context, SchoolController ctrl, ClassConfig cls, Subject? existing) async {
    final s = existing?.copy() ?? Subject(name: '', hours: 2);
    final name = TextEditingController(text: s.name);
    final coef = TextEditingController(text: _n(s.coef));
    final hours = TextEditingController(text: '${s.hours}');
    final max = TextEditingController(text: s.max == null ? '' : _n(s.max!));
    var teacherId = s.teacherId;
    var conduct = s.conduct;
    final teachers = ctrl.book.teachers;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: Text(existing == null ? 'Nouvelle matière' : 'Modifier la matière'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: name, autofocus: existing == null, decoration: const InputDecoration(labelText: 'Matière')),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: coef,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Coefficient'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: hours,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(labelText: 'Heures / semaine'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: max,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(labelText: 'Noté sur', hintText: _n(cls.scale)),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                DropdownButtonFormField<String?>(
                  initialValue: teachers.any((t) => t.id == teacherId) ? teacherId : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Professeur'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('— Non attribué —')),
                    for (final t in teachers)
                      DropdownMenuItem(
                          value: t.id,
                          child: Text('${t.name}${t.subjects.isEmpty ? '' : ' (${t.subjects})'}',
                              overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => set(() => teacherId = v),
                ),
                if (teachers.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text('Ajoutez vos professeurs dans l\'onglet « Professeurs » pour les attribuer ici.'),
                  ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: conduct,
                  onChanged: (v) => set(() => conduct = v ?? false),
                  title: const Text('Matière « Conduite »'),
                  subtitle: const Text('Reçoit la retenue pour absences ; pas d\'heures de cours'),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Enregistrer')),
          ],
        ),
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    s
      ..name = name.text.trim()
      ..coef = parseNote(coef.text) ?? 1
      ..hours = conduct ? 0 : (int.tryParse(hours.text) ?? 0)
      ..max = parseNote(max.text)
      ..conduct = conduct;
    ctrl.book.assign(s, ctrl.book.teacher(teacherId));
    if (existing == null) {
      cls.subjects.add(s);
    } else {
      cls.subjects[cls.subjects.indexWhere((e) => e.id == existing.id)] = s;
    }
    ctrl.changed();
  }

  Future<void> _copyTo(BuildContext context, SchoolController ctrl, ClassConfig cls) async {
    final others = ctrl.classNames.where((c) => c != cls.name).toList();
    final picked = <String>{};
    var withTeachers = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: Text('Copier les matières de ${cls.name}'),
          content: SizedBox(
            width: 380,
            child: ListView(shrinkWrap: true, children: [
              const Text('Matières, coefficients, heures et barème remplacent ceux des classes cochées.'),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: withTeachers,
                onChanged: (v) => set(() => withTeachers = v ?? false),
                title: const Text('Garder aussi les mêmes professeurs'),
              ),
              const Divider(),
              for (final c in others)
                CheckboxListTile(
                  dense: true,
                  value: picked.contains(c),
                  onChanged: (v) => set(() => v == true ? picked.add(c) : picked.remove(c)),
                  title: Text(c),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Copier')),
          ],
        ),
      ),
    );
    if (ok != true || picked.isEmpty) return;
    for (final c in picked) {
      ctrl.classOf(c)
        ..scale = cls.scale
        ..subjects = cls.subjects.map((e) {
          final x = e.copy(newId: true);
          if (!withTeachers) ctrl.book.assign(x, null);
          return x;
        }).toList();
    }
    ctrl.changed();
    if (context.mounted) toast(context, 'Matières copiées vers ${picked.length} classe(s).');
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = SchoolScope.of(context);
    final cls = ctrl.classOf(className);
    final teachers = ctrl.book.teachers;
    final hours = cls.subjects.fold(0, (a, s) => a + s.hours);
    final capacity = ctrl.book.tt.usable().length;
    return Scaffold(
      appBar: AppBar(title: Text('Classe $className')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editSubject(context, ctrl, cls, null),
        icon: const Icon(Icons.add),
        label: const Text('Matière'),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 90), children: [
        Section(title: 'Réglages de la classe', children: [
          Wrap(spacing: 12, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
            const Text('Notes sur'),
            SegmentedButton<double>(
              segments: const [
                ButtonSegment(value: 10, label: Text('10 (primaire)')),
                ButtonSegment(value: 20, label: Text('20')),
              ],
              selected: {cls.scale == 10 ? 10 : 20},
              onSelectionChanged: (v) {
                cls.scale = v.first;
                ctrl.changed();
              },
            ),
          ]),
          const SizedBox(height: 12),
          if (teachers.isNotEmpty)
            DropdownButtonFormField<String>(
              initialValue: teachers.any((t) => t.name == cls.titulaire) ? cls.titulaire : '',
              isExpanded: true,
              decoration: InputDecoration(labelText: cls.scale == 10 ? 'Maître / maîtresse' : 'Professeur principal (titulaire)'),
              items: [
                const DropdownMenuItem(value: '', child: Text('—')),
                for (final t in teachers) DropdownMenuItem(value: t.name, child: Text(t.name)),
              ],
              onChanged: (v) {
                cls.titulaire = v ?? '';
                ctrl.changed();
              },
            )
          else
            TextSetting(
              key: ValueKey('tit-$className'),
              label: cls.scale == 10 ? 'Maître / maîtresse' : 'Professeur principal (titulaire)',
              value: cls.titulaire,
              onChanged: (v) {
                cls.titulaire = v;
                ctrl.changed();
              },
            ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            MenuAnchor(
              builder: (c, m, _) => OutlinedButton.icon(
                onPressed: () => m.isOpen ? m.close() : m.open(),
                icon: const Icon(Icons.auto_awesome_outlined),
                label: const Text('Programme prêt à l\'emploi'),
              ),
              menuChildren: [
                for (final p in subjectPresets)
                  MenuItemButton(
                    onPressed: () async {
                      if (cls.subjects.isNotEmpty &&
                          !await confirm(context, 'Remplacer les matières ?',
                              'Les ${cls.subjects.length} matières de $className seront remplacées par « ${p.name} ».',
                              ok: 'Remplacer')) {
                        return;
                      }
                      cls
                        ..subjects = p.build()
                        ..scale = p.scale;
                      ctrl.changed();
                    },
                    child: Text('${p.name} – sur ${_n(p.scale)}'),
                  ),
              ],
            ),
            if (ctrl.classNames.length > 1 && cls.subjects.isNotEmpty)
              OutlinedButton.icon(
                onPressed: () => _copyTo(context, ctrl, cls),
                icon: const Icon(Icons.copy_all),
                label: const Text('Copier vers d\'autres classes'),
              ),
          ]),
        ]),
        const SizedBox(height: 12),
        Text('Matières (${cls.subjects.length}) · coefficients ${_n(cls.coefTotal)} · $hours h par semaine'
            '${hours > capacity ? ' — dépasse les $capacity créneaux de la semaine' : ''}',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700, color: hours > capacity ? Theme.of(context).colorScheme.error : null)),
        const SizedBox(height: 8),
        if (cls.subjects.isEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('Aucune matière : ajoutez-les avec le bouton « Matière », ou chargez un programme prêt à l\'emploi.'),
          ),
        for (var i = 0; i < cls.subjects.length; i++)
          Builder(builder: (context) {
            final m = cls.subjects[i];
            final tName = ctrl.book.teacherName(m);
            final narrow = MediaQuery.sizeOf(context).width < 600;
            final teacherChip = m.conduct
                ? null
                : PopupMenuButton<String>(
                    tooltip: 'Attribuer un professeur',
                    onSelected: (v) {
                      ctrl.book.assign(m, v == '' ? null : ctrl.book.teacher(v));
                      ctrl.changed();
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: '', child: Text('— Non attribué —')),
                      for (final t in teachers) PopupMenuItem(value: t.id, child: Text(t.name)),
                    ],
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 200),
                      child: Chip(
                        visualDensity: VisualDensity.compact,
                        avatar: Icon(tName.isEmpty ? Icons.person_add_alt : Icons.person, size: 16),
                        label: Text(tName.isEmpty ? 'Attribuer un professeur' : tName, overflow: TextOverflow.ellipsis),
                        backgroundColor: tName.isEmpty ? Theme.of(context).colorScheme.errorContainer : null,
                      ),
                    ),
                  );
            final info = Text([
              'Coef ${_n(m.coef)}',
              if (!m.conduct) '${m.hours} h/sem.',
              'sur ${_n(cls.maxOf(m))}',
              if (m.conduct) 'Conduite',
            ].join(' · '));
            return Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Color(subjectColor(m.name, index: i)),
                  child: Text(_n(m.coef), style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w700)),
                ),
                title: Text(m.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: narrow && teacherChip != null
                    ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        info,
                        Align(alignment: Alignment.centerLeft, child: teacherChip),
                      ])
                    : info,
                onTap: () => _editSubject(context, ctrl, cls, m),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (!narrow && teacherChip != null) teacherChip,
                  PopupMenuButton<String>(
                    onSelected: (v) async {
                      if (v == 'up' && i > 0) {
                        cls.subjects.insert(i - 1, cls.subjects.removeAt(i));
                        ctrl.changed();
                      }
                      if (v == 'delete' &&
                          await confirm(context, 'Supprimer « ${m.name} » ?',
                              'Les notes déjà saisies pour cette matière ne seront plus comptées.',
                              ok: 'Supprimer')) {
                        cls.subjects.removeAt(i);
                        ctrl.changed();
                      }
                    },
                    itemBuilder: (_) => [
                      if (i > 0) const PopupMenuItem(value: 'up', child: Text('Monter')),
                      const PopupMenuItem(value: 'delete', child: Text('Supprimer')),
                    ],
                  ),
                ]),
              ),
            );
          }),
      ]),
    );
  }
}

// =====================================================================
// Professeurs
// =====================================================================

class _TeachersTab extends StatelessWidget {
  const _TeachersTab();

  @override
  Widget build(BuildContext context) {
    final ctrl = SchoolScope.of(context);
    final list = [...ctrl.book.teachers]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final scheme = Theme.of(context).colorScheme;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        FilledButton.icon(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TeacherPage())),
          icon: const Icon(Icons.person_add_alt),
          label: const Text('Ajouter un professeur'),
        ),
        Text('Puis attribuez-lui ses matières et ses classes.', style: Theme.of(context).textTheme.bodySmall),
      ]),
      const SizedBox(height: 12),
      if (list.isEmpty)
        Padding(
          padding: const EdgeInsets.all(32),
          child: Column(children: [
            Icon(Icons.person_pin_outlined, size: 56, color: scheme.outline),
            const SizedBox(height: 8),
            const Text('Aucun professeur pour l\'instant.', textAlign: TextAlign.center),
          ]),
        ),
      for (final t in list)
        Builder(builder: (context) {
          final a = ctrl.assignments(t.id);
          final h = ctrl.book.teacherHours(t.id);
          final classes = a.map((e) => e.$1).toSet();
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: CircleAvatar(child: Text(t.name.trim().isEmpty ? '?' : t.name.trim()[0].toUpperCase())),
              title: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text([
                if (t.subjects.isNotEmpty) t.subjects,
                if (t.phone.isNotEmpty) t.phone,
                a.isEmpty ? 'aucune attribution' : '$h h/semaine · ${classes.length} classe(s) : ${classes.join(', ')}',
                if (t.maxHours > 0 && h > t.maxHours) '⚠ dépasse son maximum de ${t.maxHours} h',
              ].join(' · ')),
              isThreeLine: a.isNotEmpty,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TeacherPage(teacherId: t.id))),
              trailing: const Icon(Icons.chevron_right),
            ),
          );
        }),
    ]);
  }
}

/// Fiche professeur : coordonnées, attributions (classe + matière) et disponibilités.
class TeacherPage extends StatefulWidget {
  final String? teacherId;
  const TeacherPage({super.key, this.teacherId});

  @override
  State<TeacherPage> createState() => _TeacherPageState();
}

class _TeacherPageState extends State<TeacherPage> {
  late Teacher t;
  late final bool isNew;
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _subjects = TextEditingController();
  final _max = TextEditingController();

  @override
  void initState() {
    super.initState();
    final ctrl = SchoolScope.read(context);
    final existing = ctrl.book.teacher(widget.teacherId);
    isNew = existing == null;
    t = existing == null ? Teacher(name: '') : Teacher.fromJson(existing.toJson());
    _name.text = t.name;
    _phone.text = t.phone;
    _email.text = t.email;
    _subjects.text = t.subjects;
    _max.text = t.maxHours == 0 ? '' : '${t.maxHours}';
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _subjects, _max]) {
      c.dispose();
    }
    super.dispose();
  }

  bool _save({bool quiet = false}) {
    final name = _name.text.trim();
    if (name.isEmpty) {
      if (!quiet) toast(context, 'Indiquez le nom du professeur.', error: true);
      return false;
    }
    t
      ..name = name
      ..phone = _phone.text.trim()
      ..email = _email.text.trim()
      ..subjects = _subjects.text.trim()
      ..maxHours = int.tryParse(_max.text) ?? 0;
    SchoolScope.read(context).saveTeacher(t);
    return true;
  }

  Future<void> _addAssignment(SchoolController ctrl) async {
    if (!_save()) return;
    String? cls = ctrl.classNames.isEmpty ? null : ctrl.classNames.first;
    final picked = <String>{};
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(builder: (d, set) {
        final c = cls == null ? null : ctrl.classOf(cls!);
        return AlertDialog(
          title: Text('Attribuer à ${t.name}'),
          content: SizedBox(
            width: 420,
            child: ctrl.classNames.isEmpty
                ? const Text('Créez d\'abord les classes (onglet Classes).')
                : Column(mainAxisSize: MainAxisSize.min, children: [
                    DropdownButtonFormField<String>(
                      initialValue: cls,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Classe'),
                      items: [for (final x in ctrl.classNames) DropdownMenuItem(value: x, child: Text(x))],
                      onChanged: (v) => set(() {
                        cls = v;
                        picked.clear();
                      }),
                    ),
                    const SizedBox(height: 8),
                    if (c != null && c.subjects.isEmpty) const Text('Cette classe n\'a pas encore de matières.'),
                    if (c != null)
                      Flexible(
                        child: ListView(shrinkWrap: true, children: [
                          for (final s in c.subjects.where((s) => !s.conduct))
                            CheckboxListTile(
                              dense: true,
                              value: picked.contains(s.id) || s.teacherId == t.id,
                              onChanged: s.teacherId == t.id
                                  ? null
                                  : (v) => set(() => v == true ? picked.add(s.id) : picked.remove(s.id)),
                              title: Text(s.name),
                              subtitle: Text([
                                '${s.hours} h/sem.',
                                if (s.teacherId != null && s.teacherId != t.id) 'actuellement : ${ctrl.book.teacherName(s)}',
                              ].join(' · ')),
                            ),
                        ]),
                      ),
                  ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Attribuer')),
          ],
        );
      }),
    );
    if (ok != true || cls == null || picked.isEmpty) return;
    for (final s in ctrl.classOf(cls!).subjects) {
      if (picked.contains(s.id)) ctrl.book.assign(s, t);
    }
    ctrl.changed();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = SchoolScope.of(context);
    final tt = ctrl.book.tt;
    final assign = isNew && ctrl.book.teacher(t.id) == null ? <(String, Subject)>[] : ctrl.assignments(t.id);
    final hours = assign.fold(0, (a, e) => a + e.$2.hours);
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && _name.text.trim().isNotEmpty) _save(quiet: true);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(isNew ? 'Nouveau professeur' : t.name),
          actions: [
            if (!isNew)
              IconButton(
                tooltip: 'Supprimer',
                onPressed: () async {
                  if (await confirm(context, 'Supprimer ${t.name} ?',
                      'Ses ${assign.length} attribution(s) seront retirées des classes.',
                      ok: 'Supprimer')) {
                    ctrl.deleteTeacher(t);
                    _name.clear();
                    if (context.mounted) Navigator.pop(context);
                  }
                },
                icon: const Icon(Icons.delete_outline),
              ),
            TextButton(
              onPressed: () {
                if (_save()) Navigator.pop(context);
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Section(title: 'Coordonnées', children: [
            TextField(controller: _name, autofocus: isNew, decoration: const InputDecoration(labelText: 'Nom et prénom')),
            const SizedBox(height: 10),
            TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Téléphone')),
            const SizedBox(height: 10),
            TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'E-mail')),
            const SizedBox(height: 10),
            TextField(
                controller: _subjects,
                decoration: const InputDecoration(labelText: 'Matières enseignées', hintText: 'Mathématiques, Physique-Chimie')),
            const SizedBox(height: 10),
            TextField(
              controller: _max,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Heures maximum par semaine (facultatif)'),
            ),
          ]),
          const SizedBox(height: 12),
          Section(
            title: 'Attributions',
            subtitle: assign.isEmpty ? 'Classes et matières de ce professeur' : '$hours h par semaine',
            trailing: TextButton.icon(
              onPressed: () => _addAssignment(ctrl),
              icon: const Icon(Icons.add),
              label: const Text('Attribuer'),
            ),
            children: [
              if (assign.isEmpty) const Text('Aucune classe attribuée.'),
              for (final (c, s) in assign)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.class_outlined),
                  title: Text('$c – ${s.name}'),
                  subtitle: Text('${s.hours} h/sem. · coef ${_n(s.coef)}'),
                  trailing: IconButton(
                    tooltip: 'Retirer',
                    onPressed: () {
                      ctrl.book.assign(s, null);
                      ctrl.changed();
                      setState(() {});
                    },
                    icon: const Icon(Icons.close),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Section(
            title: 'Disponibilités',
            subtitle: 'Touchez un créneau pour le marquer « indisponible » : l\'emploi du temps n\'y placera pas de cours.',
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: _SlotGrid(
                  tt: tt,
                  cell: (slot) {
                    final off = t.unavailable.contains(slot);
                    return InkWell(
                      onTap: () => setState(() => off ? t.unavailable.remove(slot) : t.unavailable.add(slot)),
                      child: Container(
                        alignment: Alignment.center,
                        color: off ? const Color(0xFFFFCDD2) : const Color(0xFFE8F5E9),
                        child: Icon(off ? Icons.block : Icons.check, size: 16, color: off ? Colors.red : Colors.green),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          if (!isNew) ...[
            const SizedBox(height: 12),
            Section(title: 'Son emploi du temps', children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Builder(builder: (context) {
                  final sched = teacherSchedule(ctrl.book, t.id);
                  return _SlotGrid(
                    tt: tt,
                    cell: (slot) {
                      final e = sched[slot];
                      if (e == null) return const SizedBox();
                      final cls = ctrl.book.classes[e.$1];
                      return _LessonCell(
                          title: e.$2.name,
                          sub: e.$1,
                          color: subjectColor(e.$2.name, index: cls?.subjects.indexOf(e.$2)));
                    },
                  );
                }),
              ),
            ]),
          ],
        ]),
      ),
    );
  }
}

// =====================================================================
// Emploi du temps
// =====================================================================

/// Grille jours × créneaux.
class _SlotGrid extends StatelessWidget {
  final TimetableSettings tt;
  final Widget Function(String slot) cell;
  static const cellWidth = 118.0;

  /// Largeur disponible : si elle suffit, la grille l'occupe entièrement (sans défilement).
  final double? width;
  const _SlotGrid({required this.tt, required this.cell, this.width});

  static Widget fit(TimetableSettings tt, Widget Function(String slot) cell) => LayoutBuilder(
        builder: (context, box) {
          final need = 92 + tt.days.length * cellWidth;
          if (box.maxWidth.isFinite && box.maxWidth >= need) {
            return _SlotGrid(tt: tt, cell: cell, width: box.maxWidth.clamp(need, 1300).toDouble());
          }
          return SingleChildScrollView(scrollDirection: Axis.horizontal, child: _SlotGrid(tt: tt, cell: cell));
        },
      );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final head = TextStyle(fontWeight: FontWeight.w700, color: scheme.onPrimary);
    final cellHeight = width != null && width! > 900 ? 56.0 : 46.0;
    final table = Table(
      border: TableBorder.all(color: scheme.outlineVariant),
      defaultColumnWidth: width == null ? const FixedColumnWidth(cellWidth) : const FlexColumnWidth(),
      columnWidths: const {0: FixedColumnWidth(92)},
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(decoration: BoxDecoration(color: scheme.primary), children: [
          Padding(padding: const EdgeInsets.all(6), child: Text('Horaires', style: head, textAlign: TextAlign.center)),
          for (final d in tt.days)
            Padding(padding: const EdgeInsets.all(6), child: Text(weekDays[d - 1], style: head, textAlign: TextAlign.center)),
        ]),
        for (var i = 0; i < tt.slots.length; i++)
          TableRow(
            decoration: tt.slots[i].isBreak ? BoxDecoration(color: scheme.surfaceContainerHighest) : null,
            children: [
              Padding(
                padding: const EdgeInsets.all(4),
                child: Text(tt.slots[i].text,
                    textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
              for (final d in tt.days)
                SizedBox(
                  height: tt.slots[i].isBreak ? 24 : cellHeight,
                  child: tt.slots[i].isBreak
                      ? Center(
                          child: Text(tt.slots[i].label.isEmpty ? 'Pause' : tt.slots[i].label,
                              style: const TextStyle(fontSize: 11, color: Colors.black54)))
                      : tt.closed.contains('$d|$i')
                          ? Container(color: const Color(0xFFE0E0E0))
                          : cell('$d|$i'),
                ),
            ],
          ),
      ],
    );
    return width == null ? table : SizedBox(width: width, child: table);
  }
}

class _LessonCell extends StatelessWidget {
  final String title;
  final String sub;
  final int color;
  final bool locked;
  final bool conflict;
  const _LessonCell({required this.title, required this.sub, required this.color, this.locked = false, this.conflict = false});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Color(color),
          border: conflict ? Border.all(color: Colors.red, width: 2.5) : null,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
        child: Stack(children: [
          LayoutBuilder(
            builder: (context, box) => Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: SizedBox(
                  width: box.maxWidth,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Colors.black87)),
                    if (sub.isNotEmpty)
                      Text(sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 10, color: Colors.black54)),
                  ]),
                ),
              ),
            ),
          ),
          if (locked) const Positioned(right: 0, top: 0, child: Icon(Icons.push_pin, size: 11, color: Colors.black45)),
        ]),
      );
}

class _TimetableTab extends StatefulWidget {
  const _TimetableTab();

  @override
  State<_TimetableTab> createState() => _TimetableTabState();
}

class _TimetableTabState extends State<_TimetableTab> {
  bool _byTeacher = false;
  String? _class;
  String? _teacher;
  bool _busy = false;
  List<String> _unplaced = [];

  Future<void> _generate(SchoolController ctrl) async {
    final gb = ctrl.book;
    final classes = ctrl.classNames.where((c) => gb.classes[c]?.subjects.any((s) => s.hours > 0) ?? false).toList();
    if (classes.isEmpty) {
      toast(context, 'Ajoutez d\'abord des matières avec des heures par semaine dans vos classes.', error: true);
      return;
    }
    if (gb.timetable.values.any((m) => m.isNotEmpty) &&
        !await confirm(context, 'Générer l\'emploi du temps ?',
            'Les séances actuelles seront replacées, sauf celles épinglées à la main.',
            ok: 'Générer')) {
      return;
    }
    setState(() => _busy = true);
    await Future.delayed(const Duration(milliseconds: 50));
    final r = generateTimetable(gb, classes);
    gb.timetable = r.table;
    ctrl.changed();
    setState(() {
      _busy = false;
      _unplaced = r.unplaced;
    });
    if (!mounted) return;
    final noTeacher = gb.classes.values.fold(0, (a, c) => a + c.subjects.where((s) => s.hours > 0 && s.teacherId == null).length);
    toast(
        context,
        r.unplaced.isEmpty
            ? 'Emploi du temps généré pour ${classes.length} classe(s), sans conflit.'
                '${noTeacher > 0 ? ' Attention : $noTeacher matière(s) sans professeur.' : ''}'
            : '${r.unplaced.length} séance(s) n\'ont pas trouvé de place : voir la liste.',
        error: r.unplaced.isNotEmpty);
  }

  Future<void> _editCell(SchoolController ctrl, String cls, String slot) async {
    final c = ctrl.classOf(cls);
    final t = ctrl.book.timetable.putIfAbsent(cls, () => {});
    final cur = t[slot];
    final cover = classCoverage(ctrl.book, cls);
    final busy = <String>{}; // professeurs occupés à ce créneau dans d'autres classes
    for (final e in ctrl.book.timetable.entries) {
      if (e.key == cls) continue;
      final l = e.value[slot];
      if (l == null) continue;
      final s = ctrl.book.classes[e.key]?.subjects.where((x) => x.id == l.subjectId).firstOrNull;
      if (s?.teacherId != null) busy.add(s!.teacherId!);
    }
    final parts = slot.split('|');
    final label = '${weekDays[int.parse(parts[0]) - 1]} ${ctrl.book.tt.slots[int.parse(parts[1])].text}';
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (d) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(d).height * 0.75),
          child: ListView(shrinkWrap: true, children: [
            ListTile(title: Text('$cls · $label', style: const TextStyle(fontWeight: FontWeight.w700))),
            if (cur != null) ...[
              ListTile(
                leading: Icon(cur.locked ? Icons.push_pin_outlined : Icons.push_pin),
                title: Text(cur.locked ? 'Ne plus épingler' : 'Épingler (garder à la régénération)'),
                onTap: () => Navigator.pop(d, '#lock'),
              ),
              ListTile(
                leading: const Icon(Icons.clear),
                title: const Text('Vider le créneau'),
                onTap: () => Navigator.pop(d, '#clear'),
              ),
              const Divider(),
            ],
            for (var i = 0; i < c.subjects.length; i++)
              if (!c.subjects[i].conduct)
                Builder(builder: (context) {
                  final s = c.subjects[i];
                  final (planned, placed) = cover[s.id] ?? (0, 0);
                  final conflict = s.teacherId != null && busy.contains(s.teacherId);
                  return ListTile(
                    leading: CircleAvatar(radius: 12, backgroundColor: Color(subjectColor(s.name, index: i))),
                    title: Text(s.name),
                    subtitle: Text([
                      if (ctrl.book.teacherName(s).isNotEmpty) ctrl.book.teacherName(s),
                      '$placed/$planned h placées',
                      if (conflict) 'professeur déjà occupé à cette heure',
                    ].join(' · ')),
                    trailing: conflict ? const Icon(Icons.warning_amber, color: Colors.orange) : null,
                    onTap: () => Navigator.pop(d, s.id),
                  );
                }),
          ]),
        ),
      ),
    );
    if (choice == null) return;
    if (choice == '#clear') {
      t.remove(slot);
    } else if (choice == '#lock') {
      cur?.locked = !(cur.locked);
    } else {
      t[slot] = Lesson(choice, locked: true);
    }
    ctrl.changed();
  }

  Future<void> _pdf(SchoolController ctrl, {required bool allClasses, required bool teachers}) async {
    setState(() => _busy = true);
    try {
      final gb = ctrl.book;
      final classes = teachers ? <String>[] : (allClasses ? ctrl.classNames : [_class!]);
      final tl = !teachers
          ? <Teacher>[]
          : (allClasses ? gb.teachers : gb.teachers.where((t) => t.id == _teacher).toList());
      final bytes = await buildTimetablePdf(gb: gb, school: ctrl.app.school, classes: classes, teachers: tl);
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Emploi du temps')),
          body: PdfPreview(
            build: (_) async => bytes,
            pdfFileName: 'emploi_du_temps.pdf',
            canChangeOrientation: false,
            canChangePageFormat: false,
            canDebug: false,
          ),
        ),
      ));
    } catch (e) {
      if (mounted) toast(context, 'Échec : $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = SchoolScope.of(context);
    final gb = ctrl.book;
    final classes = ctrl.classNames;
    if (_class == null || !classes.contains(_class)) _class = classes.isEmpty ? null : classes.first;
    if (_teacher == null || gb.teacher(_teacher) == null) _teacher = gb.teachers.isEmpty ? null : gb.teachers.first.id;
    final conflicts = findConflicts(gb);
    final conflictSlots = {for (final c in conflicts) for (final cl in c.classes) '$cl|${c.slot}'};

    Widget grid;
    if (_byTeacher) {
      if (_teacher == null) {
        grid = const Padding(padding: EdgeInsets.all(24), child: Text('Ajoutez des professeurs (onglet Professeurs).'));
      } else {
        final sched = teacherSchedule(gb, _teacher!);
        grid = _SlotGrid.fit(
          gb.tt,
          (slot) {
            final e = sched[slot];
            if (e == null) return const SizedBox();
            final cls = gb.classes[e.$1];
            return _LessonCell(
              title: e.$2.name,
              sub: e.$1,
              color: subjectColor(e.$2.name, index: cls?.subjects.indexOf(e.$2)),
              conflict: conflictSlots.contains('${e.$1}|$slot'),
            );
          },
        );
      }
    } else if (_class == null) {
      grid = const Padding(padding: EdgeInsets.all(24), child: Text('Créez d\'abord vos classes (onglet Classes).'));
    } else {
      final c = ctrl.classOf(_class!);
      final t = gb.timetable[_class!] ?? {};
      grid = _SlotGrid.fit(
        gb.tt,
        (slot) {
          final l = t[slot];
          final s = l == null ? null : c.subjects.where((x) => x.id == l.subjectId).firstOrNull;
          return InkWell(
            onTap: () => _editCell(ctrl, _class!, slot),
            child: s == null
                ? const Center(child: Icon(Icons.add, size: 16, color: Colors.black26))
                : _LessonCell(
                    title: s.name,
                    sub: gb.teacherName(s),
                    color: subjectColor(s.name, index: c.subjects.indexOf(s)),
                    locked: l!.locked,
                    conflict: conflictSlots.contains('${_class!}|$slot'),
                  ),
          );
        },
      );
    }

    final coverage = _class == null || _byTeacher ? null : classCoverage(gb, _class!);
    final missing = coverage == null
        ? <String>[]
        : [
            for (final e in coverage.entries)
              if (e.value.$2 < e.value.$1)
                '${ctrl.classOf(_class!).subjects.firstWhere((s) => s.id == e.key).name} (${e.value.$1 - e.value.$2} h)',
          ];

    return ListView(padding: const EdgeInsets.all(16), children: [
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        FilledButton.icon(
          onPressed: _busy ? null : () => _generate(ctrl),
          icon: _busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.auto_fix_high),
          label: const Text('Générer automatiquement'),
        ),
        MenuAnchor(
          builder: (c, m, _) => OutlinedButton.icon(
            onPressed: _busy ? null : () => m.isOpen ? m.close() : m.open(),
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('Imprimer (PDF)'),
          ),
          menuChildren: [
            if (_class != null)
              MenuItemButton(onPressed: () => _pdf(ctrl, allClasses: false, teachers: false), child: Text('Classe $_class')),
            MenuItemButton(onPressed: () => _pdf(ctrl, allClasses: true, teachers: false), child: const Text('Toutes les classes')),
            if (_teacher != null)
              MenuItemButton(
                  onPressed: () => _pdf(ctrl, allClasses: false, teachers: true),
                  child: Text('Professeur ${gb.teacher(_teacher)?.name ?? ''}')),
            if (gb.teachers.isNotEmpty)
              MenuItemButton(onPressed: () => _pdf(ctrl, allClasses: true, teachers: true), child: const Text('Tous les professeurs')),
          ],
        ),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TimetableSettingsPage())),
          icon: const Icon(Icons.schedule),
          label: const Text('Jours et horaires'),
        ),
      ]),
      const SizedBox(height: 12),
      Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, icon: Icon(Icons.class_outlined), label: Text('Par classe')),
            ButtonSegment(value: true, icon: Icon(Icons.person_outline), label: Text('Par professeur')),
          ],
          selected: {_byTeacher},
          onSelectionChanged: (v) => setState(() => _byTeacher = v.first),
        ),
        if (!_byTeacher && classes.isNotEmpty)
          DropdownButton<String>(
            value: _class,
            items: [for (final c in classes) DropdownMenuItem(value: c, child: Text(c))],
            onChanged: (v) => setState(() => _class = v),
          ),
        if (_byTeacher && gb.teachers.isNotEmpty)
          DropdownButton<String>(
            value: _teacher,
            items: [for (final t in gb.teachers) DropdownMenuItem(value: t.id, child: Text(t.name))],
            onChanged: (v) => setState(() => _teacher = v),
          ),
      ]),
      const SizedBox(height: 8),
      if (conflicts.isNotEmpty)
        Card(
          color: Theme.of(context).colorScheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Text('${conflicts.length} conflit(s) : un professeur a deux classes au même moment (cases encadrées en rouge).'),
          ),
        ),
      if (_unplaced.isNotEmpty)
        Card(
          color: Theme.of(context).colorScheme.tertiaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Text('Séances non placées : ${_unplaced.join(' ; ')}.\n'
                'Ajoutez des créneaux, réduisez les heures, ou vérifiez les disponibilités des professeurs.'),
          ),
        ),
      if (missing.isNotEmpty && gb.timetable.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text('Encore à placer : ${missing.join(', ')}', style: Theme.of(context).textTheme.bodySmall),
        ),
      if (!_byTeacher)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text('Touchez une case pour choisir la matière à la main (elle est alors épinglée).',
              style: Theme.of(context).textTheme.bodySmall),
        ),
      grid,
    ]);
  }
}

/// Jours de cours, créneaux horaires, pauses et créneaux fermés.
class TimetableSettingsPage extends StatefulWidget {
  const TimetableSettingsPage({super.key});

  @override
  State<TimetableSettingsPage> createState() => _TimetableSettingsPageState();
}

class _TimetableSettingsPageState extends State<TimetableSettingsPage> {
  Future<String?> _time(String initial) async {
    final p = initial.split(':');
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: int.tryParse(p.first) ?? 8, minute: int.tryParse(p.length > 1 ? p[1] : '0') ?? 0),
      builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (t == null) return null;
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = SchoolScope.of(context);
    final tt = ctrl.book.tt;
    void save() {
      ctrl.changed();
      setState(() {});
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Jours et horaires')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Section(title: 'Jours de cours', children: [
          Wrap(spacing: 6, children: [
            for (var d = 1; d <= 6; d++)
              FilterChip(
                label: Text(weekDays[d - 1]),
                selected: tt.days.contains(d),
                onSelected: (v) {
                  v ? tt.days.add(d) : tt.days.remove(d);
                  tt.days.sort();
                  save();
                },
              ),
          ]),
        ]),
        const SizedBox(height: 12),
        Section(
          title: 'Créneaux de la journée',
          subtitle: 'Une séance = un créneau. Les pauses ne reçoivent pas de cours.',
          trailing: TextButton(
            onPressed: () async {
              if (await confirm(context, 'Horaires par défaut ?',
                  '7h–12h15 avec récréation, puis 15h–17h ; mercredi après-midi libre.', ok: 'Appliquer')) {
                ctrl.book.tt = TimetableSettings(days: tt.days);
                save();
              }
            },
            child: const Text('Par défaut'),
          ),
          children: [
            for (var i = 0; i < tt.slots.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  OutlinedButton(
                    onPressed: () async {
                      final v = await _time(tt.slots[i].start);
                      if (v != null) {
                        tt.slots[i].start = v;
                        save();
                      }
                    },
                    child: Text(tt.slots[i].start),
                  ),
                  const Text('  –  '),
                  OutlinedButton(
                    onPressed: () async {
                      final v = await _time(tt.slots[i].end);
                      if (v != null) {
                        tt.slots[i].end = v;
                        save();
                      }
                    },
                    child: Text(tt.slots[i].end),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: const Text('Pause'),
                    selected: tt.slots[i].isBreak,
                    onSelected: (v) {
                      tt.slots[i].isBreak = v;
                      if (v && tt.slots[i].label.isEmpty) tt.slots[i].label = 'Récréation';
                      save();
                    },
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Supprimer',
                    onPressed: tt.slots.length <= 1
                        ? null
                        : () {
                            tt.slots.removeAt(i);
                            // Les créneaux fermés suivants se décalent d'un rang.
                            tt.closed = {
                              for (final k in tt.closed)
                                if (int.parse(k.split('|')[1]) != i)
                                  int.parse(k.split('|')[1]) > i ? '${k.split('|')[0]}|${int.parse(k.split('|')[1]) - 1}' : k,
                            };
                            save();
                          },
                    icon: const Icon(Icons.delete_outline),
                  ),
                ]),
              ),
            TextButton.icon(
              onPressed: () {
                final last = tt.slots.isEmpty ? null : tt.slots.last;
                tt.slots.add(TimeSlot(last?.end ?? '08:00', last == null ? '09:00' : _plusHour(last.end)));
                save();
              },
              icon: const Icon(Icons.add),
              label: const Text('Ajouter un créneau'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Section(
          title: 'Créneaux fermés',
          subtitle: 'Touchez une case pour la fermer à toutes les classes (ex. mercredi après-midi).',
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Table(
                border: TableBorder.all(color: Theme.of(context).colorScheme.outlineVariant),
                defaultColumnWidth: const FixedColumnWidth(96),
                columnWidths: const {0: FixedColumnWidth(92)},
                children: [
                  TableRow(children: [
                    const SizedBox(),
                    for (final d in tt.days)
                      Padding(padding: const EdgeInsets.all(6), child: Text(weekDays[d - 1], textAlign: TextAlign.center)),
                  ]),
                  for (var i = 0; i < tt.slots.length; i++)
                    if (!tt.slots[i].isBreak)
                      TableRow(children: [
                        Padding(padding: const EdgeInsets.all(6), child: Text(tt.slots[i].text, style: const TextStyle(fontSize: 12))),
                        for (final d in tt.days)
                          InkWell(
                            onTap: () {
                              final k = '$d|$i';
                              tt.closed.contains(k) ? tt.closed.remove(k) : tt.closed.add(k);
                              save();
                            },
                            child: Container(
                              height: 34,
                              color: tt.closed.contains('$d|$i') ? const Color(0xFFBDBDBD) : const Color(0xFFE8F5E9),
                              alignment: Alignment.center,
                              child: Text(tt.closed.contains('$d|$i') ? 'Fermé' : 'Cours',
                                  style: const TextStyle(fontSize: 11)),
                            ),
                          ),
                      ]),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text('${tt.usable().length} créneaux de cours par semaine.',
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      ]),
    );
  }

  static String _plusHour(String t) {
    final p = t.split(':');
    final h = ((int.tryParse(p.first) ?? 8) + 1) % 24;
    return '${h.toString().padLeft(2, '0')}:${p.length > 1 ? p[1] : '00'}';
  }
}
