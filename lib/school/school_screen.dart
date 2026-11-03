import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';

import '../app_state.dart';
import '../card_kinds.dart';
import '../services/license.dart';
import '../widgets/common.dart';
import 'bulletin_pdf.dart';
import 'school_controller.dart';
import 'school_engine.dart';
import 'school_export.dart';
import 'school_models.dart';

/// Onglet « Notes et bulletins » de l'espace établissement.
class SchoolScreen extends StatefulWidget {
  const SchoolScreen({super.key});

  @override
  State<SchoolScreen> createState() => _SchoolScreenState();
}

class _SchoolScreenState extends State<SchoolScreen> {
  String? _class;
  String? _period;

  @override
  Widget build(BuildContext context) {
    final ctrl = SchoolScope.of(context);
    AppScope.of(context);
    if (!ctrl.loaded) return const Center(child: CircularProgressIndicator());
    final classes = ctrl.classNames;
    if (classes.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.school_outlined, size: 56),
            SizedBox(height: 12),
            Text('Ajoutez d\'abord vos élèves avec leur classe (onglet Élèves, ou import Excel).',
                textAlign: TextAlign.center),
            SizedBox(height: 6),
            Text('Les classes, matières, notes et bulletins se gèrent ensuite ici.', textAlign: TextAlign.center),
          ]),
        ),
      );
    }
    final periods = ctrl.book.settings.periods;
    if (_class == null || !classes.contains(_class)) _class = classes.first;
    if (periods.isNotEmpty && (_period == null || ctrl.book.settings.period(_period!) == null)) _period = periods.first.id;
    final sel = _Selection(
      className: _class!,
      period: _period == null ? null : ctrl.book.settings.period(_period!),
      onClass: (c) => setState(() => _class = c),
      onPeriod: (p) => setState(() => _period = p),
    );
    return DefaultTabController(
      length: 5,
      child: Column(children: [
        Material(
          color: Theme.of(context).colorScheme.surface,
          child: const TabBar(isScrollable: true, tabAlignment: TabAlignment.center, tabs: [
            Tab(icon: Icon(Icons.class_outlined), text: 'Classes et matières'),
            Tab(icon: Icon(Icons.edit_note), text: 'Saisie des notes'),
            Tab(icon: Icon(Icons.leaderboard_outlined), text: 'Résultats'),
            Tab(icon: Icon(Icons.description_outlined), text: 'Bulletins'),
            Tab(icon: Icon(Icons.tune), text: 'Réglages'),
          ]),
        ),
        Expanded(
          child: TabBarView(physics: const NeverScrollableScrollPhysics(), children: [
            _ClassesTab(sel: sel),
            _GradesTab(sel: sel),
            _ResultsTab(sel: sel),
            _BulletinsTab(sel: sel),
            const _SettingsTab(),
          ]),
        ),
      ]),
    );
  }
}

/// Classe et période choisies, partagées par les onglets.
class _Selection {
  final String className;
  final Period? period;
  final ValueChanged<String> onClass;
  final ValueChanged<String> onPeriod;
  const _Selection({required this.className, required this.period, required this.onClass, required this.onPeriod});
}

Widget _classPicker(BuildContext context, _Selection sel, {bool withCounts = true}) {
  final ctrl = SchoolScope.of(context);
  return DropdownButton<String>(
    value: sel.className,
    items: [
      for (final c in ctrl.classNames)
        DropdownMenuItem(
            value: c, child: Text(withCounts ? '$c (${ctrl.studentsOf(c).length})' : c)),
    ],
    onChanged: (v) => v == null ? null : sel.onClass(v),
  );
}

Widget _periodPicker(BuildContext context, _Selection sel) {
  final ctrl = SchoolScope.of(context);
  return Wrap(spacing: 6, runSpacing: 6, children: [
    for (final p in ctrl.book.settings.periods)
      ChoiceChip(label: Text(p.name), selected: sel.period?.id == p.id, onSelected: (_) => sel.onPeriod(p.id)),
  ]);
}

String _n(double v) => v == v.roundToDouble() ? v.toInt().toString() : fmt(v);

// =====================================================================
// Classes et matières
// =====================================================================

class _ClassesTab extends StatelessWidget {
  final _Selection sel;
  const _ClassesTab({required this.sel});

