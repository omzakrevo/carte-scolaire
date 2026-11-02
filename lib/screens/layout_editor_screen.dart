import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../designs/card_designs.dart';
import '../models.dart';
import '../services/photo_utils.dart';
import '../widgets/common.dart';

/// Éditeur de la carte : déplacer, agrandir, masquer les éléments du modèle
/// (photo, logo, textes, QR) et ajouter ses propres textes, formes et images.
class LayoutEditorScreen extends StatefulWidget {
  const LayoutEditorScreen({super.key});

  @override
  State<LayoutEditorScreen> createState() => _LayoutEditorScreenState();
}

const _variables = <String, String>{
  '{prenom}': 'Prénom',
  '{nom}': 'Nom',
  '{matricule}': 'Matricule',
  '{classe}': 'Classe / service',
  '{fonction}': 'Fonction',
  '{telephone}': 'Téléphone',
  '{email}': 'E-mail',
  '{adresse}': 'Adresse',
  '{ecole}': 'Structure',
  '{annee}': 'Année',
};

class _LayoutEditorScreenState extends State<LayoutEditorScreen> {
  late final LayerEditor _editor;

  /// Côté de la carte en cours de modification.
  bool _back = false;

  @override
  void initState() {
    super.initState();
    _editor = LayerEditor(onChanged: () => AppScope.read(context).changed())..selected = 'photo';
  }

  @override
  void dispose() {
    _editor.dispose();
    super.dispose();
  }

  void _nudge(AppState state, double dx, double dy) {
    final id = _editor.selected;
    if (id == null) return;
    final e = _editor.selectedElement(state.template);
    if (e != null) {
      e.x += dx;
      e.y += dy;
    } else {
      final a = state.template.layer(id);
      a.dx += dx;
      a.dy += dy;
    }
    state.changed();
  }

