import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../card_kinds.dart';
import '../models.dart';
import '../services/photo_batch.dart';
import '../services/photo_utils.dart';
import '../widgets/common.dart';

/// Photos prises à la suite (dans l'ordre de la liste) : on choisit le dossier ou les photos,
/// elles sont triées par heure de prise puis attribuées aux noms, avec correction à la main.
class PhotoBatchScreen extends StatefulWidget {
  const PhotoBatchScreen({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PhotoBatchScreen()));

  @override
  State<PhotoBatchScreen> createState() => _PhotoBatchScreenState();
}

class _PhotoBatchScreenState extends State<PhotoBatchScreen> {
  final List<BatchPhoto> _photos = [];
  PhotoAssignment? _a;
  List<Student> _people = [];
  String? _class;
  bool? _onlyMissing;
  bool _byName = false;
  String? _busy;
  double? _progress;

  static const _exts = {'jpg', 'jpeg', 'png'};
  bool get _desktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  AppState get _state => AppScope.read(context);

  void _rebuild() {
    final st = _state;
    _onlyMissing ??= st.students.any((s) => s.photo != null);
    _people = st.students.where((s) {
      if (_class != null && s.classe.trim() != _class) return false;
      if (_onlyMissing! && s.photo != null) return false;
      return true;
    }).toList();
    sortByTaken(_photos, byName: _byName);
    _a = PhotoAssignment(_people.length, _photos);
  }