  Future<void> _editSubject(BuildContext context, SchoolController ctrl, ClassConfig cls, Subject? existing) async {
    final s = existing?.copy() ?? Subject(name: '');
    final name = TextEditingController(text: s.name);
    final coef = TextEditingController(text: _n(s.coef));
    final max = TextEditingController(text: s.max == null ? '' : _n(s.max!));
    final teacher = TextEditingController(text: s.teacher);
    var conduct = s.conduct;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: Text(existing == null ? 'Nouvelle matière' : 'Modifier la matière'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'Matière')),
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
                    controller: max,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: 'Noté sur', hintText: _n(cls.scale)),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              TextField(controller: teacher, decoration: const InputDecoration(labelText: 'Professeur (facultatif)')),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: conduct,
                onChanged: (v) => set(() => conduct = v ?? false),
                title: const Text('Matière « Conduite »'),
                subtitle: const Text('Reçoit la retenue pour absences non justifiées'),
              ),
            ]),
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
      ..max = parseNote(max.text)
      ..teacher = teacher.text.trim()
      ..conduct = conduct;
    if (existing == null) {
      cls.subjects.add(s);
    } else {
      cls.subjects[cls.subjects.indexWhere((e) => e.id == existing.id)] = s;
    }
    ctrl.changed();
  }

  Future<void> _copyTo(BuildContext context, SchoolController ctrl, ClassConfig cls) async {
    final others = ctrl.classNames.where((c) => c != cls.name).toList();
    if (others.isEmpty) return;
    final picked = <String>{};
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: Text('Copier les matières de ${cls.name}'),
          content: SizedBox(
            width: 380,
            child: ListView(shrinkWrap: true, children: [
              const Text('Les matières, coefficients et barème remplacent ceux des classes cochées. '
                  'Les notes déjà saisies dans ces classes ne seront plus rattachées.'),
              const SizedBox(height: 8),
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
        ..subjects = cls.subjects.map((e) => e.copy(newId: true)).toList();
    }
    ctrl.changed();
    if (context.mounted) toast(context, 'Matières copiées vers ${picked.length} classe(s).');
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = SchoolScope.of(context);
    final cls = ctrl.classOf(sel.className);
    return ListView(padding: const EdgeInsets.all(16), children: [
      Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        const Text('Classe :'),
        _classPicker(context, sel),
        Text('${ctrl.studentsOf(cls.name).length} élèves', style: Theme.of(context).textTheme.bodySmall),
      ]),
      const SizedBox(height: 12),
      Section(
        title: 'Classe ${cls.name}',
        subtitle: 'Barème, titulaire et matières avec leurs coefficients',
        children: [
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
          TextSetting(
            key: ValueKey('tit-${cls.name}'),
            label: cls.scale == 10 ? 'Maître / maîtresse de la classe' : 'Professeur principal (titulaire)',
            value: cls.titulaire,
            onChanged: (v) {
              cls.titulaire = v;
              ctrl.changed();
            },
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(
              onPressed: () => _editSubject(context, ctrl, cls, null),
              icon: const Icon(Icons.add),
              label: const Text('Ajouter une matière'),
            ),
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
                              'Les ${cls.subjects.length} matières de ${cls.name} seront remplacées par « ${p.name} ».',
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
          const SizedBox(height: 12),
          if (cls.subjects.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Aucune matière. Ajoutez-les une par une ou choisissez un programme prêt à l\'emploi.'),
            )
          else ...[
            for (var i = 0; i < cls.subjects.length; i++)
              Builder(builder: (context) {
                final m = cls.subjects[i];
                return Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: ListTile(
                    leading: CircleAvatar(child: Text(_n(m.coef))),
                    title: Text(m.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text([
                      'Coef ${_n(m.coef)}',
                      'sur ${_n(cls.maxOf(m))}',
                      if (m.teacher.isNotEmpty) m.teacher,
                      if (m.conduct) 'Conduite (retenue absences)',
                    ].join(' · ')),
                    onTap: () => _editSubject(context, ctrl, cls, m),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        tooltip: 'Monter',
                        onPressed: i == 0
                            ? null
                            : () {
                                cls.subjects.insert(i - 1, cls.subjects.removeAt(i));
                                ctrl.changed();
                              },
                        icon: const Icon(Icons.arrow_upward),
                      ),
                      IconButton(
                        tooltip: 'Supprimer',
                        onPressed: () async {
                          if (await confirm(context, 'Supprimer « ${m.name} » ?',
                              'Les notes déjà saisies pour cette matière ne seront plus comptées.',
                              ok: 'Supprimer')) {
                            cls.subjects.removeAt(i);
                            ctrl.changed();
                          }
                        },
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ]),
                  ),
                );
              }),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Total des coefficients : ${_n(cls.coefTotal)}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ],
      ),
    ]);
  }
}

// =====================================================================
// Saisie des notes
// =====================================================================

class _GradesTab extends StatefulWidget {
  final _Selection sel;
  const _GradesTab({required this.sel});

  @override
  State<_GradesTab> createState() => _GradesTabState();
}

