import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../app_state.dart';
import '../models.dart';

/// Sauvegarde locale du projet : project.json + un fichier JPEG par photo.
class Storage {
  static final Map<String, int> _written = {};

  static Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}carte_scolaire');
    await Directory('${dir.path}${Platform.pathSeparator}photos').create(recursive: true);
    return dir;
  }

  static String _photoPath(Directory d, String id) =>
      '${d.path}${Platform.pathSeparator}photos${Platform.pathSeparator}$id.jpg';

  static Future<void> save(AppState s) async {
    final d = await _dir();
    final json = {
      'version': 1,
      'template': s.template.toJson(),
      'school': s.school.toJson(),
      'students': s.students.map((e) => e.toJson()).toList(),
    };
    final saved = File('${d.path}${Platform.pathSeparator}templates.json');
    await saved.writeAsString(jsonEncode(s.savedTemplates.map((e) => e.toJson()).toList()));
    final tmp = File('${d.path}${Platform.pathSeparator}project.json.tmp');
    await tmp.writeAsString(jsonEncode(json));
    await tmp.rename('${d.path}${Platform.pathSeparator}project.json');

    final ids = <String>{};
    for (final st in s.students) {
      ids.add(st.id);
      final f = File(_photoPath(d, st.id));
      if (st.photo == null) {
        if (await f.exists()) await f.delete();
        _written.remove(st.id);
      } else if (_written[st.id] != st.photoVersion || !await f.exists()) {
        await f.writeAsBytes(st.photo!, flush: true);
        _written[st.id] = st.photoVersion;
      }
    }
    // Supprime les photos des élèves retirés.
    final photos = Directory('${d.path}${Platform.pathSeparator}photos');
    await for (final e in photos.list()) {
      final name = e.uri.pathSegments.last;
      if (name.endsWith('.jpg') && !ids.contains(name.replaceAll('.jpg', ''))) {
        await e.delete();
      }
    }
  }

  static Future<void> load(AppState s) async {
    final d = await _dir();
    final saved = File('${d.path}${Platform.pathSeparator}templates.json');
    if (await saved.exists()) {
      s.savedTemplates
        ..clear()
        ..addAll((jsonDecode(await saved.readAsString()) as List)
            .map((e) => SavedTemplate.fromJson(e as Map<String, dynamic>)));
    }
    final f = File('${d.path}${Platform.pathSeparator}project.json');
    if (!await f.exists()) return;
    final json = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    s.template = CardTemplate.fromJson(json['template'] ?? {});
    s.school = SchoolInfo.fromJson(json['school'] ?? {});
    s.students.clear();
    for (final j in (json['students'] as List? ?? [])) {
      final st = Student.fromJson(j as Map<String, dynamic>);
      final pf = File(_photoPath(d, st.id));
      if (await pf.exists()) {
        st.photo = await pf.readAsBytes();
        _written[st.id] = st.photoVersion;
      }
      s.students.add(st);
    }
  }
}
