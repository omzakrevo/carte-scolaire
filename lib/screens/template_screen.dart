import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../designs/card_designs.dart';
import '../main.dart' show isDesktop;
import '../models.dart';
import '../services/photo_utils.dart';
import '../widgets/common.dart';

const _swatches = <int>[
  0xFF009E49,
  0xFF0B6B3A,
  0xFF00897B,
  0xFF1E4FA1,
  0xFF0D1B3E,
  0xFF1A237E,
  0xFF6A1B9A,
  0xFF8E1B2E,
  0xFFEF2B2D,
  0xFFE65100,
  0xFFFFA000,
  0xFFFCD116,
  0xFFC9A646,
  0xFF795548,
  0xFF37474F,
  0xFF263238,
  0xFF90A4AE,
  0xFF90CAF9,
];

class TemplateScreen extends StatelessWidget {
  final VoidCallback onNext;
  const TemplateScreen({super.key, required this.onNext});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final sample = state.current ?? Student.sample();

    final preview = _Preview(state: state, student: sample);
    final gallery = _Gallery(state: state, student: sample);
    final settings = <Widget>[
      _SavedSection(state: state),
      _EditorSection(state: state),
      if (state.template.designId == 'personnalise') _BackgroundSection(state: state),
      _SizeSection(state: state),
      _ColorSection(state: state),
      _SchoolSection(state: state),
    ];
    final next = Align(
      alignment: Alignment.centerRight,
      child: FilledButton.icon(
        onPressed: onNext,
        icon: const Icon(Icons.arrow_forward),
        label: const Text('Étape suivante : les élèves'),
      ),
    );

    return LayoutBuilder(builder: (context, box) {
      if (box.maxWidth >= 1000) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 420,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [for (final w in settings) Padding(padding: const EdgeInsets.only(bottom: 12), child: w)],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: ListView(padding: const EdgeInsets.all(20), children: [
              preview,
              const SizedBox(height: 20),
              gallery,
              const SizedBox(height: 16),
              next,
            ]),
          ),
        ]);
      }
      return ListView(padding: const EdgeInsets.all(16), children: [
        preview,
        const SizedBox(height: 16),
        gallery,
        const SizedBox(height: 12),
        for (final w in settings) Padding(padding: const EdgeInsets.only(bottom: 12), child: w),
        next,
        const SizedBox(height: 24),
      ]);
    });
  }
}

class _Preview extends StatelessWidget {
  final AppState state;
  final Student student;
  const _Preview({required this.state, required this.student});

  @override
  Widget build(BuildContext context) {
    final t = state.template;
    final design = designById(t.designId);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: Text('Aperçu : ${design.name}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        ),
        Text(
          '${_mm(t.widthMm)} × ${_mm(t.heightMm)} mm',
          style: Theme.of(context).textTheme.labelLarge,
        ),
      ]),
      if (student.id == 'exemple')
        Text('Données d\'exemple : importez vos élèves pour voir leurs vraies cartes.',
            style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 12),
      Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: t.landscape ? 560 : 340, maxHeight: 520),
          child: FittedBox(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 18, offset: Offset(0, 6))],
              ),
              child: CardView(template: t, school: state.school, student: student, scale: 6),
            ),
          ),
        ),
      ),
    ]);
  }
}

String _mm(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1).replaceAll('.', ',');

class _Gallery extends StatelessWidget {
  final AppState state;
  final Student student;
  const _Gallery({required this.state, required this.student});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Choisir un modèle', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Wrap(spacing: 12, runSpacing: 12, children: [
        for (final d in cardDesigns)
          _DesignTile(
            design: d,
            selected: d.id == state.template.designId,
            onTap: () => state.selectDesign(d),
            scheme: scheme,
            child: CardView(
              template: state.template.copy()
                ..designId = d.id
                ..primary = d.primary
                ..secondary = d.secondary
                ..accent = d.accent
                ..widthMm = d.defaultWidth
                ..heightMm = d.defaultHeight,
              school: state.school,
              student: student,
              scale: 2.2,
            ),
          ),
      ]),
    ]);
  }
}

