import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'sync_engine.dart';

/// Accès au serveur Supabase (auto-hébergé) : compte, table des fichiers, stockage.
/// Voir docs/sync/supabase_setup.sql pour préparer le serveur.
class SyncAuthError implements Exception {
  final String message;
  const SyncAuthError(this.message);
  @override
  String toString() => message;
}

class SyncSession {
  String accessToken;
  String refreshToken;
  DateTime expires;
  final String userId;
  final String email;
  SyncSession(this.accessToken, this.refreshToken, this.expires, this.userId, this.email);

  Map<String, dynamic> toJson() =>
      {'a': accessToken, 'r': refreshToken, 'e': expires.toIso8601String(), 'u': userId, 'm': email};

  static SyncSession? fromJson(Object? j) {
    if (j is! Map) return null;
    try {
      return SyncSession('${j['a']}', '${j['r']}', DateTime.parse('${j['e']}'), '${j['u']}', '${j['m']}');
    } catch (_) {
      return null;
    }
  }
}

class SupabaseBackend implements SyncBackend {
  final String url;
  final String anonKey;
  final String device;
  SyncSession? session;
  final http.Client client;

  static const bucket = 'carte-scolaire';
  static const table = 'cs_sync_files';

  /// Appelé quand les jetons sont renouvelés (pour les enregistrer).
  void Function(SyncSession)? onSession;

  SupabaseBackend(String url, this.anonKey, {this.session, this.device = '', http.Client? client})
      : url = url.trim().replaceAll(RegExp(r'/+$'), ''),
        client = client ?? http.Client();

  Map<String, String> get _anon => {'apikey': anonKey, 'content-type': 'application/json'};

  Future<Map<String, String>> _auth([Map<String, String> extra = const {}]) async {
    await _fresh();
    return {'apikey': anonKey, 'authorization': 'Bearer ${session!.accessToken}', ...extra};
  }

  static String _message(http.Response r) {
    try {
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      if (j is Map) {
        return '${j['error_description'] ?? j['msg'] ?? j['message'] ?? j['error'] ?? 'erreur ${r.statusCode}'}';
      }
    } catch (_) {}
    return 'erreur ${r.statusCode}';
  }

  SyncSession _readSession(Map j, {String? email}) {
    final user = (j['user'] as Map?) ?? const {};
    return SyncSession(
      '${j['access_token']}',
      '${j['refresh_token']}',
      DateTime.now().add(Duration(seconds: (j['expires_in'] as num? ?? 3600).toInt())),
      '${user['id'] ?? session?.userId ?? ''}',
      '${user['email'] ?? email ?? session?.email ?? ''}',
    );
  }

  /// Connexion avec l'adresse e-mail et le mot de passe du compte.
  Future<SyncSession> signIn(String email, String password) async {
    final r = await client.post(Uri.parse('$url/auth/v1/token?grant_type=password'),
        headers: _anon, body: jsonEncode({'email': email.trim(), 'password': password}));
    if (r.statusCode != 200) {
      final m = _message(r);
      throw SyncAuthError(m.toLowerCase().contains('invalid') ? 'Adresse e-mail ou mot de passe incorrect.' : m);
    }
    session = _readSession(jsonDecode(utf8.decode(r.bodyBytes)) as Map, email: email);
    onSession?.call(session!);
    return session!;
  }

  /// Création du compte. Selon le serveur, l'adresse doit ensuite être confirmée.
  Future<bool> signUp(String email, String password) async {
    final r = await client.post(Uri.parse('$url/auth/v1/signup'),
        headers: _anon, body: jsonEncode({'email': email.trim(), 'password': password}));
    if (r.statusCode != 200) throw SyncAuthError(_message(r));
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map;
    if (j['access_token'] != null) {
      session = _readSession(j, email: email);
      onSession?.call(session!);
      return true;
    }
    return false; // confirmation par e-mail demandée
  }

