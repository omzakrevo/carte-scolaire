import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../app_state.dart';
import '../models.dart';

/// Stockage local, entièrement sur l'appareil :
///
/// carte_scolaire/
///   projects.json              liste des projets + projet ouvert
///   templates.json             « Mes modèles » (communs à tous les projets)
///   projects/<id>/project.json modèle, établissement, élèves
///   projects/<id>/photos/      <élève>.jpg (recadrée) et <élève>_orig.jpg
class Storage {
  static final Map<String, int> _written = {};
  static String get _sep => Platform.pathSeparator;

  static Future<Directory> baseDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}${_sep}carte_scolaire');
    await dir.create(recursive: true);
    return dir;
  }

  static Future<Directory> _projectDir(String id) async {
    final d = Directory('${(await baseDir()).path}${_sep}projects$_sep$id');
    await Directory('${d.path}${_sep}photos').create(recursive: true);
    return d;
  }

  static String _photo(Directory d, String sid, {bool orig = false}) =>
      '${d.path}${_sep}photos$_sep$sid${orig ? '_orig' : ''}.jpg';

  static Future<void> _writeJson(File f, Object json) async {
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(json));
    await tmp.rename(f.path);
  }

  // ---------------- Index des projets ----------------

  static Future<(List<ProjectInfo>, String?)> loadIndex() async {
    final base = await baseDir();
    await _migrateLegacy(base);
    final f = File('${base.path}${_sep}projects.json');
    if (!await f.exists()) return (<ProjectInfo>[], null);
    final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    final list = (j['projects'] as List? ?? []).map((e) => ProjectInfo.fromJson(e as Map<String, dynamic>)).toList();
    return (list, j['current'] as String?);
  }

  static Future<void> saveIndex(List<ProjectInfo> projects, String current) async {
    final base = await baseDir();
    await _writeJson(File('${base.path}${_sep}projects.json'), {
      'current': current,
      'projects': projects.map((e) => e.toJson()).toList(),
    });
  }

  /// Version 1 de l'application : un seul projet à la racine.
  static Future<void> _migrateLegacy(Directory base) async {
    final legacy = File('${base.path}${_sep}project.json');
    final index = File('${base.path}${_sep}projects.json');
    if (!await legacy.exists() || await index.exists()) return;
    final info = ProjectInfo(name: 'Mon premier projet');
    final dest = await _projectDir(info.id);
    await legacy.rename('${dest.path}${_sep}project.json');
    final oldPhotos = Directory('${base.path}${_sep}photos');
    if (await oldPhotos.exists()) {
      await for (final e in oldPhotos.list()) {
        if (e is File) await e.rename('${dest.path}${_sep}photos$_sep${e.uri.pathSegments.last}');
      }
    }
    await saveIndex([info], info.id);
  }

  // ---------------- Modèles enregistrés ----------------

  static Future<List<SavedTemplate>> loadSavedTemplates() async {
    final f = File('${(await baseDir()).path}${_sep}templates.json');
    if (!await f.exists()) return [];
    return (jsonDecode(await f.readAsString()) as List)
        .map((e) => SavedTemplate.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> saveSavedTemplates(List<SavedTemplate> list) async {
    await _writeJson(File('${(await baseDir()).path}${_sep}templates.json'), list.map((e) => e.toJson()).toList());
  }

  // ---------------- Contenu d'un projet ----------------

  static Future<void> saveProject(AppState s) async {
    final d = await _projectDir(s.projectId);
    await _writeJson(File('${d.path}${_sep}project.json'), {
      'version': 2,
      'name': s.projectName,
      'template': s.template.toJson(),
      'school': s.school.toJson(),
      'layout': {'margin': s.layout.marginMm, 'gap': s.layout.gapMm, 'a4': s.layout.a4Sheet},
      'students': s.students.map((e) => e.toJson()).toList(),
    });

    final keep = <String>{};
    for (final st in s.students) {
      final key = '${s.projectId}/${st.id}';
      final f = File(_photo(d, st.id));
      final fo = File(_photo(d, st.id, orig: true));
      keep
        ..add('${st.id}.jpg')
        ..add('${st.id}_orig.jpg');
      if (_written[key] == st.photoVersion && await f.exists() == (st.photo != null)) continue;
      if (st.photo == null) {
        if (await f.exists()) await f.delete();
      } else {
        await f.writeAsBytes(st.photo!, flush: true);
      }
      if (st.original == null) {
        if (await fo.exists()) await fo.delete();
      } else {
        await fo.writeAsBytes(st.original!, flush: true);
      }
      _written[key] = st.photoVersion;
    }
    await for (final e in Directory('${d.path}${_sep}photos').list()) {
      if (e is File && !keep.contains(e.uri.pathSegments.last)) await e.delete();
    }
  }

  static Future<void> loadProject(AppState s, String id) async {
    final d = await _projectDir(id);
    final f = File('${d.path}${_sep}project.json');
    s.projectId = id;
    s.students.clear();
    s.currentIndex = 0;
    if (!await f.exists()) {
      s.template = CardTemplate();
      s.school = SchoolInfo();
      return;
    }
    final json = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    s.template = CardTemplate.fromJson(json['template'] ?? {});
    s.school = SchoolInfo.fromJson(json['school'] ?? {});
    final l = json['layout'] as Map<String, dynamic>?;
    if (l != null) {
      s.layout
        ..marginMm = (l['margin'] ?? 6).toDouble()
        ..gapMm = (l['gap'] ?? 3).toDouble()
        ..a4Sheet = l['a4'] ?? true;
    }
    for (final j in (json['students'] as List? ?? [])) {
      final st = Student.fromJson(j as Map<String, dynamic>);
      final pf = File(_photo(d, st.id));
      if (await pf.exists()) st.photo = await pf.readAsBytes();
      final po = File(_photo(d, st.id, orig: true));
      if (await po.exists()) st.original = await po.readAsBytes();
      _written['$id/${st.id}'] = st.photoVersion;
      s.students.add(st);
    }
  }

  static Future<void> duplicateProject(String fromId, String toId) async {
    final src = await _projectDir(fromId);
    final dst = await _projectDir(toId);
    await for (final e in src.list(recursive: true)) {
      if (e is! File) continue;
      final rel = e.path.substring(src.path.length + 1);
      final target = File('${dst.path}$_sep$rel');
      await target.parent.create(recursive: true);
      await e.copy(target.path);
    }
  }

  static Future<void> deleteProject(String id) async {
    final d = Directory('${(await baseDir()).path}${_sep}projects$_sep$id');
    if (await d.exists()) await d.delete(recursive: true);
    _written.removeWhere((k, _) => k.startsWith('$id/'));
  }
}