class _DesignTile extends StatelessWidget {
  final CardDesign design;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;
  final ColorScheme scheme;
  const _DesignTile({
    required this.design,
    required this.selected,
    required this.onTap,
    required this.child,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 210,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? scheme.primary : scheme.outlineVariant, width: selected ? 2.5 : 1),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(height: 130, child: Center(child: FittedBox(child: child))),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: Text(design.name,
                  style: const TextStyle(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            if (selected) Icon(Icons.check_circle, color: scheme.primary, size: 18),
          ]),
          Text(design.description,
              style: Theme.of(context).textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
        ]),
      ),
    );
  }
}

class _SizeSection extends StatelessWidget {
  final AppState state;
  const _SizeSection({required this.state});

  @override
  Widget build(BuildContext context) {
    final t = state.template;
    final preset = sizePresets.where((p) => p.w == t.widthMm && p.h == t.heightMm).firstOrNull;
    return Section(
      title: 'Dimensions de la carte',
      subtitle: 'Format standard ou dimensions personnalisées en millimètres',
      children: [
        DropdownButtonFormField<SizePreset?>(
          key: ValueKey(preset?.label ?? 'perso'),
          initialValue: preset,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Format'),
          items: [
            for (final p in sizePresets) DropdownMenuItem(value: p, child: Text(p.label)),
            const DropdownMenuItem(value: null, child: Text('Personnalisé')),
          ],
          onChanged: (p) {
            if (p != null) state.setSize(p.w, p.h);
          },
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: TextSetting(
              label: 'Largeur (mm)',
              value: _mm(t.widthMm),
              keyboard: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (v) {
                final d = double.tryParse(v.replaceAll(',', '.'));
                if (d != null && d >= 30 && d <= 150) state.setSize(d, t.heightMm);
              },
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Pivoter (paysage / portrait)',
            onPressed: state.swapOrientation,
            icon: const Icon(Icons.screen_rotation_alt),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextSetting(
              label: 'Hauteur (mm)',
              value: _mm(t.heightMm),
              keyboard: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (v) {
                final d = double.tryParse(v.replaceAll(',', '.'));
                if (d != null && d >= 30 && d <= 150) state.setSize(t.widthMm, d);
              },
            ),
          ),
        ]),
        const SizedBox(height: 6),
        Text('Entre 30 et 150 mm. Le format carte bancaire (85,6 × 54) passe dans les porte-badges standards.',
            style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _ColorSection extends StatelessWidget {
  final AppState state;
  const _ColorSection({required this.state});

  @override
  Widget build(BuildContext context) {
    final t = state.template;
    Widget row(String label, int value, ValueChanged<int> set) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final c in _swatches)
                InkWell(
                  onTap: () => set(c),
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Color(c),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: c == value ? Theme.of(context).colorScheme.onSurface : Colors.black12,
                        width: c == value ? 3 : 1,
                      ),
                    ),
                  ),
                ),
            ]),
          ]),
        );
    return Section(
      title: 'Couleurs',
      trailing: TextButton(
        onPressed: () {
          final d = designById(t.designId);
          t.primary = d.primary;
          t.secondary = d.secondary;
          t.accent = d.accent;
          state.changed();
        },
        child: const Text('Couleurs du modèle'),
      ),
      children: [
        row('Principale', t.primary, (c) {
          t.primary = c;
          state.changed();
        }),
        row('Secondaire', t.secondary, (c) {
          t.secondary = c;
          state.changed();
        }),
        row('Accent', t.accent, (c) {
          t.accent = c;
          state.changed();
        }),
      ],
    );
  }
}

const _fieldHints = <String, String>{
  'matricule': 'Matricule',
  'nomPrenom': 'Nom et prénom(s)',
  'dateNaissance': 'Date de naissance',
  'lieuNaissance': 'Lieu de naissance',
  'sexe': 'Sexe',
  'classe': 'Classe',
  'contact': 'Contact du parent',
};

/// Textes, libellés, champs affichés, tailles : l'éditeur du modèle.
class _EditorSection extends StatelessWidget {
  final AppState state;
  const _EditorSection({required this.state});

