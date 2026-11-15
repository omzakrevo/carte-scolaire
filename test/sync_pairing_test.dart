import 'dart:convert';
import 'dart:io';

import 'package:carte_scolaire/sync/pairing.dart';
import 'package:carte_scolaire/sync/sync_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Serveur Supabase simulé : comptes, accès par licence, dépôt de code, fichiers.
class FakeSupabase {
  final users = <String, String>{}; // e-mail → mot de passe
  final access = <String>{};
  final pairs = <String, String>{};
  final rows = <Map<String, dynamic>>[];
  final objects = <String, List<int>>{};
  final licensesSeen = <String>[];

  String? _user(http.Request r) {
    final a = r.headers['authorization'];
    return a?.substring('Bearer tok-'.length);
  }

  http.Response _session(String email) => http.Response(
      jsonEncode({
        'access_token': 'tok-$email',
        'refresh_token': 'r',
        'expires_in': 3600,
        'user': {'id': 'id-$email', 'email': email},
      }),
      200);

  late final client = MockClient((r) async {
    final p = r.url.path;
    final body = r.body.isEmpty ? <String, dynamic>{} : jsonDecode(r.body);
    if (p == '/auth/v1/signup') {
      users[body['email']] = body['password'];
      return _session(body['email']);
    }
    if (p == '/auth/v1/token') {
      return users[body['email']] == body['password']
          ? _session(body['email'])
          : http.Response('{"error_description":"Invalid login credentials"}', 400);
    }
    if (p == '/rest/v1/rpc/cs_register_license') {
      licensesSeen.add(body['code']);
      if ('${body['code']}'.contains('sync')) access.add(_user(r)!);
      return http.Response('{"active":true}', 200);
    }
    if (p == '/rest/v1/rpc/cs_pair_put') {
      pairs[body['pair_id']] = body['data'];
      return http.Response('', 204);
    }
    if (p == '/rest/v1/rpc/cs_pair_take') {
      final v = pairs.remove(body['pair_id']);
      return http.Response(jsonEncode(v), 200);
    }
    if (p == '/rest/v1/cs_sync_access') {
      return http.Response(access.contains(_user(r)) ? '[{"active":true}]' : '[]', 200);
    }
    if (p == '/rest/v1/cs_sync_files' && r.method == 'GET') return http.Response(jsonEncode(rows), 200);
    if (p == '/rest/v1/cs_sync_files') {
      rows.removeWhere((e) => e['path'] == body['path']);
      rows.add({...body, 'updated_at': DateTime.now().toUtc().toIso8601String()});
      return http.Response('', 201);
    }
    if (p.startsWith('/storage/v1/object/authenticated/')) {
      return http.Response.bytes(objects[p.substring('/storage/v1/object/authenticated/'.length)] ?? [], 200);
    }
    if (p.startsWith('/storage/v1/object/')) {
      objects[p.substring('/storage/v1/object/'.length)] = r.bodyBytes;
      return http.Response('{}', 200);
    }
    return http.Response('?', 404);
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final tmp = Directory.systemTemp.createTempSync('pair');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'), (_) async => tmp.path);

  test('codes d\'appairage', () async {
    final c = newPairingCode();
    expect(RegExp(r'^[A-Z2-9]{4}-[A-Z2-9]{3}-[A-Z2-9]{3}$').hasMatch(c), isTrue);
    expect(normalizePairingCode(pairingQr(c)), c);
    expect(normalizePairingCode(c.toLowerCase().replaceAll('-', ' ')), c);
    expect(normalizePairingCode('ABC'), isNull);
    final sealed = await sealCredentials(c, 'a@b.c', 'secret');
    expect(sealed, isNot(contains('secret')));
    expect(await openCredentials(c, sealed), ('a@b.c', 'secret'));
    expect(await openCredentials(newPairingCode(), sealed), isNull);
    expect((await pairingId(c)).length, 64);
    final (mail, pass) = newAccountCredentials();
    expect(mail, endsWith('@carte-scolaire.app'));
    expect(pass.length, 32);
  });

  test('premier appareil activé tout seul, second relié par le code', () async {
    final srv = FakeSupabase();
    SyncController device(String licence, {bool allowed = true, bool server = true}) => SyncController(
          licensed: () => allowed,
          licenseCode: () => licence,
          server: () => server ? ('https://vps.exemple', 'anon') : ('https://vps.exemple', ''),
          beforeSync: () async {},
          afterSync: (_) async {},
          lastEdit: () => DateTime(2000),
          httpClient: srv.client,
        );

    expect(await device('x', server: false).activate(), contains('pas encore configuré'));
    expect(await device('x', allowed: false).activate(), contains('licence'));

    final pc = device('CODE-PC-sync');
    expect(await pc.activate(), isNull);
    expect(pc.connected, isTrue);
    expect(srv.users.keys.single, pc.email);
    expect(srv.licensesSeen, ['CODE-PC-sync']);
    File('${tmp.path}/carte_scolaire/projects/p1/project.json')
      ..createSync(recursive: true)
      ..writeAsStringSync('{"students":[]}');
    final r = await pc.syncNow();
    expect(pc.lastError, isNull);
    expect(r!.uploaded, contains('projects/p1/project.json'));

    final (code, err) = await pc.newPairing();
    expect(err, isNull);
    final phone = device('CODE-TEL-sync');
    expect(await phone.join('ABCD-EFG-HJK'), contains('expiré'));
    expect(await phone.join(pairingQr(code!)), isNull);
    expect(phone.email, pc.email);
    expect(srv.licensesSeen.last, 'CODE-TEL-sync');
    // Code à usage unique.
    expect(await device('z-sync').join(code), contains('expiré'));
    await phone.syncNow();
    expect(phone.lastError, isNull);
  });
}