  Future<void> _add(AppState state, String type) async {
    final t = state.template;
    final cx = t.widthMm / 2, cy = t.heightMm / 2;
    CardElement e;
    switch (type) {
      case 'text':
        e = CardElement(
            type: 'text',
            text: 'Votre texte',
            x: cx - 15,
            y: cy - 3,
            w: 30,
            h: 6,
            fontSize: 3,
            bold: true,
            color: t.secondary);
      case 'rect':
        e = CardElement(type: 'rect', x: cx - 10, y: cy - 6, w: 20, h: 12, color: t.primary, radius: 1.5);
      case 'ellipse':
        e = CardElement(type: 'ellipse', x: cx - 7, y: cy - 7, w: 14, h: 14, color: t.accent);
      case 'line':
        e = CardElement(type: 'line', x: cx - 15, y: cy, w: 30, h: 0.6, color: t.primary);
      default:
        final f = await pickOneFile(type: FileType.image);
        if (f == null) return;
        final img = await prepareLogo(f.$2);
        e = CardElement(type: 'image', x: cx - 10, y: cy - 10, w: 20, h: 20, image: img);
    }
    e.back = _back;
    t.elements.add(e);
    _editor.select('el:${e.id}');
    state.changed();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = state.template;
    final student = state.current ?? Student.sample();
    final scheme = Theme.of(context).colorScheme;

    return ListenableBuilder(
      listenable: _editor,
      builder: (context, _) {
        final sel = _editor.selected;
        final el = _editor.selectedElement(t);
        final wide = MediaQuery.sizeOf(context).width >= 900;

        final cardArea = LayoutBuilder(builder: (context, box) {
          final scale = ((box.maxWidth - 32) / t.widthMm).clamp(1.0, 14.0).toDouble();
          final s2 = ((box.maxHeight - 32) / t.heightMm).clamp(1.0, 14.0).toDouble();
          final sc = scale < s2 ? scale : s2;
          return Center(
            child: GestureDetector(
              // Glisser hors d'un élément déplace l'élément sélectionné.
              onScaleStart: (_) {
                if (sel != null) _editor.begin(sel, t);
              },
              onScaleUpdate: (d) {
                if (sel != null) _editor.update(sel, t, d.focalPointDelta / sc, d.scale);
              },
              child: Container(
                padding: const EdgeInsets.all(16),
                color: Colors.transparent,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3 * sc),
                    boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 18, offset: Offset(0, 6))],
                  ),
                  child: CardView(
                      template: t, school: state.school, student: student, scale: sc, editor: _editor, back: _back && t.hasVerso),
                ),
              ),
            ),
          );
        });

        final moveRow = Row(children: [
          const Text('Déplacer :'),
          const SizedBox(width: 8),
          IconButton.filledTonal(
              tooltip: 'Gauche', onPressed: () => _nudge(state, -0.5, 0), icon: const Icon(Icons.arrow_back)),
          IconButton.filledTonal(
              tooltip: 'Haut', onPressed: () => _nudge(state, 0, -0.5), icon: const Icon(Icons.arrow_upward)),
          IconButton.filledTonal(
              tooltip: 'Bas', onPressed: () => _nudge(state, 0, 0.5), icon: const Icon(Icons.arrow_downward)),
          IconButton.filledTonal(
              tooltip: 'Droite', onPressed: () => _nudge(state, 0.5, 0), icon: const Icon(Icons.arrow_forward)),
        ]);

        final back = _back && t.hasVerso;
        final prefix = back ? 'v:' : '';
        final controls = ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (t.hasVerso) ...[
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Recto'), icon: Icon(Icons.flip_to_front)),
                  ButtonSegment(value: true, label: Text('Verso'), icon: Icon(Icons.flip_to_back)),
                ],
                selected: {back},
                onSelectionChanged: (v) => setState(() {
                  _back = v.first;
                  _editor.select(null);
                }),
              ),
              const SizedBox(height: 14),
            ],
            Text('Ajouter sur la carte', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final (type, icon, label) in [
                ('text', Icons.text_fields, 'Texte'),
                ('rect', Icons.crop_square, 'Rectangle'),
                ('ellipse', Icons.circle_outlined, 'Cercle'),
                ('line', Icons.horizontal_rule, 'Ligne'),
                ('image', Icons.image_outlined, 'Image'),
              ])
                FilledButton.tonalIcon(onPressed: () => _add(state, type), icon: Icon(icon), label: Text(label)),
            ]),
            const SizedBox(height: 14),
            Text(
                'Touchez un élément de la carte puis faites-le glisser. Pincez avec deux doigts, '
                'ou utilisez les curseurs, pour l\'agrandir ou le réduire.',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final e in cardLayers.entries)
                ChoiceChip(
                  label: Text(e.value),
                  selected: sel == '$prefix${e.key}',
                  avatar: (t.layers['$prefix${e.key}']?.hidden ?? false) ? const Icon(Icons.visibility_off, size: 16) : null,
                  onSelected: (_) => _editor.select('$prefix${e.key}'),
                ),
              for (final e in t.elements.where((e) => e.back == back))
                ChoiceChip(
                  label: Text(e.label),
                  avatar: Icon(
                      switch (e.type) {
                        'text' => Icons.text_fields,
                        'rect' => Icons.crop_square,
                        'ellipse' => Icons.circle_outlined,
                        'line' => Icons.horizontal_rule,
                        _ => Icons.image_outlined,
                      },
                      size: 16),
                  selected: sel == 'el:${e.id}',
                  onSelected: (_) => _editor.select('el:${e.id}'),
                ),
            ]),
            const SizedBox(height: 16),
            if (el != null)
              _ElementPanel(element: el, state: state, editor: _editor, moveRow: moveRow)
            else if (sel != null)
              _LayerPanel(id: sel, state: state, moveRow: moveRow),
            const Divider(height: 32),
            Text(
                'Le réglage s\'applique à toutes les cartes du projet. Dans un texte, les variables comme {nom} '
                'sont remplacées par les informations de chaque personne.',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        );

        return Scaffold(
          appBar: AppBar(
            title: const Text('Éditeur de la carte'),
            actions: [
              TextButton.icon(
                onPressed: () async {
                  if (await confirm(context, 'Tout réinitialiser ?',
                      'Les éléments du modèle reprennent leur place d\'origine. Vos textes, formes et images ajoutés sont conservés.',
                      ok: 'Réinitialiser')) {
                    t.layers.clear();
                    state.changed();
                  }
                },
                icon: const Icon(Icons.restart_alt),
                label: const Text('Réinitialiser'),
              ),
            ],
          ),
          backgroundColor: scheme.surfaceContainerLow,
          body: wide
              ? Row(children: [
                  Expanded(child: cardArea),
                  SizedBox(width: 400, child: Material(color: scheme.surface, child: controls)),
                ])
              : Column(children: [
                  SizedBox(height: MediaQuery.sizeOf(context).height * 0.36, child: cardArea),
                  Expanded(child: Material(color: scheme.surface, child: controls)),
                ]),
        );
      },
    );
  }
}