  @override
  Widget build(BuildContext context) {
    final t = state.template;
    void set(void Function() f) {
      f();
      state.changed();
    }

    Widget sw(String label, bool v, void Function(bool) f, {String? sub}) => SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(label),
          subtitle: sub == null ? null : Text(sub),
          value: v,
          onChanged: (x) => set(() => f(x)),
        );

    return Section(
      title: 'Modifier le modèle',
      subtitle: 'Textes de la carte, libellés et champs affichés',
      trailing: TextButton(
        onPressed: () => set(() {
          t.labels = {...defaultLabels};
          t.hidden = {};
          t.textScale = 1;
          t.photoScale = 1;
        }),
        child: const Text('Réinitialiser'),
      ),
      children: [
        TextSetting(label: 'Titre de la carte', value: t.title, onChanged: (v) => set(() => t.title = v)),
        const SizedBox(height: 10),
        TextSetting(label: 'Texte avant l\'année', value: t.yearLabel, onChanged: (v) => set(() => t.yearLabel = v)),
        const SizedBox(height: 14),
        Text('Champs (cochez pour afficher, renommez le libellé)', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        for (final f in cardFields)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Checkbox(
                value: t.shows(f),
                onChanged: (v) => set(() => v == true ? t.hidden.remove(f) : t.hidden.add(f)),
              ),
              Expanded(
                child: TextSetting(
                  label: _fieldHints[f]!,
                  value: t.label(f),
                  onChanged: (v) => set(() => t.labels[f] = v),
                ),
              ),
            ]),
          ),
        const Divider(height: 24),
        sw('Cachet de l\'école sur la photo', t.showStamp, (v) => t.showStamp = v,
            sub: state.school.stamp == null ? 'Ajoutez l\'image du cachet dans « Établissement »' : null),
        sw('Signataire (nom sous la photo, mention en pied)', t.showSignature, (v) => t.showSignature = v),
        sw('QR code du matricule', t.showQr, (v) => t.showQr = v),
        const SizedBox(height: 8),
        Text('Taille du texte : ${(t.textScale * 100).round()} %'),
        Slider(
          value: t.textScale,
          min: 0.75,
          max: 1.35,
          divisions: 12,
          label: '${(t.textScale * 100).round()} %',
          onChanged: (v) => set(() => t.textScale = v),
        ),
        Text('Taille de la photo : ${(t.photoScale * 100).round()} %'),
        Slider(
          value: t.photoScale,
          min: 0.7,
          max: 1.1,
          divisions: 8,
          label: '${(t.photoScale * 100).round()} %',
          onChanged: (v) => set(() => t.photoScale = v),
        ),
      ],
    );
  }
}

/// Image de fond du modèle « Fond personnalisé ».
class _BackgroundSection extends StatelessWidget {
  final AppState state;
  const _BackgroundSection({required this.state});

  Future<void> _pick(BuildContext context) async {
    try {
      final r = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
      final bytes = r?.files.single.bytes;
      if (bytes == null) return;
      state.template.background = await prepareBackground(bytes);
      state.changed();
    } catch (_) {
      if (context.mounted) toast(context, 'Image illisible : choisissez un fichier PNG ou JPEG.', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = state.template;
    void set(void Function() f) {
      f();
      state.changed();
    }

    return Section(
      title: 'Fond personnalisé',
      subtitle:
          'Créez le fond dans Photoshop ou Illustrator (logo, titre, décor) au format ${_mm(t.widthMm)} × ${_mm(t.heightMm)} mm, puis importez-le en PNG ou JPEG.',
      children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.tonalIcon(
            onPressed: () => _pick(context),
            icon: const Icon(Icons.wallpaper),
            label: Text(t.background == null ? 'Importer le fond' : 'Changer le fond'),
          ),
          if (t.background != null)
            TextButton(onPressed: () => set(() => t.background = null), child: const Text('Retirer')),
        ]),
        const SizedBox(height: 12),
        Text('Espace réservé en haut (en-tête du fond) : ${(t.headerSpace * 100).round()} %'),
        Slider(
          value: t.headerSpace.clamp(0, 0.6),
          max: 0.6,
          divisions: 24,
          onChanged: (v) => set(() => t.headerSpace = v),
        ),
        Text('Espace réservé en bas (pied du fond) : ${(t.footerSpace * 100).round()} %'),
        Slider(
          value: t.footerSpace.clamp(0, 0.5),
          max: 0.5,
          divisions: 20,
          onChanged: (v) => set(() => t.footerSpace = v),
        ),
      ],
    );
  }
}

