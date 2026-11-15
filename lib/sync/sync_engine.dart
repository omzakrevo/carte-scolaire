import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Synchronisation des données entre appareils d'un même compte.
///
/// Les fichiers du dossier de l'application (projets, élèves, photos, notes, présences,
/// modèles) sont comparés à ceux du serveur. Pour chaque fichier, on garde l'empreinte
/// connue lors de la dernière synchronisation (la « base ») :
/// - modifié seulement ici → envoyé ; modifié seulement ailleurs → reçu ;
/// - modifié des deux côtés → la version la plus récente gagne (une suppression ne
///   l'emporte jamais sur une modification) ;
/// - la liste des projets (projects.json) est fusionnée.

/// Fichier tel que le serveur le connaît.
class RemoteFile {
  final String path;
  final String hash;
  final int size;
  final bool deleted;
  final DateTime updated;
  const RemoteFile(this.path, this.hash, this.size, this.deleted, this.updated);
}

/// Stockage distant (Supabase dans l'application, mémoire dans les tests).
abstract class SyncBackend {
  Future<List<RemoteFile>> list();
  Future<Uint8List> download(String path);
  Future<void> upload(String path, Uint8List bytes, String hash);
  Future<void> delete(String path);
}

class LocalFile {
  final String path;
  final String hash;
  final int size;
  final int mtime;
  const LocalFile(this.path, this.hash, this.size, this.mtime);
}

class SyncReport {
  final List<String> uploaded = [];
  final List<String> downloaded = [];
  final List<String> deletedLocal = [];
  final List<String> deletedRemote = [];
  final List<String> errors = [];
  int bytesUp = 0, bytesDown = 0;

  /// Fichiers modifiés sur cet appareil par la synchronisation.
  List<String> get changedLocally => [...downloaded, ...deletedLocal];
  bool get nothing => uploaded.isEmpty && downloaded.isEmpty && deletedLocal.isEmpty && deletedRemote.isEmpty;
}

typedef SyncProgress = void Function(int done, int total, String path);

const projectsIndex = 'projects.json';

/// Fichiers synchronisés : liste des projets, modèles enregistrés, contenu des projets.
/// Restent sur l'appareil : licence et mot de passe, réglages de synchronisation et de lecture IA.
bool isSyncedPath(String p) {
  if (p.endsWith('.tmp')) return false;
  return p == projectsIndex || p == 'templates.json' || p.startsWith('projects/');
}

Future<String> hashBytes(List<int> bytes) async {
  final h = await Sha256().hash(bytes);
  return base64Url.encode(h.bytes).replaceAll('=', '');
}

class SyncEngine {
  final Directory root;
  final SyncBackend backend;

  /// Empreintes de la dernière synchronisation, avec taille et date pour éviter de tout relire.
  final Map<String, LocalFile> base;

  SyncEngine(this.root, this.backend, Map<String, LocalFile>? base) : base = base ?? {};

  String get _sep => Platform.pathSeparator;
  File _file(String rel) => File('${root.path}$_sep${rel.replaceAll('/', _sep)}');

  // ---------------- État enregistré ----------------

  static Map<String, LocalFile> decodeBase(Object? json) {
    final out = <String, LocalFile>{};
    if (json is Map) {
      json.forEach((k, v) {
        if (v is List && v.length >= 3) {
          out['$k'] = LocalFile('$k', '${v[0]}', (v[1] as num).toInt(), (v[2] as num).toInt());
        }
      });
    }
    return out;
  }

  Map<String, Object> encodeBase() => {
        for (final e in base.values) e.path: [e.hash, e.size, e.mtime]
      };

  // ---------------- Fichiers locaux ----------------

