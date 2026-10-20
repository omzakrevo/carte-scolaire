import 'package:flutter/material.dart';

import '../app_state.dart';
import '../designs/card_designs.dart';
import '../models.dart';
import '../widgets/common.dart';

/// Éditeur de disposition : déplacer, agrandir, réduire ou masquer chaque
/// élément de la carte (photo, logo, emblème, cachet, textes, QR).
class LayoutEditorScreen extends StatefulWidget {
  const LayoutEditorScreen({super.key});

  @override
  State<LayoutEditorScreen> createState() => _LayoutEditorScreenState();
}

class _LayoutEditorScreenState extends State<LayoutEditorScreen> {
  late final LayerEditor _editor;
  double _startScale = 1;

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
    final a = state.template.layer(id);
    a.dx += dx;
    a.dy += dy;
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
        final a = sel == null ? null : t.layers[sel];
        final wide = MediaQuery.sizeOf(context).width >= 900;

        final cardArea = LayoutBuilder(builder: (context, box) {
          final scale = ((box.maxWidth - 32) / t.widthMm).clamp(1.0, 14.0).toDouble();
          final s2 = ((box.maxHeight - 32) / t.heightMm).clamp(1.0, 14.0).toDouble();
          final sc = scale < s2 ? scale : s2;
          return Center(
            child: GestureDetector(
              // Glisser hors d'un élément déplace l'élément sélectionné.
              onScaleStart: (_) {
                if (sel != null) _startScale = t.layer(sel).scale;
              },
              onScaleUpdate: (d) {
                if (sel == null) return;
                final l = t.layer(sel);
                l.dx += d.focalPointDelta.dx / sc;
                l.dy += d.focalPointDelta.dy / sc;
                if (d.scale != 1) l.scale = (_startScale * d.scale).clamp(0.3, 3.0).toDouble();
                state.changed();
              },
              child: Container(
                padding: const EdgeInsets.all(16),
                color: Colors.transparent,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3 * sc),
                    boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 18, offset: Offset(0, 6))],
                  ),
                  child: CardView(template: t, school: state.school, student: student, scale: sc, editor: _editor),
                ),
              ),
            ),
          );
        });

        final controls = ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
                'Touchez un élément de la carte puis faites-le glisser. Pincez avec deux doigts, '
                'ou utilisez le curseur, pour l\'agrandir ou le réduire.',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final e in cardLayers.entries)
                ChoiceChip(
                  label: Text(e.value),
                  selected: sel == e.key,
                  avatar: (t.layers[e.key]?.hidden ?? false) ? const Icon(Icons.visibility_off, size: 16) : null,
                  onSelected: (_) => _editor.select(e.key),
                ),
            ]),
            const SizedBox(height: 16),
            if (sel != null) ...[
              Text(cardLayers[sel] ?? sel,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text('Taille : ${((a?.scale ?? 1) * 100).round()} %'),
              Slider(
                value: (a?.scale ?? 1).clamp(0.3, 3.0),
                min: 0.3,
                max: 3.0,
                divisions: 54,
                label: '${((a?.scale ?? 1) * 100).round()} %',
                onChanged: (v) {
                  t.layer(sel).scale = v;
                  state.changed();
                },
              ),
              Row(children: [
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
              ]),
              Text(
                'Décalage : ${(a?.dx ?? 0).toStringAsFixed(1)} mm horizontal, ${(a?.dy ?? 0).toStringAsFixed(1)} mm vertical',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(
                  onPressed: () {
                    t.layer(sel).hidden = !(a?.hidden ?? false);
                    state.changed();
                  },
                  icon: Icon((a?.hidden ?? false) ? Icons.visibility : Icons.visibility_off),
                  label: Text((a?.hidden ?? false) ? 'Afficher' : 'Masquer'),
                ),
                TextButton.icon(
                  onPressed: () {
                    t.layers.remove(sel);
                    state.changed();
                  },
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Réinitialiser cet élément'),
                ),
              ]),
            ],
            const Divider(height: 32),
            Text(
                'Le réglage s\'applique à toutes les cartes du projet. Les éléments absents du modèle '
                '(par exemple le QR code s\'il est désactivé) ne s\'affichent pas.',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        );

        return Scaffold(
          appBar: AppBar(
            title: const Text('Disposition des éléments'),
            actions: [
              TextButton.icon(
                onPressed: () async {
                  if (await confirm(context, 'Tout réinitialiser ?',
                      'Tous les éléments reprennent leur place et leur taille d\'origine.',
                      ok: 'Réinitialiser')) {
                    t.layers.clear();
                    state.changed();
                  }
                },
                icon: const Icon(Icons.restart_alt),
                label: const Text('Tout réinitialiser'),
              ),
            ],
          ),
          backgroundColor: scheme.surfaceContainerLow,
          body: wide
              ? Row(children: [
                  Expanded(child: cardArea),
                  SizedBox(width: 380, child: Material(color: scheme.surface, child: controls)),
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
