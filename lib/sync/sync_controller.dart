import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';

import '../services/storage.dart';
import 'supabase_backend.dart';
import 'sync_engine.dart';

/// Option multi-appareil : le même compte sur l'ordinateur et le téléphone, avec les mêmes
/// projets, fiches, photos, notes et présences. Chaque appareil garde sa propre licence.
class SyncController extends ChangeNotifier {
  /// L'option est-elle comprise dans la licence de cet appareil ?
  final bool Function() licensed;

  /// Avant la synchronisation : tout enregistrer sur le disque.
  final Future<void> Function() beforeSync;

  /// Après : recharger ce qui a été reçu.
  final Future<void> Function(SyncReport report) afterSync;

  /// Dernière modification faite dans l'application (pour ne pas synchroniser en pleine saisie).
  final DateTime Function() lastEdit;

  SyncController({
    required this.licensed,
    required this.beforeSync,
    required this.afterSync,
    required this.lastEdit,
  });

  String url = '';
  String anonKey = '';
  bool auto = true;
  SyncSession? session;
  DateTime? lastSync;
  String? lastError;
  SyncReport? lastReport;

  bool running = false;
  int done = 0, total = 0;
  bool loaded = false;
  Timer? _timer;

  bool get configured => url.isNotEmpty && anonKey.isNotEmpty;
  bool get connected => configured && session != null;
  bool get allowed => licensed();
  String get email => session?.email ?? '';

  static String get deviceName {
    try {
      return '${Platform.localHostname} (${Platform.operatingSystem})';
    } catch (_) {
      return Platform.operatingSystem;
    }
  }

  Future<File> _file(String name) async => File('${(await Storage.baseDir()).path}${Platform.pathSeparator}$name');

  Future<void> load() async {
    try {
      final f = await _file('sync.json');
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString()) as Map;
        url = '${j['url'] ?? ''}';
        anonKey = '${j['key'] ?? ''}';
        auto = j['auto'] != false;
        session = SyncSession.fromJson(j['session']);
        lastSync = DateTime.tryParse('${j['last'] ?? ''}');
      }
    } catch (_) {}
    loaded = true;
    notifyListeners();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 10), (_) => maybeAutoSync());
  }

  Future<void> _save() async {
    try {
      await (await _file('sync.json')).writeAsString(jsonEncode({
        'url': url,
        'key': anonKey,
        'auto': auto,
        'session': session?.toJson(),
        'last': lastSync?.toIso8601String(),
      }));
    } catch (_) {}
  }

  Future<Map<String, LocalFile>> _loadBase() async {
    try {
      final f = await _file('sync_state.json');
      if (await f.exists()) return SyncEngine.decodeBase(jsonDecode(await f.readAsString()));
    } catch (_) {}
    return {};
  }

  Future<void> _saveBase(SyncEngine e) async {
    final f = await _file('sync_state.json');
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(e.encodeBase()));
    await tmp.rename(f.path);
  }

  SupabaseBackend _backend() => SupabaseBackend(url, anonKey, session: session, device: deviceName)
    ..onSession = (s) {
      session = s;
      _save();
    };

  /// Connexion (ou création du compte). Renvoie un message à afficher, ou null si tout va bien.
  Future<String?> connect(String serverUrl, String key, String mail, String password, {bool create = false}) async {
    var u = serverUrl.trim();
    if (u.isNotEmpty && !u.startsWith('http')) u = 'https://$u';
    final changedAccount = session?.email != mail.trim() || url != u;
    url = u;
    anonKey = key.trim();
    final b = _backend();
    try {
      if (create) {
        final ok = await b.signUp(mail, password);
        if (!ok) {
          await _save();
          return 'Compte créé. Confirmez l\'adresse e-mail reçue, puis connectez-vous.';
        }
      } else {
        await b.signIn(mail, password);
      }
      session = b.session;
      if (changedAccount) await (await _file('sync_state.json')).writeAsString('{}');
      lastError = null;
      await _save();
      notifyListeners();
      if (!await b.hasAccess()) {
        return 'Connecté, mais l\'option multi-appareil n\'est pas encore activée pour ce compte '
            'sur le serveur. Demandez son activation.';
      }
      return null;
    } on SocketException {
      return 'Serveur injoignable : vérifiez l\'adresse et la connexion Internet.';
    } catch (e) {
      return '$e';
    }
  }

  Future<void> disconnect() async {
    session = null;
    lastSync = null;
    lastReport = null;
    try {
      await (await _file('sync_state.json')).writeAsString('{}');
    } catch (_) {}
    await _save();
    notifyListeners();
  }

  Future<void> setAuto(bool v) async {
    auto = v;
    await _save();
    notifyListeners();
  }

  /// Synchronisation automatique : au démarrage puis toutes les 10 minutes,
  /// seulement si rien n'a été modifié depuis une minute et demie.
  Future<void> maybeAutoSync() async {
    if (!auto || !connected || !allowed || running) return;
    if (DateTime.now().difference(lastEdit()) < const Duration(seconds: 90)) return;
    await syncNow();
  }

  Future<SyncReport?> syncNow() async {
    if (running || !connected) return null;
    if (!allowed) {
      lastError = 'L\'option multi-appareil n\'est pas comprise dans la licence de cet appareil.';
      notifyListeners();
      return null;
    }
    running = true;
    done = 0;
    total = 0;
    lastError = null;
    notifyListeners();
    SyncEngine? engine;
    try {
      final b = _backend();
      if (!await b.hasAccess()) {
        throw const SyncAuthError('Option multi-appareil non activée pour ce compte sur le serveur.');
      }
      await beforeSync();
      engine = SyncEngine(await Storage.baseDir(), b, await _loadBase());
      var last = DateTime.now();
      final report = await engine.run(progress: (d, t, _) {
        done = d;
        total = t;
        if (DateTime.now().difference(last).inMilliseconds > 250) {
          last = DateTime.now();
          notifyListeners();
        }
      });
      await _saveBase(engine);
      lastReport = report;
      lastSync = DateTime.now();
      if (report.errors.isNotEmpty) {
        lastError = '${report.errors.length} fichier(s) non synchronisé(s) : ${report.errors.first}';
      }
      await _save();
      await afterSync(report);
      return report;
    } on SocketException {
      lastError = 'Pas de connexion au serveur. Les données restent sur l\'appareil ; réessayez plus tard.';
    } catch (e) {
      lastError = '$e';
      if (engine != null) {
        try {
          await _saveBase(engine);
        } catch (_) {}
      }
    } finally {
      running = false;
      notifyListeners();
    }
    return null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

class SyncScope extends InheritedNotifier<SyncController> {
  const SyncScope({super.key, required SyncController controller, required super.child})
      : super(notifier: controller);

  static SyncController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SyncScope>()?.notifier;
}