  Future<Map<String, LocalFile>> scan() async {
    final out = <String, LocalFile>{};
    if (!await root.exists()) return out;
    await for (final e in root.list(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      final rel = e.path.substring(root.path.length + 1).replaceAll(_sep, '/');
      if (!isSyncedPath(rel)) continue;
      final st = await e.stat();
      final mtime = st.modified.millisecondsSinceEpoch;
      final known = base[rel];
      final hash = (known != null && known.size == st.size && known.mtime == mtime)
          ? known.hash
          : await hashBytes(await e.readAsBytes());
      out[rel] = LocalFile(rel, hash, st.size, mtime);
    }
    return out;
  }

  Future<LocalFile> _write(String rel, Uint8List bytes, String hash) async {
    final f = _file(rel);
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(f.path);
    final st = await f.stat();
    return LocalFile(rel, hash, st.size, st.modified.millisecondsSinceEpoch);
  }

  Future<void> _deleteLocal(String rel) async {
    final f = _file(rel);
    if (await f.exists()) await f.delete();
  }

  // ---------------- Synchronisation ----------------

  Future<SyncReport> run({SyncProgress? progress}) async {
    final report = SyncReport();
    final local = await scan();
    final remoteList = await backend.list();
    final remote = {for (final r in remoteList) r.path: r};

    final paths = {...local.keys, ...remote.keys, ...base.keys}.where(isSyncedPath).toList()..sort();
    paths.remove(projectsIndex);
    // Les petits fichiers (fiches, notes) d'abord, les photos ensuite.
    paths.sort((a, b) {
      final pa = a.endsWith('.json') ? 0 : 1, pb = b.endsWith('.json') ? 0 : 1;
      return pa != pb ? pa - pb : a.compareTo(b);
    });

    var done = 0;
    final total = paths.length + 1;
    for (final p in paths) {
      progress?.call(done++, total, p);
      try {
        await _syncOne(p, local[p], remote[p], report);
      } catch (e) {
        report.errors.add('$p : $e');
      }
    }
    progress?.call(done++, total, projectsIndex);
    try {
      await _syncIndex(local[projectsIndex], remote[projectsIndex], report);
    } catch (e) {
      report.errors.add('$projectsIndex : $e');
    }
    progress?.call(total, total, '');
    return report;
  }

  Future<void> _syncOne(String p, LocalFile? l, RemoteFile? r, SyncReport report) async {
    final lh = l?.hash;
    final rh = (r == null || r.deleted) ? null : r.hash;
    final bh = base[p]?.hash;

    if (lh == rh) {
      if (l == null) {
        base.remove(p);
      } else {
        base[p] = l;
      }
      return;
    }
    final localChanged = lh != bh;
    final remoteChanged = rh != bh;
    bool upload;
    if (localChanged && !remoteChanged) {
      upload = true;
    } else if (!localChanged && remoteChanged) {
      upload = false;
    } else {
      // Modifié des deux côtés : on garde une modification plutôt qu'une suppression,
      // sinon la plus récente.
      if (lh == null) {
        upload = false;
      } else if (rh == null) {
        upload = true;
      } else {
        upload = l!.mtime >= r!.updated.millisecondsSinceEpoch;
      }
    }

    if (upload) {
      if (l == null) {
        await backend.delete(p);
        base.remove(p);
        report.deletedRemote.add(p);
      } else {
        final bytes = await _file(p).readAsBytes();
        await backend.upload(p, bytes, l.hash);
        base[p] = l;
        report
          ..uploaded.add(p)
          ..bytesUp += bytes.length;
      }
    } else {
      if (rh == null) {
        await _deleteLocal(p);
        base.remove(p);
        report.deletedLocal.add(p);
      } else {
        final bytes = await backend.download(p);
        final got = await hashBytes(bytes);
        if (got != rh) throw const FormatException('fichier reçu incomplet');
        base[p] = await _write(p, bytes, rh);
        report
          ..downloaded.add(p)
          ..bytesDown += bytes.length;
      }
    }
  }

  /// La liste des projets est fusionnée : projets des deux appareils, sans ceux supprimés.
  Future<void> _syncIndex(LocalFile? l, RemoteFile? r, SyncReport report) async {
    final rh = (r == null || r.deleted) ? null : r.hash;
    Map<String, dynamic> localJson = {};
    Map<String, dynamic> remoteJson = {};
    if (l != null) {
      try {
        localJson = jsonDecode(await _file(projectsIndex).readAsString()) as Map<String, dynamic>;
      } catch (_) {}
    }
    if (rh != null && rh != l?.hash) {
      try {
        remoteJson = jsonDecode(utf8.decode(await backend.download(projectsIndex))) as Map<String, dynamic>;
      } catch (_) {}
    }
    final merged = mergeProjectIndex(localJson, remoteJson,
        exists: (id) => _file('projects/$id/project.json').existsSync());
    final text = jsonEncode(merged);
    final bytes = Uint8List.fromList(utf8.encode(text));
    final hash = await hashBytes(bytes);
    LocalFile written;
    if (hash != l?.hash) {
      written = await _write(projectsIndex, bytes, hash);
      report.downloaded.add(projectsIndex);
    } else {
      written = l!;
    }
    if (hash != rh) {
      await backend.upload(projectsIndex, bytes, hash);
      report.uploaded.add(projectsIndex);
    }
    base[projectsIndex] = written;
  }
}

/// Union des projets des deux listes (la fiche la plus récente l'emporte), limitée aux
/// projets présents sur l'appareil. Le projet ouvert reste celui de cet appareil.
Map<String, dynamic> mergeProjectIndex(Map<String, dynamic> local, Map<String, dynamic> remote,
    {required bool Function(String id) exists}) {
  final byId = <String, Map<String, dynamic>>{};
  final order = <String>[];
  for (final src in [local, remote]) {
    for (final p in (src['projects'] as List? ?? const [])) {
      if (p is! Map) continue;
      final m = Map<String, dynamic>.from(p);
      final id = '${m['id'] ?? ''}';
      if (id.isEmpty) continue;
      final old = byId[id];
      if (old == null) {
        order.add(id);
        byId[id] = m;
      } else if ('${m['updated'] ?? ''}'.compareTo('${old['updated'] ?? ''}') > 0) {
        byId[id] = m;
      }
    }
  }
  final list = [
    for (final id in order)
      if (exists(id)) byId[id]!
  ];
  list.sort((a, b) => '${b['updated'] ?? ''}'.compareTo('${a['updated'] ?? ''}'));
  var current = local['current'] as String? ?? remote['current'] as String?;
  if (!list.any((p) => p['id'] == current)) current = list.isEmpty ? null : '${list.first['id']}';
  return {'current': current, 'projects': list};
}