class _GradesTabState extends State<_GradesTab> {
  String? _subject;
  final Map<String, TextEditingController> _ctrls = {};
  final Map<String, FocusNode> _focus = {};
  String _key = '';

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    for (final f in _focus.values) {
      f.dispose();
    }
    super.dispose();
  }

  void _reset() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    for (final f in _focus.values) {
      f.dispose();
    }
    _ctrls.clear();
    _focus.clear();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = SchoolScope.of(context);
    final sel = widget.sel;
    final cls = ctrl.classOf(sel.className);
    final p = sel.period;
    final evals = ctrl.book.settings.evals;
    if (cls.subjects.isEmpty) {
      return ListView(padding: const EdgeInsets.all(16), children: [
        Wrap(spacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [const Text('Classe :'), _classPicker(context, sel)]),
        const SizedBox(height: 24),
        const Center(child: Text('Définissez d\'abord les matières de cette classe (onglet « Classes et matières »).')),
      ]);
    }
    if (_subject == null || !cls.subjects.any((m) => m.id == _subject)) _subject = cls.subjects.first.id;
    final m = cls.subjects.firstWhere((x) => x.id == _subject);
    final max = cls.maxOf(m);
    final students = ctrl.studentsOf(cls.name);
    final key = '${cls.name}|${p?.id}|${m.id}';
    if (key != _key) {
      _reset();
      _key = key;
    }
    TextEditingController ctl(String sid, String eid) => _ctrls.putIfAbsent('$sid|$eid', () {
          final v = p == null ? null : ctrl.book.note(p.id, sid, m.id, eid);
          return TextEditingController(text: v == null ? '' : _n(v));
        });
    FocusNode focus(int row, int col) => _focus.putIfAbsent('$row|$col', () => FocusNode());

    final avgs = <double>[];
    for (final s in students) {
      final a = p == null
          ? null
          : weightedMean({for (final e in evals) e.id: ctrl.book.note(p.id, s.id, m.id, e.id)}, evals);
      if (a != null) avgs.add(a);
    }
    final classAvg = avgs.isEmpty ? null : avgs.reduce((a, b) => a + b) / avgs.length;

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            const Text('Classe :'),
            _classPicker(context, sel),
            _periodPicker(context, sel),
          ]),
          const SizedBox(height: 8),
          SizedBox(
            height: 40,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (final x in cls.subjects)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(x.name),
                    selected: x.id == m.id,
                    onSelected: (_) => setState(() => _subject = x.id),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 6),
          Text(
            '${m.name} · coef ${_n(m.coef)} · notes sur ${_n(max)}'
            '${classAvg == null ? '' : ' · moyenne de la classe ${fmt(classAvg)}'}'
            '${m.conduct ? ' · la retenue pour absences s\'applique au calcul' : ''}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ]),
      ),
      const Divider(height: 1),
      if (p == null)
        const Expanded(child: Center(child: Text('Ajoutez une période dans les réglages.')))
      else if (students.isEmpty)
        const Expanded(child: Center(child: Text('Aucun élève dans cette classe.')))
      else
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            itemCount: students.length + 1,
            itemBuilder: (context, i) {
              // Sur téléphone : le nom au-dessus, les cases de notes en dessous sur toute la largeur.
              final narrow = MediaQuery.sizeOf(context).width < 600;
              Widget cellBox(Widget child) => narrow
                  ? Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 3), child: child))
                  : Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: SizedBox(width: 76, child: child));
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(children: [
                    if (!narrow) ...[
                      const SizedBox(width: 34, child: Text('N°', style: TextStyle(fontWeight: FontWeight.w700))),
                      const Expanded(child: Text('Élève', style: TextStyle(fontWeight: FontWeight.w700))),
                    ],
                    for (final e in evals)
                      cellBox(Text('${e.name}${e.weight != 1 ? ' ×${_n(e.weight)}' : ''}',
                          textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700))),
                    const SizedBox(
                        width: 70,
                        child: Text('Moy.', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700))),
                  ]),
                );
              }
              final row = i - 1;
              final s = students[row];
              final avg = weightedMean({for (final e in evals) e.id: ctrl.book.note(p.id, s.id, m.id, e.id)}, evals);
              final cells = Row(children: [
                  if (!narrow) ...[
                    SizedBox(width: 34, child: Text('${row + 1}')),
                    Expanded(child: Text(s.fullName, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ],
                  for (var col = 0; col < evals.length; col++)
                    cellBox(Builder(builder: (context) {
                          final e = evals[col];
                          final c = ctl(s.id, e.id);
                          final v = parseNote(c.text);
                          final bad = c.text.trim().isNotEmpty && (v == null || v < 0 || v > max);
                          return TextField(
                            controller: c,
                            focusNode: focus(row, col),
                            textAlign: TextAlign.center,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              isDense: true,
                              hintText: '—',
                              errorText: bad ? '> ${_n(max)}' : null,
                              errorStyle: const TextStyle(fontSize: 0, height: 0),
                            ),
                            onChanged: (t) {
                              final x = parseNote(t);
                              if (t.trim().isEmpty) {
                                ctrl.book.setNote(p.id, s.id, m.id, e.id, null);
                              } else if (x != null && x >= 0 && x <= max) {
                                ctrl.book.setNote(p.id, s.id, m.id, e.id, x);
                              }
                              ctrl.changed();
                            },
                            onSubmitted: (_) {
                              // Entrée : passe à l'élève suivant, même colonne.
                              final next = row + 1 < students.length ? focus(row + 1, col) : focus(0, (col + 1) % evals.length);
                              next.requestFocus();
                            },
                          );
                        })),
                  SizedBox(
                    width: 70,
                    child: Text(fmt(avg),
                        textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ]);
              return Padding(
                padding: EdgeInsets.only(bottom: narrow ? 10 : 4),
                child: narrow
                    ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${row + 1}. ${s.fullName}', style: const TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        cells,
                      ])
                    : cells,
              );
            },
          ),
        ),
    ]);
  }
}

// =====================================================================
// Résultats
// =====================================================================

class _ResultsTab extends StatefulWidget {
  final _Selection sel;
  const _ResultsTab({required this.sel});

  @override
  State<_ResultsTab> createState() => _ResultsTabState();
}

class _ResultsTabState extends State<_ResultsTab> {
  String? _counted;
  bool _annual = false;

