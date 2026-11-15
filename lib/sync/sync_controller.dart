import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import '../services/storage.dart';
import 'pairing.dart';
import 'supabase_backend.dart';
import 'sync_engine.dart';

/// Option multi-appareil : le même compte sur l'ordinateur et le téléphone, avec les mêmes
/// projets, fiches, photos, notes et présences. Chaque appareil garde sa propre licence.
///
/// Personne n'a de serveur ni de mot de passe à saisir :
/// - le premier appareil crée le compte tout seul (identifiants générés et gardés sur l'appareil) ;
/// - un autre appareil rejoint le compte avec le code (ou le QR code) affiché par le premier ;
/// - l'accès est ouvert par la licence de l'appareil (module « Multi-appareil »).
class SyncController extends ChangeNotifier {
  /// L'option est-elle comprise dans la licence de cet appareil ?
  final bool Function() licensed;

  /// Code de licence de l'appareil (envoyé au serveur pour ouvrir l'accès).
  final String? Function() licenseCode;

  /// Adresse et clé publique du serveur (fournies par le registre des licences).
  final (String, String) Function() server;

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
    this.server = _noServer,
    this.licenseCode = _noCode,
    this.httpClient,
  });

  /// Pour les tests : client HTTP simulé.
  final http.Client? httpClient;

  static (String, String) _noServer() => ('', '');
  static String? _noCode() => null;

  bool auto = true;
  String email = '';
  String password = '';
  SyncSession? session;
  DateTime? lastSync;
  String? lastError;
  SyncReport? lastReport;

  bool running = false;
  bool busy = false;
  int done = 0, total = 0;
  bool loaded = false;
  Timer? _timer;

  String get url => server().$1;
  String get anonKey => server().$2;
  bool get serverReady => url.isNotEmpty && anonKey.isNotEmpty;
  bool get connected => session != null && email.isNotEmpty;
  bool get allowed => licensed();

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
        auto = j['auto'] != false;
        email = '${j['email'] ?? ''}';
        password = '${j['password'] ?? ''}';
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
        'auto': auto,
        'email': email,
        'password': password,
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

  Future<void> _clearBase() async {
    try {
      await (await _file('sync_state.json')).writeAsString('{}');
    } catch (_) {}
  }

  SupabaseBackend _backend() => SupabaseBackend(url, anonKey, session: session, device: deviceName, client: httpClient)
    ..onSession = (s) {
      session = s;
      _save();
    };

  String? _checkReady() {
    if (!allowed) return 'L\'option multi-appareil n\'est pas comprise dans la licence de cet appareil.';
    if (!serverReady) {
      return 'Serveur de synchronisation pas encore configuré. Connectez l\'appareil à Internet '
          'puis réessayez (Licence > Rechercher une mise à jour).';
    }
    return null;
  }

  String _explain(Object e) {
    if (e is SocketException || e is TimeoutException) {
      return 'Serveur injoignable : vérifiez la connexion Internet.';
    }
    final m = '$e';
    if (m.contains('confirm')) {
      return 'Le serveur demande de confirmer les e-mails : l\'éditeur doit activer la confirmation automatique.';
    }
    return m;
  }

  /// Ouvre l'accès sur le serveur avec la licence de cet appareil.
  Future<bool> _register(SupabaseBackend b) async {
    final code = licenseCode();
    if (code != null) {
      try {
        await b.rpc('cs_register_license', {'code': code});
      } catch (_) {}
    }
    return b.hasAccess();
  }

  Future<String?> _finishLogin(SupabaseBackend b, String mail, String pass) async {
    session = b.session;
    final changed = email != mail;
    email = mail;
    password = pass;
    if (changed) await _clearBase();
    lastError = null;
    await _save();
    notifyListeners();
    if (!await _register(b)) {
      return 'Compte prêt, mais l\'accès n\'est pas encore ouvert sur le serveur : '
          'la licence de cet appareil doit contenir « Multi-appareil ».';
    }
    return null;
  }

  /// Premier appareil : crée le compte automatiquement.
  Future<String?> activate() async {
    final ready = _checkReady();
    if (ready != null) return ready;
    busy = true;
    notifyListeners();
    try {
      final b = _backend();
      final (mail, pass) = newAccountCredentials();
      if (!await b.signUp(mail, pass)) {
        return 'Le serveur demande de confirmer les e-mails : l\'éditeur doit activer la confirmation automatique.';
      }
      return await _finishLogin(b, mail, pass);
    } catch (e) {
      return _explain(e);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Autre appareil : rejoint le compte avec le code affiché sur le premier.
  Future<String?> join(String rawCode) async {
    final ready = _checkReady();
    if (ready != null) return ready;
    final code = normalizePairingCode(rawCode);
    if (code == null) return 'Code incomplet : 10 lettres et chiffres, comme ABCD-EFG-HJK.';
    busy = true;
    notifyListeners();
    try {
      final b = SupabaseBackend(url, anonKey, device: deviceName, client: httpClient);
      final sealed = await b.rpc('cs_pair_take', {'pair_id': await pairingId(code)}, anon: true);
      if (sealed is! String || sealed.isEmpty) {
        return 'Code inconnu ou expiré (15 minutes). Affichez un nouveau code sur l\'autre appareil.';
      }
      final creds = await openCredentials(code, sealed);
      if (creds == null) return 'Code incorrect.';
      final (mail, pass) = creds;
      final backend = _backend();
      await backend.signIn(mail, pass);
      return await _finishLogin(backend, mail, pass);
    } catch (e) {
      return _explain(e);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Code (et QR code) pour ajouter un autre appareil, valable 15 minutes.
  Future<(String?, String?)> newPairing() async {
    if (!connected) return (null, 'Cet appareil n\'est pas connecté.');
    try {
      final code = newPairingCode();
      final b = _backend();
      await b.rpc('cs_pair_put', {
        'pair_id': await pairingId(code),
        'data': await sealCredentials(code, email, password),
      });
      return (code, null);
    } catch (e) {
      return (null, _explain(e));
    }
  }

  Future<void> disconnect() async {
    session = null;
    email = '';
    password = '';
    lastSync = null;
    lastReport = null;
    await _clearBase();
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
    if (!auto || !connected || !allowed || running || !serverReady) return;
    if (DateTime.now().difference(lastEdit()) < const Duration(seconds: 90)) return;
    await syncNow();
  }

  Future<SyncReport?> syncNow() async {
    if (running || !connected) return null;
    final ready = _checkReady();
    if (ready != null) {
      lastError = ready;
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
      var b = _backend();
      bool access;
      try {
        access = await b.hasAccess();
      } on SyncAuthError {
        // Session perdue : on se reconnecte avec les identifiants gardés sur l'appareil.
        if (password.isEmpty) rethrow;
        b = _backend();
        await b.signIn(email, password);
        session = b.session;
        access = await b.hasAccess();
      }
      if (!access && !await _register(b)) {
        throw const SyncAuthError('Accès fermé sur le serveur : la licence de cet appareil doit contenir '
            '« Multi-appareil » et être en cours de validité.');
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
    } catch (e) {
      lastError = _explain(e);
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
