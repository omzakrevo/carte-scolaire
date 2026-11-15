import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../app_state.dart';
import '../card_kinds.dart';
import '../models.dart';
import '../services/ocr_engine.dart';
import '../services/sheet_reader.dart';
import '../widgets/common.dart';

/// Photo d'une feuille de noms → tableau modifiable (comme dans Excel) → fiches ajoutées.
class SheetImportScreen extends StatefulWidget {
  const SheetImportScreen({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SheetImportScreen()));

  @override
  State<SheetImportScreen> createState() => _SheetImportScreenState();
}

class _SheetImportScreenState extends State<SheetImportScreen> {
  Uint8List? _photo;
  String? _busy;
  String? _error;
  List<List<String>>? _rows;
  List<String> _fields = [];
  int? _header;
  final Set<int> _skip = {};
  String _defaultClass = '';
  int _rev = 0;
  String _source = '';

  bool get _isPhone => !Platform.isWindows && !Platform.isLinux && !Platform.isMacOS;

  Future<void> _pick(ImageSource? camera) async {
    Uint8List? bytes;
    try {
      if (camera != null && _isPhone) {
        final x = await ImagePicker().pickImage(source: camera, maxWidth: 3200, imageQuality: 92);
        bytes = await x?.readAsBytes();
      } else {
        bytes = (await pickOneFile(type: FileType.image))?.$2;
      }
    } catch (e) {
      if (mounted) toast(context, 'Impossible d\'ouvrir la photo : $e', error: true);
      return;
    }
    if (bytes == null) return;
    setState(() {
      _photo = bytes;
      _rows = null;
      _error = null;
    });
    if (OcrEngine.offlineSupported) {
      await _readOffline();
    }
  }

  void _setTable(List<List<String>> rows, String source) {
    final g = guessColumns(rows);
    setState(() {
      _rows = rows;
      _fields = [...g.fields];
      _header = g.headerRow;
      _skip.clear();
      _rev++;
      _source = source;
      _error = rows.isEmpty ? 'Aucun texte reconnu sur la photo.' : null;
    });
  }