  void _ensureAbsences(SchoolController ctrl, Period? p) {
    if (p == null || _counted == p.id) return;
    _counted = p.id;
    WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.refreshAbsences(p));
  }

  Future<void> _editStudent(BuildContext context, SchoolController ctrl, StudentResult r, Period p) async {
    final man = ctrl.book.manualAbsences(p.id, r.student.id);
    final auto = ctrl.autoAbsences(p.id)[r.student.id] ?? AbsenceCount();
    final j = TextEditingController(text: '${man.justified}');
    final u = TextEditingController(text: '${man.unjustified}');
    final l = TextEditingController(text: '${man.lates}');
    final council = TextEditingController(text: ctrl.book.council[p.id]?[r.student.id] ?? '');
    final last = ctrl.book.settings.periods.isNotEmpty && ctrl.book.settings.periods.last.id == p.id;
    final decision = TextEditingController(text: ctrl.book.decisions[r.student.id] ?? '');
    Widget num(TextEditingController c, String label) => Expanded(
          child: TextField(
            controller: c,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(labelText: label),
          ),
        );
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(r.student.fullName),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Absences du pointage (${p.name}) : ${auto.justified} justifiée(s), ${auto.unjustified} non justifiée(s), '
                  '${auto.lates} retard(s).'),
              const SizedBox(height: 8),
              const Text('Absences à ajouter (saisie manuelle) :', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Row(children: [num(j, 'Justifiées'), const SizedBox(width: 8), num(u, 'Non justifiées'), const SizedBox(width: 8), num(l, 'Retards')]),
              const SizedBox(height: 14),
              TextField(
                controller: council,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Appréciation du conseil de classe'),
              ),
              if (last) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: decision,
                  decoration: const InputDecoration(
                    labelText: 'Décision de fin d\'année',
                    hintText: 'Vide = automatique (admis / redouble selon la moyenne)',
                  ),
                ),
              ],
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Enregistrer')),
        ],
      ),
    );
    if (ok != true) return;
    ctrl.book.setManualAbsences(
        p.id,
        r.student.id,
        AbsenceCount(
          justified: int.tryParse(j.text) ?? 0,
          unjustified: int.tryParse(u.text) ?? 0,
          lates: int.tryParse(l.text) ?? 0,
        ));
    final t = council.text.trim();
    if (t.isEmpty) {
      ctrl.book.council[p.id]?.remove(r.student.id);
    } else {
      ctrl.book.council.putIfAbsent(p.id, () => {})[r.student.id] = t;
    }
    if (last) {
      final dec = decision.text.trim();
      if (dec.isEmpty) {
        ctrl.book.decisions.remove(r.student.id);
      } else {
        ctrl.book.decisions[r.student.id] = dec;
      }
    }
    ctrl.changed();
  }

  Future<void> _exportExcel(BuildContext context, SchoolController ctrl, ClassResults res) async {
    try {
      final bytes = buildResultsExcel(res, ctrl.app.school, ctrl.book.settings, trial: LicenseScope.watermarkOf(context, bulletinModule));
      final name = 'resultats_${res.cls.name}_${res.period.name}'.replaceAll(RegExp(r'[^\w-]+'), '_');
      final uri = await FilePicker.saveFile(
        dialogTitle: 'Enregistrer les résultats',
        fileName: '$name.xlsx',
        bytes: bytes,
        mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      if (uri != null && context.mounted) toast(context, 'Résultats enregistrés.');
    } catch (e) {
      if (context.mounted) toast(context, 'Export impossible : $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = SchoolScope.of(context);
    final sel = widget.sel;
    final p = sel.period;
    final cls = ctrl.classOf(sel.className);
    _ensureAbsences(ctrl, p);
    final head = Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
      const Text('Classe :'),
      _classPicker(context, sel),
      _periodPicker(context, sel),
      FilterChip(label: const Text('Année complète'), selected: _annual, onSelected: (v) => setState(() => _annual = v)),
    ]);
    if (p == null || cls.subjects.isEmpty) {
      return ListView(padding: const EdgeInsets.all(16), children: [
        head,
        const SizedBox(height: 24),
        const Center(child: Text('Définissez les matières de la classe et au moins une période.')),
      ]);
    }
    if (_annual) {
      final an = ctrl.annual(cls.name)..sort((a, b) => (a.rank == 0 ? 9999 : a.rank ?? 9999).compareTo(b.rank == 0 ? 9999 : b.rank ?? 9999));
      final periods = ctrl.book.settings.periods;
      return ListView(padding: const EdgeInsets.all(16), children: [
        head,
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(columns: [
            const DataColumn(label: Text('Rang')),
            const DataColumn(label: Text('Élève')),
            for (final x in periods) DataColumn(label: Text(x.name), numeric: true),
            const DataColumn(label: Text('Moy. annuelle'), numeric: true),
            const DataColumn(label: Text('Décision')),
          ], rows: [
            for (final a in an)
              DataRow(cells: [
                DataCell(Text(ordinal(a.rank, female: isFemale(a.student), exAequo: a.exAequo))),
                DataCell(Text(a.student.fullName)),
                for (final x in periods) DataCell(Text(fmt(a.periodAverages[x.id]))),
                DataCell(Text(fmt(a.average), style: const TextStyle(fontWeight: FontWeight.w800))),
                DataCell(Text(a.decision)),
              ]),
          ]),
        ),
      ]);
    }
    final res = ctrl.results(cls.name, p);
    final rows = [...res.rows]..sort((a, b) => (a.rank == 0 ? 9999 : a.rank ?? 9999).compareTo(b.rank == 0 ? 9999 : b.rank ?? 9999));
    final scheme = Theme.of(context).colorScheme;
    Widget stat(String label, String value) => Container(
          width: 150,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ]),
        );
    final usesAttendance = ctrl.book.settings.useAttendance && p.start != null && p.end != null;
    return ListView(padding: const EdgeInsets.all(16), children: [
      head,
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        stat('Moyenne de la classe', '${fmt(res.classAverage)} / ${_n(cls.scale)}'),
        stat('Plus forte moyenne', fmt(res.best)),
        stat('Plus faible moyenne', fmt(res.worst)),
        stat('Moyenne ≥ ${_n(cls.scale / 2)}', '${res.passing} / ${res.ranked}'),
      ]),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(
          usesAttendance
              ? 'Absences : pointage du ${_date(p.start!)} au ${_date(p.end!)} + saisies manuelles.'
              : 'Absences : saisies manuelles (renseignez les dates de la période pour utiliser le pointage).',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (usesAttendance)
          TextButton.icon(
            onPressed: () => ctrl.refreshAbsences(p),
            icon: const Icon(Icons.refresh),
            label: const Text('Recompter'),
          ),
        OutlinedButton.icon(
          onPressed: () => _exportExcel(context, ctrl, res),
          icon: const Icon(Icons.table_view),
          label: const Text('Exporter en Excel'),
        ),
      ]),
      const SizedBox(height: 8),
      Text('Touchez un élève pour ajouter des absences, l\'appréciation du conseil ou la décision.',
          style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 8),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          showCheckboxColumn: false,
          columns: [
            const DataColumn(label: Text('Rang')),
            const DataColumn(label: Text('Élève')),
            for (final m in cls.subjects) DataColumn(label: Text(m.name), numeric: true),
            DataColumn(label: Text('Moy. /${_n(cls.scale)}'), numeric: true),
            const DataColumn(label: Text('Abs. J / NJ / Ret.')),
            const DataColumn(label: Text('Retenue')),
            const DataColumn(label: Text('Mention')),
          ],
          rows: [
            for (final r in rows)
              DataRow(
                onSelectChanged: (_) => _editStudent(context, ctrl, r, p),
                cells: [
                  DataCell(Text(ordinal(r.rank, female: isFemale(r.student), exAequo: r.exAequo))),
                  DataCell(Text(r.student.fullName)),
                  for (final s in r.subjects) DataCell(Text(fmt(s.onScale))),
                  DataCell(Text(fmt(r.average), style: const TextStyle(fontWeight: FontWeight.w800))),
                  DataCell(Text('${r.absences.justified} / ${r.absences.unjustified} / ${r.absences.lates}')),
                  DataCell(Text(_retenue(r))),
                  DataCell(Text(r.mention ?? '',
                      style: TextStyle(color: r.mentionPositive ? null : scheme.error, fontWeight: FontWeight.w600))),
                ],
              ),
          ],
        ),
      ),
    ]);
  }
}