  Future<void> _load(Future<List<BatchPhoto>> Function() read) async {
    setState(() {
      _busy = 'Lecture des photos…';
      _progress = null;
    });
    try {
      final list = await read();
      if (!mounted) return;
      if (list.isEmpty) {
        toast(context, 'Aucune photo JPEG ou PNG trouvée.', error: true);
        return;
      }
      setState(() {
        _photos
          ..clear()
          ..addAll(list);
        _rebuild();
      });
    } catch (e) {
      if (mounted) toast(context, 'Impossible de lire les photos : $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<BatchPhoto> _describe(String name, {String? path, Uint8List? bytes}) async {
    Uint8List head;
    DateTime? fileDate;
    if (bytes != null) {
      head = bytes;
    } else {
      final raf = await File(path!).open();
      try {
        head = await raf.read(256 * 1024);
      } finally {
        await raf.close();
      }
    }
    if (path != null) {
      try {
        fileDate = await File(path).lastModified();
      } catch (_) {}
    }
    final exif = exifTakenDate(head);
    final fromName = exif == null ? fileNameDate(name) : null;
    return BatchPhoto(
      name,
      path: path,
      bytes: path == null ? bytes : null,
      taken: exif ?? fromName ?? fileDate,
      source: exif != null
          ? TakenSource.exif
          : fromName != null
              ? TakenSource.fileName
              : fileDate != null
                  ? TakenSource.fileDate
                  : TakenSource.none,
    );
  }

  Future<void> _pickFolder() async {
    final dir = await FilePicker.getDirectoryPath(dialogTitle: 'Dossier des photos');
    if (dir == null) return;
    await _load(() async {
      final out = <BatchPhoto>[];
      final files = await Directory(dir)
          .list()
          .where((e) => e is File && _exts.contains(e.path.split('.').last.toLowerCase()))
          .cast<File>()
          .toList();
      for (var i = 0; i < files.length; i++) {
        if (mounted) setState(() => _progress = (i + 1) / files.length);
        out.add(await _describe(files[i].uri.pathSegments.last, path: files[i].path));
      }
      return out;
    });
  }

  Future<void> _pickFiles() async {
    List<PlatformFile> files;
    try {
      files = await FilePicker.pickFiles(type: FileType.image, dialogTitle: 'Photos à attribuer');
    } catch (e) {
      if (mounted) toast(context, 'Impossible d\'ouvrir le sélecteur : $e', error: true);
      return;
    }
    if (files.isEmpty) return;
    await _load(() async {
      final out = <BatchPhoto>[];
      for (var i = 0; i < files.length; i++) {
        if (mounted) setState(() => _progress = (i + 1) / files.length);
        final f = files[i];
        final path = f.path;
        if (path != null && File(path).existsSync()) {
          out.add(await _describe(f.name, path: path));
        } else {
          out.add(await _describe(f.name, bytes: await f.readAsBytes()));
        }
      }
      return out;
    });
  }

  Future<void> _apply() async {
    final a = _a;
    if (a == null) return;
    final st = _state;
    final todo = [
      for (var i = 0; i < _people.length; i++)
        if (a.slots[i] != null) (_people[i], a.slots[i]!)
    ];
    if (todo.isEmpty) return;
    final replacing = todo.where((e) => e.$1.photo != null).length;
    if (replacing > 0 &&
        !await confirm(context, 'Remplacer des photos ?',
            '$replacing fiche(s) ont déjà une photo : elle sera remplacée par la nouvelle.',
            ok: 'Remplacer')) {
      return;
    }
    setState(() {
      _busy = 'Attribution des photos…';
      _progress = 0;
    });
    var done = 0, failed = 0;
    for (final (s, p) in todo) {
      try {
        final bytes = p.bytes ?? await File(p.path!).readAsBytes();
        final original = await normalizeOriginal(bytes);
        st.setPhoto(s, await preparePhoto(original), original: original);
        done++;
      } catch (_) {
        failed++;
      }
      if (mounted) setState(() => _progress = (done + failed) / todo.length);
    }
    if (!mounted) return;
    setState(() => _busy = null);
    toast(context,
        '$done photo(s) attribuée(s).${failed > 0 ? ' $failed illisible(s).' : ''} Vous pouvez recadrer chaque photo dans l\'écran Photos.',
        error: failed > 0);
    Navigator.pop(context);
  }

  String _time(BatchPhoto p) {
    final t = p.taken;
    if (t == null) return 'Heure inconnue';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.day)}/${two(t.month)} ${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  Widget _thumb(BatchPhoto? p, {double w = 72, double h = 96}) {
    final scheme = Theme.of(context).colorScheme;
    if (p == null) {
      return Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Icon(Icons.no_photography_outlined, color: scheme.outline),
      );
    }
    final cache = (w * 2.5).round();
    final image = p.bytes != null
        ? Image.memory(p.bytes!, width: w, height: h, fit: BoxFit.cover, cacheWidth: cache)
        : Image.file(File(p.path!), width: w, height: h, fit: BoxFit.cover, cacheWidth: cache);
    return ClipRRect(borderRadius: BorderRadius.circular(8), child: image);
  }

  Future<int?> _choosePerson(String title, {int? except}) => showDialog<int>(
        context: context,
        builder: (c) => SimpleDialog(
          title: Text(title),
          children: [
            SizedBox(
              width: 420,
              height: 420,
              child: ListView.builder(
                itemCount: _people.length,
                itemBuilder: (_, j) => ListTile(
                  enabled: j != except,
                  leading: SizedBox(width: 36, child: _thumb(_a!.slots[j], w: 30, h: 40)),
                  title: Text('${j + 1}. ${_people[j].fullName}'),
                  subtitle: _people[j].classe.isEmpty ? null : Text(_people[j].classe),
                  onTap: () => Navigator.pop(c, j),
                ),
              ),
            ),
          ],
        ),
      );

  Future<void> _preview(BatchPhoto p) => showDialog(
        context: context,
        builder: (c) => Dialog(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Flexible(
              child: InteractiveViewer(
                child: p.bytes != null ? Image.memory(p.bytes!) : Image.file(File(p.path!), cacheWidth: 1400),
              ),
            ),
            Padding(padding: const EdgeInsets.all(10), child: Text('${p.name} · ${_time(p)}')),
          ]),
        ),
      );

  Future<void> _rowAction(int i, String action) async {
    final a = _a!;
    switch (action) {
      case 'swap':
        final j = await _choosePerson('Échanger la photo avec…', except: i);
        if (j != null) setState(() => a.swap(i, j));
      case 'gap':
        setState(() => a.insertGap(i));
      case 'remove':
        setState(() => a.removeAt(i));
      case 'clear':
        setState(() => a.clear(i));
      case 'view':
        final p = a.slots[i];
        if (p != null) await _preview(p);
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final kind = kindById(st.template.kind);
    final a = _a;
    final classes = st.classes;
    final unassigned = a == null ? <BatchPhoto>[] : [...a.spare, ...a.discarded];
    final noTime = _photos.where((p) => p.source != TakenSource.exif).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Photos en lot')),
      bottomNavigationBar: a == null || a.assigned == 0 || _busy != null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(children: [
                  Expanded(
                    child: Text('${a.assigned} photo(s) pour ${_people.length} fiche(s)',
                        style: Theme.of(context).textTheme.titleSmall),
                  ),
                  FilledButton.icon(
                    onPressed: _apply,
                    icon: const Icon(Icons.check),
                    label: const Text('Attribuer les photos'),
                  ),
                ]),
              ),
            ),
      body: _busy != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(width: 260, child: LinearProgressIndicator(value: _progress)),
                  const SizedBox(height: 12),
                  Text(_busy!),
                ]),
              ),
            )
          : ListView(padding: const EdgeInsets.all(16), children: [
              Section(
                title: 'Photos prises à la suite',
                subtitle: 'Prenez les photos dans l\'ordre de la liste. Elles sont triées par heure de prise '
                    'et attribuées aux noms dans le même ordre ; vous corrigez ensuite si besoin.',
                children: [
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    if (_desktop)
                      FilledButton.icon(
                        onPressed: _pickFolder,
                        icon: const Icon(Icons.folder_open),
                        label: const Text('Choisir un dossier'),
                      ),
                    (_desktop ? OutlinedButton.icon : FilledButton.icon)(
                      onPressed: _pickFiles,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: Text(_desktop ? 'Choisir des photos' : 'Choisir les photos (tout sélectionner)'),
                    ),
                  ]),
                  if (_photos.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text('${_photos.length} photo(s) chargée(s)'
                        '${noTime > 0 ? ' · $noTime sans heure de prise (EXIF) : heure du nom ou du fichier utilisée' : ''}.'),
                    const SizedBox(height: 10),
                    Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: false, label: Text('Heure de prise'), icon: Icon(Icons.schedule)),
                          ButtonSegment(value: true, label: Text('Nom du fichier'), icon: Icon(Icons.sort_by_alpha)),
                        ],
                        selected: {_byName},
                        onSelectionChanged: (v) => setState(() {
                          _byName = v.first;
                          _rebuild();
                        }),
                      ),
                      if (classes.isNotEmpty)
                        SizedBox(
                          width: 190,
                          child: DropdownButtonFormField<String?>(
                            initialValue: _class,
                            isExpanded: true,
                            decoration: InputDecoration(labelText: kind.group),
                            items: [
                              const DropdownMenuItem(value: null, child: Text('Toute la liste')),
                              for (final c in classes) DropdownMenuItem(value: c, child: Text(c)),
                            ],
                            onChanged: (v) => setState(() {
                              _class = v;
                              _rebuild();
                            }),
                          ),
                        ),
                      FilterChip(
                        label: const Text('Seulement les fiches sans photo'),
                        selected: _onlyMissing ?? false,
                        onSelected: (v) => setState(() {
                          _onlyMissing = v;
                          _rebuild();
                        }),
                      ),
                    ]),
                  ],
                ],
              ),
              if (a != null) ...[
                const SizedBox(height: 12),
                if (_people.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Aucune fiche à compléter avec ces choix.'),
                  )
                else
                  Section(
                    title: 'Attribution',
                    subtitle: 'Menu ⋮ : échanger deux photos, décaler si une personne n\'a pas été photographiée, '
                        'retirer une photo ratée ou en double.',
                    children: [
                      for (var i = 0; i < _people.length; i++) _row(i, _people[i], a.slots[i]),
                    ],
                  ),
                if (unassigned.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Section(
                    title: 'Photos non attribuées (${unassigned.length})',
                    subtitle: 'Touchez une photo pour la donner à une fiche.',
                    children: [
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        for (final p in unassigned)
                          InkWell(
                            onTap: () async {
                              final j = await _choosePerson('Donner cette photo à…');
                              if (j != null) setState(() => a.assignSpare(p, j));
                            },
                            onLongPress: () => _preview(p),
                            child: Column(children: [
                              _thumb(p, w: 64, h: 84),
                              Text(_time(p).split(' ').last, style: Theme.of(context).textTheme.labelSmall),
                            ]),
                          ),
                      ]),
                    ],
                  ),
                ],
              ],
            ]),
    );
  }

  Widget _row(int i, Student s, BatchPhoto? p) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(width: 30, child: Text('${i + 1}', style: theme.textTheme.labelLarge)),
        InkWell(onTap: p == null ? null : () => _preview(p), child: _thumb(p, w: 54, h: 72)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.fullName.isEmpty ? s.matricule : s.fullName,
                style: theme.textTheme.titleSmall, overflow: TextOverflow.ellipsis),
            Text(
              [
                if (s.classe.isNotEmpty) s.classe,
                if (p != null) _time(p) else 'Sans photo',
                if (p != null && p.source == TakenSource.fileDate) 'date du fichier',
                if (s.photo != null) 'remplace la photo actuelle',
              ].join(' · '),
              style: theme.textTheme.bodySmall,
            ),
          ]),
        ),
        PopupMenuButton<String>(
          tooltip: 'Corriger',
          onSelected: (v) => _rowAction(i, v),
          itemBuilder: (_) => [
            if (p != null) const PopupMenuItem(value: 'view', child: Text('Agrandir la photo')),
            const PopupMenuItem(value: 'swap', child: Text('Échanger avec une autre fiche…')),
            const PopupMenuItem(value: 'gap', child: Text('Pas de photo pour cette personne (décaler les suivantes)')),
            if (p != null) const PopupMenuItem(value: 'remove', child: Text('Photo ratée ou en double (retirer et remonter)')),
            if (p != null) const PopupMenuItem(value: 'clear', child: Text('Laisser cette fiche sans photo')),
          ],
        ),
      ]),
    );
  }
}