/// « Mes modèles » : enregistrer, appliquer, renommer, exporter, importer.
class _SavedSection extends StatelessWidget {
  final AppState state;
  const _SavedSection({required this.state});

  Future<String?> _askName(BuildContext context, String title, String initial) {
    final c = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nom du modèle', hintText: 'Ex. C.P.E Maranatha 2026'),
          onSubmitted: (v) => Navigator.pop(d, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(d, c.text), child: const Text('Enregistrer')),
        ],
      ),
    );
  }

  Future<void> _export(BuildContext context, SavedTemplate s) async {
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode({'carteScolaireModele': 1, ...s.toJson()})));
    final safe = s.name.replaceAll(RegExp(r'[^\w\- ]'), '').trim().replaceAll(' ', '_');
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Exporter le modèle',
        fileName: '${safe.isEmpty ? 'modele' : safe}.carte.json',
        bytes: bytes,
      );
      if (path != null && isDesktop) await File(path).writeAsBytes(bytes);
      if (path != null && context.mounted) toast(context, 'Modèle « ${s.name} » exporté.');
    } catch (e) {
      if (context.mounted) toast(context, 'Export impossible : $e', error: true);
    }
  }

  Future<void> _import(BuildContext context) async {
    try {
      final r = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
      final bytes = r?.files.single.bytes;
      if (bytes == null) return;
      final j = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      if (j['template'] == null) throw const FormatException();
      final s = SavedTemplate.fromJson(j)..id = Student.newId();
      state.savedTemplates.add(s);
      state.changed();
      if (context.mounted) toast(context, 'Modèle « ${s.name} » importé.');
    } catch (_) {
      if (context.mounted) toast(context, 'Ce fichier n\'est pas un modèle de carte (.carte.json).', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = state.savedTemplates;
    return Section(
      title: 'Mes modèles',
      subtitle: 'Enregistrez vos réglages pour chaque établissement et réutilisez-les',
      children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(
            onPressed: () async {
              final name = await _askName(context, 'Enregistrer le modèle actuel', state.school.name);
              if (name != null && name.trim().isNotEmpty) state.saveTemplateAs(name.trim());
            },
            icon: const Icon(Icons.save_outlined),
            label: const Text('Enregistrer le modèle actuel'),
          ),
          OutlinedButton.icon(
            onPressed: () => _import(context),
            icon: const Icon(Icons.file_open_outlined),
            label: const Text('Importer'),
          ),
        ]),
        if (list.isNotEmpty) const SizedBox(height: 8),
        for (final s in list)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.style),
            title: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
                '${designById(s.template.designId).name} · ${_mm(s.template.widthMm)} × ${_mm(s.template.heightMm)} mm'),
            onTap: () {
              state.applySaved(s);
              toast(context, 'Modèle « ${s.name} » appliqué.');
            },
            trailing: PopupMenuButton<String>(
              tooltip: 'Actions',
              onSelected: (a) async {
                switch (a) {
                  case 'apply':
                    state.applySaved(s);
                  case 'update':
                    state.overwriteSaved(s);
                    toast(context, '« ${s.name} » mis à jour avec les réglages actuels.');
                  case 'rename':
                    final n = await _askName(context, 'Renommer le modèle', s.name);
                    if (n != null && n.trim().isNotEmpty) state.renameSaved(s, n.trim());
                  case 'export':
                    await _export(context, s);
                  case 'delete':
                    if (await confirm(context, 'Supprimer « ${s.name} » ?', 'Ce modèle enregistré sera supprimé.',
                        ok: 'Supprimer')) {
                      state.deleteSaved(s);
                    }
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'apply', child: Text('Appliquer')),
                PopupMenuItem(value: 'update', child: Text('Remplacer par les réglages actuels')),
                PopupMenuItem(value: 'rename', child: Text('Renommer')),
                PopupMenuItem(value: 'export', child: Text('Exporter (.carte.json)')),
                PopupMenuItem(value: 'delete', child: Text('Supprimer')),
              ],
            ),
          ),
      ],
    );
  }
}