String _retenue(StudentResult r) {
  final t = r.subjects.fold(0.0, (a, s) => a + s.penalty) + r.averagePenalty;
  return t == 0 ? '' : '−${fmt(t)} pt';
}

String _date(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

// =====================================================================
// Bulletins
// =====================================================================

class _BulletinsTab extends StatefulWidget {
  final _Selection sel;
  const _BulletinsTab({required this.sel});

  @override
  State<_BulletinsTab> createState() => _BulletinsTabState();
}

class _BulletinsTabState extends State<_BulletinsTab> {
  bool _allClasses = false;
  bool _busy = false;

  static const _colors = [0xFF1B4F8C, 0xFF0B6B3A, 0xFF8E1B2E, 0xFF1A237E, 0xFF37474F, 0xFFB25E00, 0xFF6A1B9A, 0xFF00695C];

  Future<void> _generate(BuildContext context, {String? onlyStudent}) async {
    final ctrl = SchoolScope.read(context);
    final p = widget.sel.period;
    if (p == null) return;
    final watermark = LicenseScope.watermarkOf(context, bulletinModule);
    setState(() => _busy = true);
    try {
      await ctrl.refreshAbsences(p);
      final st = ctrl.book.settings;
      final last = st.periods.isNotEmpty && st.periods.last.id == p.id;
      final classes = _allClasses ? ctrl.classNames : [widget.sel.className];
      final items = <BulletinData>[];
      for (final c in classes) {
        if (ctrl.classOf(c).subjects.isEmpty) continue;
        final res = ctrl.results(c, p);
        final annual = last && st.annualRecap && st.periods.length > 1 ? ctrl.annual(c) : null;
        for (final r in res.rows) {
          if (onlyStudent != null && r.student.id != onlyStudent) continue;
          items.add(BulletinData(r, res, st, annual: annual));
        }
      }
      if (items.isEmpty) {
        if (context.mounted) toast(context, 'Aucun bulletin : vérifiez les matières des classes.', error: true);
        return;
      }
      final bytes = await buildBulletinsPdf(
        items: items,
        school: ctrl.app.school,
        model: st.bulletinModel,
        primaryColor: st.bulletinColor,
        secondaryColor: Color.lerp(Color(st.bulletinColor), Colors.black, 0.35)!.toARGB32(),
        watermark: watermark,
      );
      if (!context.mounted) return;
      final name = 'bulletins_${p.name}_${_allClasses ? 'toutes_classes' : widget.sel.className}'.replaceAll(RegExp(r'[^\w-]+'), '_');
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text('${items.length} bulletin(s) – ${p.name}')),
          body: PdfPreview(
            build: (_) async => bytes,
            pdfFileName: '$name.pdf',
            canChangeOrientation: false,
            canChangePageFormat: false,
            canDebug: false,
          ),
        ),
      ));
    } catch (e) {
      if (context.mounted) toast(context, 'Échec de la génération : $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = SchoolScope.of(context);
    final st = ctrl.book.settings;
    final sel = widget.sel;
    final scheme = Theme.of(context).colorScheme;
    final students = ctrl.studentsOf(sel.className);
    return ListView(padding: const EdgeInsets.all(16), children: [
      Section(title: 'Modèle de bulletin', subtitle: 'Choisissez la présentation imprimée', children: [
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (final m in bulletinModels)
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                st.bulletinModel = m.id;
                ctrl.changed();
              },
              child: Container(
                width: 230,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: st.bulletinModel == m.id ? scheme.primary : scheme.outlineVariant,
                    width: st.bulletinModel == m.id ? 2.5 : 1,
                  ),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _ModelThumb(model: m.id, color: Color(st.bulletinColor)),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: Text(m.name, style: const TextStyle(fontWeight: FontWeight.w700))),
                    if (st.bulletinModel == m.id) Icon(Icons.check_circle, color: scheme.primary, size: 18),
                  ]),
                  Text(m.description, style: Theme.of(context).textTheme.bodySmall),
                ]),
              ),
            ),
        ]),
        const SizedBox(height: 12),
        const Text('Couleur'),
        const SizedBox(height: 6),
        Wrap(spacing: 8, children: [
          for (final c in _colors)
            InkWell(
              onTap: () {
                st.bulletinColor = c;
                ctrl.changed();
              },
              child: CircleAvatar(
                radius: 16,
                backgroundColor: Color(c),
                child: st.bulletinColor == c ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
              ),
            ),
        ]),
      ]),
      const SizedBox(height: 12),
      Section(title: 'Imprimer', subtitle: 'Un bulletin par page A4, prêt à imprimer ou à partager', children: [
        Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          const Text('Classe :'),
          _classPicker(context, sel),
          FilterChip(
            label: const Text('Toutes les classes'),
            selected: _allClasses,
            onSelected: (v) => setState(() => _allClasses = v),
          ),
        ]),
        const SizedBox(height: 8),
        _periodPicker(context, sel),
        const SizedBox(height: 8),
        if (st.periods.isNotEmpty && sel.period?.id == st.periods.last.id && st.annualRecap)
          Text('Dernière période : le récapitulatif annuel et la décision figurent sur le bulletin.',
              style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(
            onPressed: _busy || sel.period == null ? null : () => _generate(context),
            icon: _busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.picture_as_pdf),
            label: Text(_allClasses ? 'Bulletins de toutes les classes' : 'Bulletins de la classe ${sel.className}'),
          ),
          if (!_allClasses && students.isNotEmpty)
            MenuAnchor(
              builder: (c, m, _) => OutlinedButton.icon(
                onPressed: _busy ? null : () => m.isOpen ? m.close() : m.open(),
                icon: const Icon(Icons.person_outline),
                label: const Text('Un seul élève'),
              ),
              menuChildren: [
                for (final s in students)
                  MenuItemButton(onPressed: () => _generate(context, onlyStudent: s.id), child: Text(s.fullName)),
              ],
            ),
        ]),
        if (LicenseScope.watermarkOf(context, bulletinModule))
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Version d\'essai : les bulletins portent la mention « VERSION D\'ESSAI ».',
                style: TextStyle(color: Color(0xFFC62828))),
          ),
      ]),
    ]);
  }
}

