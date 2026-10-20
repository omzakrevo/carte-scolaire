import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../app_state.dart';
import '../models.dart';
import '../services/pdf_export.dart';
import '../widgets/common.dart';

class PrintScreen extends StatelessWidget {
  const PrintScreen({super.key});

  Future<void> _generate(BuildContext context, AppState state) async {
    final list = state.printable();
    if (list.isEmpty) {
      toast(context, 'Aucune carte à imprimer avec ces filtres.', error: true);
      return;
    }
    final progress = ValueNotifier<(int, int)>((0, list.length));
    var cancelled = false;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text('Préparation des cartes'),
        content: ValueListenableBuilder<(int, int)>(
          valueListenable: progress,
          builder: (_, p, __) => Column(mainAxisSize: MainAxisSize.min, children: [
            LinearProgressIndicator(value: p.$2 == 0 ? null : p.$1 / p.$2),
            const SizedBox(height: 12),
            Text(p.$1 < p.$2 ? 'Carte ${p.$1 + 1} sur ${p.$2}…' : 'Assemblage du PDF…'),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () {
              cancelled = true;
            },
            child: const Text('Annuler'),
          ),
        ],
      ),
    );
    Uint8List? bytes;
    String? error;
    try {
      bytes = await buildCardsPdf(
        students: list,
        template: state.template,
        school: state.school,
        layout: state.layout,
        onProgress: (d, t) => progress.value = (d, t),
        cancelled: () => cancelled,
      );
    } catch (e) {
      if (!isCancelled(e)) error = e is ArgumentError ? e.message.toString() : e.toString();
    }
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    if (error != null) {
      toast(context, 'Échec de la génération : $error', error: true);
      return;
    }
    if (bytes == null) return;
    final name = state.layout.a4Sheet ? 'planches_cartes_scolaires.pdf' : 'cartes_scolaires_individuelles.pdf';
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text('${list.length} cartes prêtes')),
        body: PdfPreview(
          build: (_) async => bytes!,
          pdfFileName: name,
          canChangeOrientation: false,
          canChangePageFormat: false,
          canDebug: false,
          allowSharing: true,
          allowPrinting: true,
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final l = state.layout;
    final t = state.template;
    final list = state.printable();
    final noPhoto = list.where((s) => s.photo == null).length;
    final (cols, rows) = l.grid(t.widthMm, t.heightMm);
    final perPage = cols * rows;
    final pages = perPage == 0 ? 0 : (list.length / perPage).ceil();
    void set(void Function() f) {
      f();
      state.changed();
    }

    final settings = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Section(title: 'Type d\'impression', children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, icon: Icon(Icons.grid_view), label: Text('Planche A4')),
            ButtonSegment(value: false, icon: Icon(Icons.crop_portrait), label: Text('Carte individuelle')),
          ],
          selected: {l.a4Sheet},
          onSelectionChanged: (v) => set(() => l.a4Sheet = v.first),
        ),
        const SizedBox(height: 8),
        Text(
          l.a4Sheet
              ? 'Plusieurs cartes par feuille A4, avec traits de coupe, pour imprimante classique.'
              : 'Une page PDF par carte, au format exact de la carte, pour imprimante à cartes PVC.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ]),
      const SizedBox(height: 12),
      Section(title: 'Cartes à imprimer', children: [
        DropdownButtonFormField<String?>(
          initialValue: state.classes.contains(l.classFilter) ? l.classFilter : null,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Classe'),
          items: [
            const DropdownMenuItem(value: null, child: Text('Toutes les classes')),
            for (final c in state.classes) DropdownMenuItem(value: c, child: Text(c)),
          ],
          onChanged: (v) => set(() => l.classFilter = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Uniquement les cartes validées'),
          value: l.onlyValidated,
          onChanged: (v) => set(() => l.onlyValidated = v),
        ),
      ]),
      if (l.a4Sheet) ...[
        const SizedBox(height: 12),
        Section(title: 'Mise en page A4', children: [
          Text('Marge de la feuille : ${l.marginMm.toStringAsFixed(0)} mm'),
          Slider(
            value: l.marginMm,
            min: 3,
            max: 20,
            divisions: 17,
            label: '${l.marginMm.toStringAsFixed(0)} mm',
            onChanged: (v) => set(() => l.marginMm = v),
          ),
          Text('Espace entre les cartes : ${l.gapMm.toStringAsFixed(0)} mm'),
          Slider(
            value: l.gapMm,
            min: 0,
            max: 10,
            divisions: 10,
            label: '${l.gapMm.toStringAsFixed(0)} mm',
            onChanged: (v) => set(() => l.gapMm = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Traits de coupe'),
            value: l.cutMarks,
            onChanged: (v) => set(() => l.cutMarks = v),
          ),
        ]),
      ],
    ]);

    final summary = Section(
      title: 'Récapitulatif',
      children: [
        _Line('Cartes', '${list.length}'),
        _Line('Format de carte',
            '${t.widthMm.toStringAsFixed(1).replaceAll('.0', '').replaceAll('.', ',')} × ${t.heightMm.toStringAsFixed(1).replaceAll('.0', '').replaceAll('.', ',')} mm'),
        if (l.a4Sheet) _Line('Par feuille A4', perPage == 0 ? 'Carte trop grande' : '$perPage ($cols × $rows)'),
        _Line('Pages', l.a4Sheet ? '$pages' : '${list.length}'),
        if (noPhoto > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              const Icon(Icons.warning_amber, color: Colors.orange, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text('$noPhoto carte(s) sans photo : elles seront imprimées avec une silhouette.')),
            ]),
          ),
        if (l.a4Sheet && perPage > 0) ...[
          const SizedBox(height: 16),
          Center(child: _SheetPreview(cols: cols, rows: rows, layout: l, w: t.widthMm, h: t.heightMm)),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
          onPressed: list.isEmpty || (l.a4Sheet && perPage == 0) ? null : () => _generate(context, state),
          icon: const Icon(Icons.picture_as_pdf),
          label: const Text('Générer le PDF'),
        ),
        const SizedBox(height: 6),
        Text('Vous pourrez ensuite imprimer, enregistrer ou partager le PDF.',
            textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
      ],
    );

    return LayoutBuilder(builder: (context, box) {
      if (box.maxWidth >= 900) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: settings),
            const SizedBox(width: 16),
            Expanded(child: summary),
          ]),
        );
      }
      return ListView(padding: const EdgeInsets.all(16), children: [settings, const SizedBox(height: 12), summary]);
    });
  }
}

class _Line extends StatelessWidget {
  final String label;
  final String value;
  const _Line(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(label)),
          Text(value,
              style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()])),
        ]),
      );
}

/// Schéma de la feuille A4 avec l'emplacement des cartes.
class _SheetPreview extends StatelessWidget {
  final int cols, rows;
  final PrintLayout layout;
  final double w, h;
  const _SheetPreview({required this.cols, required this.rows, required this.layout, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    const k = 1.0; // 1 px par mm
    final gridW = cols * w + (cols - 1) * layout.gapMm;
    final gridH = rows * h + (rows - 1) * layout.gapMm;
    final left = (210 - gridW) / 2, top = (297 - gridH) / 2;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 210 * k,
      height: 297 * k,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 8, offset: Offset(0, 3))],
      ),
      child: Stack(children: [
        for (var r = 0; r < rows; r++)
          for (var c = 0; c < cols; c++)
            Positioned(
              left: (left + c * (w + layout.gapMm)) * k,
              top: (top + r * (h + layout.gapMm)) * k,
              child: Container(
                width: w * k,
                height: h * k,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  border: Border.all(color: scheme.primary, width: 0.8),
                ),
              ),
            ),
      ]),
    );
  }
}