/// Réglages d'un élément du modèle (photo, logo, QR…).
class _LayerPanel extends StatelessWidget {
  final String id;
  final AppState state;
  final Widget moveRow;
  const _LayerPanel({required this.id, required this.state, required this.moveRow});

  @override
  Widget build(BuildContext context) {
    final t = state.template;
    final a = t.layers[id];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(cardLayers[id.replaceFirst('v:', '')] ?? id, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Text('Taille : ${((a?.scale ?? 1) * 100).round()} %'),
      Slider(
        value: (a?.scale ?? 1).clamp(0.3, 3.0),
        min: 0.3,
        max: 3.0,
        divisions: 54,
        label: '${((a?.scale ?? 1) * 100).round()} %',
        onChanged: (v) {
          t.layer(id).scale = v;
          state.changed();
        },
      ),
      moveRow,
      Text(
        'Décalage : ${(a?.dx ?? 0).toStringAsFixed(1)} mm horizontal, ${(a?.dy ?? 0).toStringAsFixed(1)} mm vertical',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(
          onPressed: () {
            t.layer(id).hidden = !(a?.hidden ?? false);
            state.changed();
          },
          icon: Icon((a?.hidden ?? false) ? Icons.visibility : Icons.visibility_off),
          label: Text((a?.hidden ?? false) ? 'Afficher' : 'Masquer'),
        ),
        TextButton.icon(
          onPressed: () {
            t.layers.remove(id);
            state.changed();
          },
          icon: const Icon(Icons.restart_alt),
          label: const Text('Réinitialiser cet élément'),
        ),
      ]),
    ]);
  }
}

/// Réglages d'un texte, d'une forme ou d'une image ajoutés.
class _ElementPanel extends StatefulWidget {
  final CardElement element;
  final AppState state;
  final LayerEditor editor;
  final Widget moveRow;
  const _ElementPanel({required this.element, required this.state, required this.editor, required this.moveRow});

  @override
  State<_ElementPanel> createState() => _ElementPanelState();
}

class _ElementPanelState extends State<_ElementPanel> {
  late final TextEditingController _text = TextEditingController(text: widget.element.text);