/// Miniature schématique d'un modèle de bulletin.
class _ModelThumb extends StatelessWidget {
  final String model;
  final Color color;
  const _ModelThumb({required this.model, required this.color});

  @override
  Widget build(BuildContext context) {
    final light = Color.lerp(color, Colors.white, 0.85)!;
    Widget bar(double w, double h, Color c, {double r = 2}) =>
        Container(width: w, height: h, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(r)));
    final rows = model == 'primaire' ? 6 : 8;
    return Container(
      height: 150,
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.black12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (model == 'moderne')
          Container(
            height: 22,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [color, Color.lerp(color, Colors.black, 0.35)!]),
              borderRadius: BorderRadius.circular(4),
            ),
          )
        else ...[
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            bar(50, 5, Colors.black26),
            CircleAvatar(radius: 6, backgroundColor: light),
            bar(40, 5, Colors.black26),
          ]),
          const SizedBox(height: 4),
          bar(double.infinity, 8, color),
        ],
        const SizedBox(height: 4),
        bar(double.infinity, 12, Colors.black12),
        const SizedBox(height: 4),
        for (var i = 0; i < rows; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(children: [
              Expanded(flex: 3, child: bar(0, model == 'primaire' ? 7 : 5, i == 0 ? color : (i.isOdd ? light : Colors.black12))),
              const SizedBox(width: 2),
              if (model == 'detaille') ...[
                for (var k = 0; k < 3; k++) ...[
                  Expanded(child: bar(0, 5, i == 0 ? color : Colors.black12)),
                  const SizedBox(width: 2),
                ],
              ],
              Expanded(child: bar(0, model == 'primaire' ? 7 : 5, i == 0 ? color : Colors.black26)),
              const SizedBox(width: 2),
              Expanded(flex: 2, child: bar(0, model == 'primaire' ? 7 : 5, i == 0 ? color : Colors.black12)),
            ]),
          ),
        const Spacer(),
        if (model == 'moderne')
          Row(children: [
            for (final w in [30.0, 46.0, 22.0, 38.0])
              Padding(padding: const EdgeInsets.only(right: 4), child: bar(w, 4, color)),
          ])
        else
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            bar(30, 4, Colors.black26),
            bar(30, 4, Colors.black26),
            bar(30, 4, Colors.black26),
          ]),
      ]),
    );
  }
}

