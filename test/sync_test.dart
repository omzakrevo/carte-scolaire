import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:carte_scolaire/sync/supabase_backend.dart';
import 'package:carte_scolaire/sync/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Serveur en mémoire.
class MemoryBackend implements SyncBackend {
  final files = <String, Uint8List>{};
  final rows = <String, RemoteFile>{};
  int clock = 0;

  @override
  Future<List<RemoteFile>> list() async => rows.values.toList();
  @override
  Future<Uint8List> download(String path) async => files[path]!;
  @override
  Future<void> upload(String path, Uint8List bytes, String hash) async {
    files[path] = bytes;
    rows[path] = RemoteFile(path, hash, bytes.length, false, DateTime.now().add(Duration(seconds: clock++)));
  }

  @override
  Future<void> delete(String path) async {
    files.remove(path);
    rows[path] = RemoteFile(path, '', 0, true, DateTime.now());
  }
}

class Device {
  final Directory dir;
  final MemoryBackend server;
  Map<String, LocalFile> base = {};
  Device(this.dir, this.server);

  File f(String p) => File('${dir.path}/$p');
  void write(String p, String text) {
    f(p).parent.createSync(recursive: true);
    f(p).writeAsStringSync(text);
  }

  String? read(String p) => f(p).existsSync() ? f(p).readAsStringSync() : null;

  Future<SyncReport> sync() async {
    final e = SyncEngine(dir, server, Map.of(base));
    // L'état passe par le disque (JSON) entre deux synchronisations.
    final saved = SyncEngine.decodeBase(jsonDecode(jsonEncode(e.encodeBase())));
    e.base
      ..clear()
      ..addAll(saved);
    final r = await e.run();
    base = e.base;
    return r;
  }
}

String index(List<(String, String)> projects, String current) => jsonEncode({
      'current': current,
      'projects': [
        for (final (id, updated) in projects) {'id': id, 'name': id, 'updated': updated}
      ],
    });