  Future<void> _readOffline() async {
    final p = _photo;
    if (p == null) return;
    setState(() {
      _busy = 'Lecture de la feuille…';
      _error = null;
    });
    try {
      final words = await OcrEngine.recognize(p);
      _setTable(wordsToTable(words), 'Lecture hors ligne');
    } catch (e) {
      setState(() => _error = '$e'.replaceFirst('FormatException: ', '').replaceFirst('Unsupported operation: ', ''));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _readAi() async {
    final p = _photo;
    if (p == null) return;
    var s = await AiSettings.load();
    if (!s.ready) {
      if (!mounted) return;
      final ok = await showAiSettings(context, s);
      if (ok != true) return;
      s = await AiSettings.load();
      if (!s.ready) return;
    }
    setState(() {
      _busy = 'Lecture IA en cours (quelques secondes)…';
      _error = null;
    });
    try {
      _setTable(await readSheetWithAi(p, s), 'Lecture IA');
    } on SocketException {
      setState(() => _error = 'Pas de connexion Internet : la lecture IA en a besoin.');
    } catch (e) {
      setState(() => _error = '$e'.replaceFirst('FormatException: ', ''));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _pasteText() async {
    final c = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Coller une liste'),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: c,
            minLines: 8,
            maxLines: 16,
            decoration: const InputDecoration(
              hintText: 'Une personne par ligne. Colonnes séparées par des tabulations, des points-virgules '
                  'ou plusieurs espaces.\n\nOUÉDRAOGO Awa\t6e A\t12/03/2014',
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Lire la liste')),
        ],
      ),
    );
    if (text == null || text.trim().isEmpty) return;
    _setTable(textToTable(text), 'Texte collé');
  }

  List<Student> get _students =>
      _rows == null ? [] : buildStudents(_rows!, _fields, headerRow: _header, skip: _skip, defaultClass: _defaultClass);

  Future<void> _import() async {
    final state = AppScope.read(context);
    final list = _students;
    if (list.isEmpty) {
      toast(context, 'Choisissez au moins une colonne Nom (ou Nom et prénom).', error: true);
      return;
    }
    var replace = false;
    if (state.students.isNotEmpty) {
      final choice = await showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('${list.length} fiche(s) à ajouter'),
          content: Text('La liste contient déjà ${state.students.length} fiches. Ajouter à la suite ou remplacer ?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
            OutlinedButton(onPressed: () => Navigator.pop(c, 'replace'), child: const Text('Remplacer')),
            FilledButton(onPressed: () => Navigator.pop(c, 'add'), child: const Text('Ajouter à la suite')),
          ],
        ),
      );
      if (choice == null) return;
      replace = choice == 'replace';
    }
    state.addStudents(list, replace: replace);
    if (!mounted) return;
    toast(context, '${list.length} fiche(s) ajoutée(s) à la liste.');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final kind = kindById(state.template.kind);
    final rows = _rows;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Liste depuis une photo'),
        actions: [
          IconButton(
            tooltip: 'Réglages de la lecture IA',
            icon: const Icon(Icons.key_outlined),
            onPressed: () async {
              final s = await AiSettings.load();
              if (context.mounted) await showAiSettings(context, s);
            },
          ),
        ],
      ),
      bottomNavigationBar: rows == null || rows.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(children: [
                  Expanded(
                    child: Text('${_students.length} fiche(s) prête(s)', style: Theme.of(context).textTheme.titleSmall),
                  ),
                  FilledButton.icon(
                    onPressed: _busy == null ? _import : null,
                    icon: const Icon(Icons.playlist_add),
                    label: const Text('Ajouter à la liste'),
                  ),
                ]),
              ),
            ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        _sourceCard(context),
        if (_busy != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(children: [const CircularProgressIndicator(), const SizedBox(height: 12), Text(_busy!)]),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Material(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  const Icon(Icons.error_outline),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_error!)),
                ]),
              ),
            ),
          ),
        if (rows != null && rows.isNotEmpty && _busy == null) ...[
          const SizedBox(height: 16),
          _tableCard(context, rows, kind),
        ],
      ]),
    );
  }

  Widget _sourceCard(BuildContext context) {
    final p = _photo;
    return Section(
      title: 'Feuille de noms',
      subtitle: 'Photographiez la liste bien à plat, de face, avec une bonne lumière. '
          'La lecture hors ligne convient aux listes imprimées ; la lecture IA lit aussi l\'écriture à la main.',
      children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (_isPhone)
            FilledButton.icon(
              onPressed: _busy == null ? () => _pick(ImageSource.camera) : null,
              icon: const Icon(Icons.photo_camera),
              label: const Text('Photographier la feuille'),
            ),
          (_isPhone ? OutlinedButton.icon : FilledButton.icon)(
            onPressed: _busy == null ? () => _pick(null) : null,
            icon: const Icon(Icons.image_outlined),
            label: const Text('Choisir une image'),
          ),
          OutlinedButton.icon(
            onPressed: _busy == null ? _pasteText : null,
            icon: const Icon(Icons.content_paste),
            label: const Text('Coller du texte'),
          ),
        ]),
        if (p != null) ...[
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            InkWell(
              onTap: () => showDialog(
                context: context,
                builder: (c) => Dialog(child: InteractiveViewer(maxScale: 6, child: Image.memory(p))),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(p, width: 110, height: 140, fit: BoxFit.cover, cacheWidth: 300),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                if (OcrEngine.offlineSupported)
                  OutlinedButton.icon(
                    onPressed: _busy == null ? _readOffline : null,
                    icon: const Icon(Icons.document_scanner_outlined),
                    label: const Text('Lire (hors ligne)'),
                  ),
                FilledButton.tonalIcon(
                  onPressed: _busy == null ? _readAi : null,
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Lecture IA (écriture à la main)'),
                ),
                Text(
                  _source.isEmpty
                      ? 'Touchez la photo pour l\'agrandir.'
                      : '$_source : vérifiez le tableau ci-dessous et corrigez si besoin.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ]),
            ),
          ]),
        ],
      ],
    );
  }

  Widget _tableCard(BuildContext context, List<List<String>> rows, CardKind kind) {
    final width = _fields.length;
    const colW = 190.0;
    final scheme = Theme.of(context).colorScheme;
    return Section(
      title: 'Tableau relu (${rows.length} lignes)',
      subtitle: 'Choisissez ce que contient chaque colonne, corrigez les cases, décochez les lignes à ne pas ajouter.',
      children: [
        Row(children: [
          Expanded(
            child: CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _header != null,
              title: Text(_header == null || _header == 0
                  ? 'La première ligne contient les titres des colonnes'
                  : 'La ligne ${_header! + 1} contient les titres (les lignes au-dessus sont ignorées)'),
              onChanged: (v) => setState(() => _header = v == true ? 0 : null),
            ),
          ),
        ]),
        if (!_fields.contains('classe'))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TextField(
              decoration: InputDecoration(labelText: '${kind.group} pour toutes les fiches (facultatif)'),
              onChanged: (v) => setState(() => _defaultClass = v.trim()),
            ),
          ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: 44 + width * colW + 44,
            child: Column(children: [
              Row(children: [
                const SizedBox(width: 44),
                for (var c = 0; c < width; c++)
                  SizedBox(
                    width: colW,
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: DropdownButtonFormField<String>(
                        key: ValueKey('f$_rev-$c-${_fields[c]}'),
                        initialValue: _fields[c],
                        isExpanded: true,
                        isDense: true,
                        decoration: InputDecoration(
                          labelText: 'Colonne ${c + 1}',
                          filled: true,
                          fillColor: _fields[c].isEmpty ? null : scheme.primaryContainer,
                        ),
                        items: [
                          for (final f in sheetFields)
                            DropdownMenuItem(
                                value: f, child: Text(sheetFieldLabel(f), overflow: TextOverflow.ellipsis)),
                        ],
                        onChanged: (v) => setState(() {
                          // Un champ n'est utilisé qu'une fois.
                          for (var k = 0; k < _fields.length; k++) {
                            if (k != c && _fields[k] == v && v != '') _fields[k] = '';
                          }
                          _fields[c] = v ?? '';
                          _rev++;
                        }),
                      ),
                    ),
                  ),
              ]),
              for (var i = 0; i < rows.length; i++) _row(context, rows, i, colW),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() {
                    rows.add(List.filled(width, ''));
                    _rev++;
                  }),
                  icon: const Icon(Icons.add),
                  label: const Text('Ajouter une ligne'),
                ),
              ),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _row(BuildContext context, List<List<String>> rows, int i, double colW) {
    final r = rows[i];
    final header = i == _header;
    final above = _header != null && i < _header!;
    final off = header || above || _skip.contains(i);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: header ? scheme.surfaceContainerHighest : null,
      child: Row(children: [
        SizedBox(
          width: 44,
          child: header
              ? const Tooltip(message: 'Ligne des titres', child: Icon(Icons.title, size: 18))
              : above
                  ? const Tooltip(message: 'Au-dessus des titres : ignorée', child: Icon(Icons.block, size: 18))
                  : Checkbox(
                      value: !_skip.contains(i),
                      onChanged: (v) => setState(() => v == true ? _skip.remove(i) : _skip.add(i)),
                    ),
        ),
        for (var c = 0; c < _fields.length; c++)
          SizedBox(
            width: colW,
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: TextFormField(
                key: ValueKey('c$_rev-$i-$c'),
                initialValue: c < r.length ? r[c] : '',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: header ? FontWeight.w700 : null,
                  color: off && !header ? scheme.outline : null,
                  decoration: above ? TextDecoration.lineThrough : null,
                ),
                decoration: const InputDecoration(
                    isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10)),
                onChanged: (v) {
                  while (r.length <= c) {
                    r.add('');
                  }
                  r[c] = v;
                  setState(() {});
                },
              ),
            ),
          ),
        SizedBox(
          width: 44,
          child: IconButton(
            tooltip: 'Supprimer la ligne',
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => setState(() {
              rows.removeAt(i);
              final moved = {
                for (final k in _skip)
                  if (k != i) k > i ? k - 1 : k
              };
              _skip
                ..clear()
                ..addAll(moved);
              if (_header != null) {
                if (_header == i) {
                  _header = null;
                } else if (_header! > i) {
                  _header = _header! - 1;
                }
              }
              _rev++;
            }),
          ),
        ),
      ]),
    );
  }
}

/// Clé API et modèle de la lecture IA (enregistrés sur cet appareil uniquement).
Future<bool?> showAiSettings(BuildContext context, AiSettings s) {
  final key = TextEditingController(text: s.apiKey);
  final model = TextEditingController(text: s.model);
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Lecture IA'),
      content: SizedBox(
        width: 480,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text(
            'La lecture IA envoie la photo de la feuille à l\'API Claude (Anthropic) pour lire les noms, '
            'y compris l\'écriture à la main. Il faut Internet et une clé API (console.anthropic.com), '
            'payée à l\'usage : quelques francs CFA par feuille.\n\nLa clé reste sur cet appareil.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: key,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Clé API', hintText: 'sk-ant-…'),
          ),
          const SizedBox(height: 8),
          TextField(controller: model, decoration: const InputDecoration(labelText: 'Modèle')),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
        FilledButton(
          onPressed: () async {
            s
              ..apiKey = key.text.trim()
              ..model = model.text.trim().isEmpty ? AiSettings.defaultModel : model.text.trim();
            await s.save();
            if (ctx.mounted) Navigator.pop(ctx, true);
          },
          child: const Text('Enregistrer'),
        ),
      ],
    ),
  );
}