// =====================================================================
// Réglages
// =====================================================================

class _SettingsTab extends StatelessWidget {
  const _SettingsTab();

  Future<DateTime?> _pickDate(BuildContext context, DateTime? initial) => showDatePicker(
        context: context,
        initialDate: initial ?? DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime(2040),
        helpText: 'Choisir la date',
      );

  @override
  Widget build(BuildContext context) {
    final ctrl = SchoolScope.of(context);
    final st = ctrl.book.settings;
    void save() => ctrl.changed();

    Widget dd<T>(String label, T value, List<(T, String)> items, ValueChanged<T> on) => Row(children: [
          Expanded(child: Text(label)),
          DropdownButton<T>(
            value: items.any((e) => e.$1 == value) ? value : items.first.$1,
            items: [for (final (v, l) in items) DropdownMenuItem(value: v, child: Text(l))],
            onChanged: (v) {
              if (v != null) {
                on(v);
                save();
              }
            },
          ),
        ]);

    return ListView(padding: const EdgeInsets.all(16), children: [
      Section(
        title: 'Périodes',
        subtitle: 'Trimestres ou semestres. Les dates servent à compter les absences du pointage.',
        trailing: MenuAnchor(
          builder: (c, m, _) => TextButton(onPressed: () => m.isOpen ? m.close() : m.open(), child: const Text('Modèle')),
          menuChildren: [
            MenuItemButton(
              onPressed: () {
                st.periods = SchoolSettings.defaultPeriods();
                save();
              },
              child: const Text('3 trimestres'),
            ),
            MenuItemButton(
              onPressed: () {
                final y = st.periods.isNotEmpty && st.periods.first.start != null
                    ? st.periods.first.start!.year
                    : (DateTime.now().month >= 8 ? DateTime.now().year : DateTime.now().year - 1);
                st.periods = [
                  Period(name: '1er semestre', start: DateTime(y, 10, 1), end: DateTime(y + 1, 2, 15)),
                  Period(name: '2e semestre', start: DateTime(y + 1, 2, 16), end: DateTime(y + 1, 6, 30)),
                ];
                save();
              },
              child: const Text('2 semestres'),
            ),
          ],
        ),
        children: [
          for (final p in st.periods)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(children: [
                  Row(children: [
                    Expanded(
                      child: TextSetting(
                        key: ValueKey('pn-${p.id}'),
                        label: 'Nom',
                        value: p.name,
                        onChanged: (v) {
                          p.name = v;
                          save();
                        },
                      ),
                    ),
                    IconButton(
                      tooltip: 'Supprimer',
                      onPressed: st.periods.length <= 1
                          ? null
                          : () async {
                              if (await confirm(context, 'Supprimer « ${p.name} » ?',
                                  'Les notes saisies pour cette période ne seront plus affichées.',
                                  ok: 'Supprimer')) {
                                st.periods.remove(p);
                                save();
                              }
                            },
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.event),
                      label: Text('Du ${p.start == null ? '—' : _date(p.start!)}'),
                      onPressed: () async {
                        final d = await _pickDate(context, p.start);
                        if (d != null) {
                          p.start = d;
                          save();
                        }
                      },
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.event),
                      label: Text('Au ${p.end == null ? '—' : _date(p.end!)}'),
                      onPressed: () async {
                        final d = await _pickDate(context, p.end);
                        if (d != null) {
                          p.end = d;
                          save();
                        }
                      },
                    ),
                    const Text('Poids annuel :'),
                    DropdownButton<double>(
                      value: [1.0, 2.0, 3.0].contains(p.weight) ? p.weight : 1.0,
                      items: const [
                        DropdownMenuItem(value: 1.0, child: Text('1')),
                        DropdownMenuItem(value: 2.0, child: Text('2')),
                        DropdownMenuItem(value: 3.0, child: Text('3')),
                      ],
                      onChanged: (v) {
                        p.weight = v ?? 1;
                        save();
                      },
                    ),
                  ]),
                ]),
              ),
            ),
          TextButton.icon(
            onPressed: () {
              st.periods.add(Period(name: 'Période ${st.periods.length + 1}'));
              save();
            },
            icon: const Icon(Icons.add),
            label: const Text('Ajouter une période'),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Section(
        title: 'Évaluations de chaque période',
        subtitle: 'La moyenne d\'une matière est la moyenne pondérée de ces notes (les notes manquantes sont ignorées).',
        children: [
          for (final e in st.evals)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Expanded(
                  child: TextSetting(
                    key: ValueKey('ev-${e.id}'),
                    label: 'Évaluation',
                    value: e.name,
                    onChanged: (v) {
                      e.name = v;
                      save();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                const Text('Poids'),
                const SizedBox(width: 6),
                DropdownButton<double>(
                  value: [0.5, 1.0, 2.0, 3.0].contains(e.weight) ? e.weight : 1.0,
                  items: const [
                    DropdownMenuItem(value: 0.5, child: Text('0,5')),
                    DropdownMenuItem(value: 1.0, child: Text('1')),
                    DropdownMenuItem(value: 2.0, child: Text('2')),
                    DropdownMenuItem(value: 3.0, child: Text('3')),
                  ],
                  onChanged: (v) {
                    e.weight = v ?? 1;
                    save();
                  },
                ),
                IconButton(
                  onPressed: st.evals.length <= 1
                      ? null
                      : () {
                          st.evals.remove(e);
                          save();
                        },
                  icon: const Icon(Icons.delete_outline),
                ),
              ]),
            ),
          TextButton.icon(
            onPressed: () {
              st.evals.add(EvalType(name: 'Devoir ${st.evals.length + 1}'));
              save();
            },
            icon: const Icon(Icons.add),
            label: const Text('Ajouter une évaluation'),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Section(
        title: 'Absences dans les bulletins',
        subtitle: 'Les absences du pointage et celles saisies à la main sont comptées, et peuvent être retirées des notes.',
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Utiliser les absences du pointage'),
            subtitle: const Text('Selon les dates de chaque période (onglet Présences)'),
            value: st.useAttendance,
            onChanged: (v) {
              st.useAttendance = v;
              save();
            },
          ),
          dd<double>('Retenue sur la note de conduite, par absence non justifiée', st.conductPenalty, const [
            (0.0, 'Aucune'),
            (0.25, '0,25 pt'),
            (0.5, '0,5 pt'),
            (1.0, '1 pt'),
            (2.0, '2 pts'),
          ], (v) => st.conductPenalty = v),
          dd<double>('Retenue sur la moyenne générale, par absence non justifiée', st.averagePenalty, const [
            (0.0, 'Aucune'),
            (0.05, '0,05 pt'),
            (0.1, '0,1 pt'),
            (0.25, '0,25 pt'),
            (0.5, '0,5 pt'),
            (1.0, '1 pt'),
          ], (v) => st.averagePenalty = v),
          dd<int>('Retards comptés comme une absence', st.latesPerAbsence, const [
            (0, 'Jamais'),
            (2, '2 retards'),
            (3, '3 retards'),
            (4, '4 retards'),
            (5, '5 retards'),
          ], (v) => st.latesPerAbsence = v),
          dd<String>('Unité affichée', st.absenceUnit, const [
            ('jour(s)', 'Jours'),
            ('demi-journée(s)', 'Demi-journées'),
            ('heure(s)', 'Heures'),
          ], (v) => st.absenceUnit = v),
          Text(
            'Les retenues sont exprimées sur 20 et adaptées automatiquement aux classes notées sur 10. '
            'Pour la conduite, ajoutez une matière « Conduite » (cochée comme telle) dans chaque classe.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      const SizedBox(height: 12),
      Section(title: 'Classement et bulletin', children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Rang par matière'),
          value: st.rankPerSubject,
          onChanged: (v) {
            st.rankPerSubject = v;
            save();
          },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Récapitulatif annuel sur le bulletin de la dernière période'),
          value: st.annualRecap,
          onChanged: (v) {
            st.annualRecap = v;
            save();
          },
        ),
        dd<double>('Moyenne d\'admission (sur 20)', st.passMark, const [
          (9.0, '9'),
          (9.5, '9,5'),
          (10.0, '10'),
          (11.0, '11'),
          (12.0, '12'),
        ], (v) => st.passMark = v),
      ]),
      const SizedBox(height: 12),
      Section(
        title: 'Distinctions et sanctions',
        subtitle: 'Selon la moyenne générale ramenée sur 20 (de … à moins de …)',
        trailing: TextButton(
          onPressed: () {
            st.mentions = SchoolSettings.defaultMentions();
            save();
          },
          child: const Text('Par défaut'),
        ),
        children: [
          for (final m in st.mentions)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Expanded(
                  flex: 3,
                  child: TextSetting(
                    key: ValueKey('mt-${st.mentions.indexOf(m)}-${m.label}'),
                    label: m.positive ? 'Distinction' : 'Sanction',
                    value: m.label,
                    onChanged: (v) {
                      m.label = v;
                      save();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 70,
                  child: TextSetting(
                    key: ValueKey('mmin-${st.mentions.indexOf(m)}'),
                    label: 'De',
                    value: _n(m.min),
                    keyboard: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (v) {
                      m.min = parseNote(v) ?? m.min;
                      save();
                    },
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 70,
                  child: TextSetting(
                    key: ValueKey('mmax-${st.mentions.indexOf(m)}'),
                    label: 'À moins de',
                    value: _n(m.max),
                    keyboard: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (v) {
                      m.max = parseNote(v) ?? m.max;
                      save();
                    },
                  ),
                ),
                IconButton(
                  onPressed: () {
                    st.mentions.remove(m);
                    save();
                  },
                  icon: const Icon(Icons.delete_outline),
                ),
              ]),
            ),
          TextButton.icon(
            onPressed: () {
              st.mentions.add(MentionRule(10, 12, 'Nouvelle mention'));
              save();
            },
            icon: const Icon(Icons.add),
            label: const Text('Ajouter'),
          ),
        ],
      ),
    ]);
  }
}