void main() {
  late Directory tmp;
  late MemoryBackend server;
  late Device pc, phone;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sync');
    server = MemoryBackend();
    pc = Device(Directory('${tmp.path}/pc')..createSync(), server);
    phone = Device(Directory('${tmp.path}/phone')..createSync(), server);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('les données de l\'ordinateur arrivent sur le téléphone, et inversement', () async {
    pc.write('projects.json', index([('a', '2026-11-01')], 'a'));
    pc.write('projects/a/project.json', '{"students":1}');
    pc.write('projects/a/photos/s1.jpg', 'PHOTO1');
    pc.write('security.json', 'licence du PC');
    pc.write('sync.json', 'réglages');

    final r1 = await pc.sync();
    expect(r1.uploaded, containsAll(['projects/a/project.json', 'projects/a/photos/s1.jpg', 'projects.json']));
    expect(server.files.keys, isNot(contains('security.json')));
    expect(server.files.keys, isNot(contains('sync.json')));

    phone.write('projects.json', index([('b', '2026-11-02')], 'b'));
    phone.write('projects/b/project.json', '{"students":2}');
    phone.write('security.json', 'licence du téléphone');
    await phone.sync();
    expect(phone.read('projects/a/photos/s1.jpg'), 'PHOTO1');
    expect(phone.read('security.json'), 'licence du téléphone');
    final idx = jsonDecode(phone.read('projects.json')!) as Map;
    expect((idx['projects'] as List).map((e) => e['id']), ['b', 'a']);
    expect(idx['current'], 'b');

    await pc.sync();
    expect(pc.read('projects/b/project.json'), '{"students":2}');
    final pcIdx = jsonDecode(pc.read('projects.json')!) as Map;
    expect(pcIdx['current'], 'a');
    expect((pcIdx['projects'] as List).length, 2);

    // Plus rien à faire ensuite.
    final again = await pc.sync();
    expect(again.nothing, isTrue);
  });

  test('modifications, suppressions et conflits', () async {
    pc.write('projects.json', index([('a', '1'), ('c', '1')], 'a'));
    pc.write('projects/a/project.json', 'v1');
    pc.write('projects/a/gestion.json', 'notes v1');
    pc.write('projects/c/project.json', 'c');
    await pc.sync();
    await phone.sync();

    // Le téléphone modifie les notes, l'ordinateur supprime le projet c.
    phone.write('projects/a/gestion.json', 'notes v2');
    pc.f('projects/c/project.json').deleteSync();
    await phone.sync();
    final r = await pc.sync();
    expect(r.downloaded, contains('projects/a/gestion.json'));
    expect(r.deletedRemote, contains('projects/c/project.json'));
    expect(pc.read('projects/a/gestion.json'), 'notes v2');

    final r2 = await phone.sync();
    expect(r2.deletedLocal, contains('projects/c/project.json'));
    expect((jsonDecode(phone.read('projects.json')!)['projects'] as List).map((e) => e['id']), ['a']);

    // Les deux modifient le même fichier : la version la plus récente gagne.
    pc.write('projects/a/project.json', 'pc');
    await pc.sync();
    phone.write('projects/a/project.json', 'téléphone');
    // Date du fichier du téléphone plus ancienne que l'envoi du PC.
    phone.f('projects/a/project.json').setLastModifiedSync(DateTime(2020));
    await phone.sync();
    expect(phone.read('projects/a/project.json'), 'pc');

    // Supprimé d'un côté, modifié de l'autre : la modification est gardée.
    pc.write('projects/a/photos/x.jpg', 'X');
    await pc.sync();
    await phone.sync();
    phone.f('projects/a/photos/x.jpg').deleteSync();
    pc.write('projects/a/photos/x.jpg', 'X2');
    await pc.sync();
    await phone.sync();
    expect(phone.read('projects/a/photos/x.jpg'), 'X2');
  });

  test('fusion de la liste des projets', () {
    final m = mergeProjectIndex(
      jsonDecode(index([('a', '2026-01-02'), ('b', '2026-01-01')], 'a')),
      jsonDecode(index([('b', '2026-01-05'), ('z', '2026-01-03')], 'z')),
      exists: (id) => id != 'z',
    );
    expect(m['current'], 'a');
    expect((m['projects'] as List).map((e) => '${e['id']}${e['updated']}'), ['b2026-01-05', 'a2026-01-02']);
  });

  test('requêtes envoyées au serveur Supabase', () async {
    final calls = <http.Request>[];
    final client = MockClient((req) async {
      calls.add(req);
      final p = req.url.path;
      if (p == '/auth/v1/token') {
        return http.Response(
            jsonEncode({
              'access_token': 'A',
              'refresh_token': 'R',
              'expires_in': 3600,
              'user': {'id': 'u1', 'email': 'moi@test.bf'},
            }),
            200);
      }
      if (p == '/rest/v1/cs_sync_access') return http.Response('[{"active":true}]', 200);
      if (p == '/rest/v1/cs_sync_files' && req.method == 'GET') {
        return http.Response(
            '[{"path":"projects.json","hash":"h","size":3,"deleted":false,"updated_at":"2026-11-14T10:00:00Z"}]', 200);
      }
      if (p == '/rest/v1/cs_sync_files') return http.Response('', 201);
      if (p.startsWith('/storage/v1/object/authenticated/')) return http.Response.bytes([1, 2, 3], 200);
      if (p.startsWith('/storage/v1/object/')) return http.Response('{"Key":"x"}', 200);
      return http.Response('?', 404);
    });
    final b = SupabaseBackend('https://supa.exemple.bf/', 'anon', client: client, device: 'PC');
    final s = await b.signIn('moi@test.bf', 'secret');
    expect(s.userId, 'u1');
    expect(calls.first.url.toString(), 'https://supa.exemple.bf/auth/v1/token?grant_type=password');
    expect(calls.first.headers['apikey'], 'anon');
    expect(await b.hasAccess(), isTrue);

    final l = await b.list();
    expect(l.single.path, 'projects.json');
    expect(l.single.updated, DateTime.utc(2026, 11, 14, 10));

    await b.upload('projects/a b/photos/s1.jpg', Uint8List.fromList([9]), 'H');
    final put = calls[calls.length - 2];
    expect(put.url.path, '/storage/v1/object/carte-scolaire/u1/projects/a%20b/photos/s1.jpg');
    expect(put.headers['authorization'], 'Bearer A');
    expect(put.headers['x-upsert'], 'true');
    final row = calls.last;
    expect(row.url.query, 'on_conflict=user_id,path');
    expect(jsonDecode(row.body)['hash'], 'H');
    expect(row.headers['prefer'], contains('merge-duplicates'));

    expect(await b.download('projects.json'), [1, 2, 3]);
    await b.delete('projects/x.jpg');
    expect(calls.last.method, 'DELETE');
  });
}