class _SchoolSection extends StatelessWidget {
  final AppState state;
  const _SchoolSection({required this.state});

  Future<void> _pickImage(
      BuildContext context, Future<Uint8List> Function(Uint8List) prep, void Function(Uint8List) assign) async {
    try {
      final r = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
      final bytes = r?.files.single.bytes;
      if (bytes == null) return;
      assign(await prep(bytes));
      state.changed();
    } catch (e) {
      if (context.mounted) toast(context, 'Image illisible : choisissez un fichier PNG ou JPEG.', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = state.school;
    void set(void Function() f) {
      f();
      state.changed();
    }

    Widget imageSlot(String label, String hint, Uint8List? img, Future<Uint8List> Function(Uint8List) prep,
            void Function(Uint8List?) assign) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: const Color(0xFFF5F6F8),
                border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.all(5),
              child: img != null ? Image.memory(img, fit: BoxFit.contain) : const Icon(Icons.image_outlined),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(hint, style: Theme.of(context).textTheme.bodySmall),
                Wrap(spacing: 4, children: [
                  TextButton(
                    onPressed: () => _pickImage(context, prep, assign),
                    child: Text(img == null ? 'Ajouter' : 'Changer'),
                  ),
                  if (img != null) TextButton(onPressed: () => set(() => assign(null)), child: const Text('Retirer')),
                ]),
              ]),
            ),
          ]),
        );

    Widget gap() => const SizedBox(height: 10);
    return Section(
      title: 'Établissement',
      subtitle: 'Ces informations apparaissent sur toutes les cartes',
      children: [
        imageSlot('Logo de l\'école', 'À gauche de l\'en-tête', s.logo, prepareLogo, (b) => s.logo = b),
        imageSlot('Armoiries / emblème', 'À droite de l\'en-tête (drapeau par défaut)', s.emblem, prepareLogo,
            (b) => s.emblem = b),
        imageSlot('Cachet', 'Photo ou scan du cachet : le fond blanc est retiré automatiquement', s.stamp, prepareStamp,
            (b) => s.stamp = b),
        TextSetting(label: 'Nom de l\'établissement', value: s.name, onChanged: (v) => set(() => s.name = v)),
        gap(),
        TextSetting(
            label: 'Nom court (bandeau)',
            value: s.shortName,
            hint: 'C.P.E MARANATHA',
            onChanged: (v) => set(() => s.shortName = v)),
        gap(),
        TextSetting(
            label: 'Devise de l\'école',
            value: s.slogan,
            hint: 'DISCIPLINE - TRAVAIL - PROGRÈS',
            onChanged: (v) => set(() => s.slogan = v)),
        gap(),
        TextSetting(label: 'Année scolaire', value: s.schoolYear, onChanged: (v) => set(() => s.schoolYear = v)),
        gap(),
        TextSetting(label: 'Pays', value: s.country, onChanged: (v) => set(() => s.country = v)),
        gap(),
        TextSetting(label: 'Devise nationale', value: s.devise, onChanged: (v) => set(() => s.devise = v)),
        gap(),
        TextSetting(label: 'Ministère', value: s.ministry, onChanged: (v) => set(() => s.ministry = v)),
        gap(),
        TextSetting(
            label: 'Région / Province',
            value: s.region,
            hint: 'Région des Cascades - Province de la Léraba',
            onChanged: (v) => set(() => s.region = v)),
        gap(),
        TextSetting(
            label: 'Nom du signataire (sous la photo)',
            value: s.signerName,
            hint: 'M. BAZIÉ',
            onChanged: (v) => set(() => s.signerName = v)),
        gap(),
        TextSetting(
            label: 'Mention du signataire',
            value: s.directorTitle,
            hint: 'Le Directeur, Le Proviseur…',
            onChanged: (v) => set(() => s.directorTitle = v)),
        gap(),
        TextSetting(label: 'Adresse', value: s.address, onChanged: (v) => set(() => s.address = v)),
        gap(),
        TextSetting(label: 'Téléphone', value: s.phone, onChanged: (v) => set(() => s.phone = v)),
      ],
    );
  }
}