  Future<void> _fresh() async {
    final s = session;
    if (s == null) throw const SyncAuthError('Non connecté.');
    if (s.expires.isAfter(DateTime.now().add(const Duration(minutes: 1)))) return;
    final r = await client.post(Uri.parse('$url/auth/v1/token?grant_type=refresh_token'),
        headers: _anon, body: jsonEncode({'refresh_token': s.refreshToken}));
    if (r.statusCode != 200) throw const SyncAuthError('Session expirée : reconnectez-vous.');
    session = _readSession(jsonDecode(utf8.decode(r.bodyBytes)) as Map);
    onSession?.call(session!);
  }

  /// Le compte a-t-il l'option multi-appareil (activée par l'administrateur sur le serveur) ?
  Future<bool> hasAccess() async {
    final r = await client.get(Uri.parse('$url/rest/v1/cs_sync_access?select=active'), headers: await _auth());
    if (r.statusCode != 200) throw SyncAuthError('Serveur : ${_message(r)}');
    final l = jsonDecode(utf8.decode(r.bodyBytes)) as List;
    return l.any((e) => e is Map && e['active'] == true);
  }

  String _object(String path) => '${session!.userId}/${path.split('/').map(Uri.encodeComponent).join('/')}';

  @override
  Future<List<RemoteFile>> list() async {
    final out = <RemoteFile>[];
    const page = 1000;
    for (var offset = 0;; offset += page) {
      final r = await client.get(
        Uri.parse('$url/rest/v1/$table?select=path,hash,size,deleted,updated_at&order=path&limit=$page&offset=$offset'),
        headers: await _auth(),
      );
      if (r.statusCode != 200) throw SyncAuthError('Serveur : ${_message(r)}');
      final l = jsonDecode(utf8.decode(r.bodyBytes)) as List;
      for (final e in l) {
        out.add(RemoteFile(
          '${e['path']}',
          '${e['hash']}',
          (e['size'] as num? ?? 0).toInt(),
          e['deleted'] == true,
          DateTime.tryParse('${e['updated_at']}') ?? DateTime(2000),
        ));
      }
      if (l.length < page) break;
    }
    return out;
  }

  Future<void> _row(String path, String hash, int size, bool deleted) async {
    final r = await client.post(
      Uri.parse('$url/rest/v1/$table?on_conflict=user_id,path'),
      headers: await _auth({
        'content-type': 'application/json',
        'prefer': 'resolution=merge-duplicates,return=minimal',
      }),
      body: jsonEncode({
        'path': path,
        'hash': hash,
        'size': size,
        'deleted': deleted,
        'device': device,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }),
    );
    if (r.statusCode >= 300) throw SyncAuthError('Serveur : ${_message(r)}');
  }

  @override
  Future<void> upload(String path, Uint8List bytes, String hash) async {
    final r = await client.post(
      Uri.parse('$url/storage/v1/object/$bucket/${_object(path)}'),
      headers: await _auth({'content-type': 'application/octet-stream', 'x-upsert': 'true', 'cache-control': 'no-cache'}),
      body: bytes,
    );
    if (r.statusCode >= 300) throw SyncAuthError('Envoi refusé : ${_message(r)}');
    await _row(path, hash, bytes.length, false);
  }

  @override
  Future<Uint8List> download(String path) async {
    final r = await client.get(
      Uri.parse('$url/storage/v1/object/authenticated/$bucket/${_object(path)}'),
      headers: await _auth(),
    );
    if (r.statusCode != 200) throw SyncAuthError('Réception refusée : ${_message(r)}');
    return r.bodyBytes;
  }

  @override
  Future<void> delete(String path) async {
    await _row(path, '', 0, true);
    final r = await client.delete(Uri.parse('$url/storage/v1/object/$bucket/${_object(path)}'), headers: await _auth());
    if (r.statusCode >= 300 && r.statusCode != 404 && r.statusCode != 400) {
      throw SyncAuthError('Suppression refusée : ${_message(r)}');
    }
  }
}