  @override
  void didUpdateWidget(_ElementPanel old) {
    super.didUpdateWidget(old);
    if (old.element.id != widget.element.id) _text.text = widget.element.text;
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.element;
    final state = widget.state;
    final t = state.template;
    void set(void Function() f) {
      f();
      state.changed();
    }

    Widget slider(String label, double value, double min, double max, ValueChanged<double> on, {String unit = 'mm'}) =>
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$label : ${value.toStringAsFixed(unit == '°' || unit == '%' ? 0 : 1)} $unit'),
          Slider(value: value.clamp(min, max), min: min, max: max, onChanged: (v) => set(() => on(v))),
        ]);
    Widget colors(String label, int value, ValueChanged<int> on,
            {bool allowNone = false, bool isNone = false, VoidCallback? onNone}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            ColorRow(
              value: value,
              onChanged: (c) => set(() => on(c)),
              extra: [t.primary, t.secondary, t.accent],
              allowNone: allowNone,
              isNone: isNone,
              onNone: onNone == null ? null : () => set(onNone),
            ),
          ]),
        );
    final index = t.elements.indexOf(e);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(CardElement.typeLabels[e.type] ?? e.type,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 10),
      if (e.type == 'text') ...[
        TextField(
          controller: _text,
          minLines: 1,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Texte'),
          onChanged: (v) => set(() => e.text = v),
        ),
        const SizedBox(height: 6),
        Wrap(spacing: 4, runSpacing: 4, children: [
          for (final v in _variables.entries)
            ActionChip(
              visualDensity: VisualDensity.compact,
              label: Text(v.value),
              tooltip: v.key,
              onPressed: () {
                final sel = _text.selection;
                final pos = sel.isValid ? sel.start : _text.text.length;
                _text.text = _text.text.replaceRange(pos, sel.isValid ? sel.end : pos, v.key);
                _text.selection = TextSelection.collapsed(offset: pos + v.key.length);
                set(() => e.text = _text.text);
              },
            ),
        ]),
        const SizedBox(height: 10),
        slider('Taille du texte', e.fontSize, 0.8, 20, (v) => e.fontSize = v),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          FilterChip(label: const Text('Gras'), selected: e.bold, onSelected: (v) => set(() => e.bold = v)),
          FilterChip(label: const Text('Italique'), selected: e.italic, onSelected: (v) => set(() => e.italic = v)),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'left', icon: Icon(Icons.format_align_left)),
              ButtonSegment(value: 'center', icon: Icon(Icons.format_align_center)),
              ButtonSegment(value: 'right', icon: Icon(Icons.format_align_right)),
            ],
            selected: {e.align},
            onSelectionChanged: (v) => set(() => e.align = v.first),
          ),
          DropdownButton<String>(
            value: e.font,
            items: const [
              DropdownMenuItem(value: '', child: Text('Police standard')),
              DropdownMenuItem(value: 'serif', child: Text('Avec empattements')),
              DropdownMenuItem(value: 'mono', child: Text('Machine à écrire')),
            ],
            onChanged: (v) => set(() => e.font = v ?? ''),
          ),
        ]),
        const SizedBox(height: 10),
        colors('Couleur du texte', e.color, (c) => e.color = c),
        colors('Fond du texte', e.fill ?? 0xFFFFFFFF, (c) => e.fill = c,
            allowNone: true, isNone: e.fill == null, onNone: () => e.fill = null),
      ],
      if (e.type == 'rect' || e.type == 'ellipse') colors('Remplissage', e.color, (c) => e.color = c),
      if (e.type == 'line') colors('Couleur', e.color, (c) => e.color = c),
      if (e.type == 'image')
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: OutlinedButton.icon(
            onPressed: () async {
              final f = await pickOneFile(type: FileType.image);
              if (f == null) return;
              final img = await prepareLogo(f.$2);
              set(() => e.image = img);
            },
            icon: const Icon(Icons.image_search),
            label: const Text('Changer l\'image'),
          ),
        ),
      slider(e.type == 'line' ? 'Longueur' : 'Largeur', e.w, 1, t.widthMm * 1.5, (v) => e.w = v),
      slider(e.type == 'line' ? 'Épaisseur' : 'Hauteur', e.h, e.type == 'line' ? 0.1 : 1,
          e.type == 'line' ? 4 : t.heightMm * 1.5, (v) => e.h = v),
      if (e.type != 'line') ...[
        if (e.type != 'ellipse') slider('Coins arrondis', e.radius, 0, 15, (v) => e.radius = v),
        slider('Bordure', e.borderWidth, 0, 3, (v) => e.borderWidth = v),
        if (e.borderWidth > 0) colors('Couleur de la bordure', e.borderColor, (c) => e.borderColor = c),
      ],
      slider('Rotation', e.rotation, -180, 180, (v) => e.rotation = v, unit: '°'),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Opacité : ${(e.opacity * 100).round()} %'),
        Slider(value: e.opacity, min: 0.05, max: 1, onChanged: (v) => set(() => e.opacity = v)),
      ]),
      widget.moveRow,
      Text('Position : ${e.x.toStringAsFixed(1)} × ${e.y.toStringAsFixed(1)} mm depuis le coin haut gauche',
          style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(
          onPressed: index < t.elements.length - 1
              ? () => set(() {
                    t.elements.removeAt(index);
                    t.elements.insert(index + 1, e);
                  })
              : null,
          icon: const Icon(Icons.flip_to_front),
          label: const Text('Devant'),
        ),
        OutlinedButton.icon(
          onPressed: index > 0
              ? () => set(() {
                    t.elements.removeAt(index);
                    t.elements.insert(index - 1, e);
                  })
              : null,
          icon: const Icon(Icons.flip_to_back),
          label: const Text('Derrière'),
        ),
        OutlinedButton.icon(
          onPressed: () {
            final c = e.copy(newId: true)
              ..x = e.x + 2
              ..y = e.y + 2;
            t.elements.add(c);
            widget.editor.select('el:${c.id}');
            state.changed();
          },
          icon: const Icon(Icons.copy),
          label: const Text('Dupliquer'),
        ),
        TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
          onPressed: () {
            t.elements.remove(e);
            widget.editor.select(null);
            state.changed();
          },
          icon: const Icon(Icons.delete_outline),
          label: const Text('Supprimer'),
        ),
      ]),
    ]);
  }
}
