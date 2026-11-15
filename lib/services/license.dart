import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import '../card_kinds.dart';
import 'storage.dart';

/// Clé publique de l'administrateur. Les codes de licence sont signés avec la
/// clé privée correspondante, que seul l'administrateur possède : impossible de
/// fabriquer un code valide sans elle. Aucune base de données externe.
const _adminPublicKey = '9z6fiwSh9JJ+XGPnVLNmzzVsVMoDjZrj444y0RCO23g=';

/// Registre public des licences (révocations), mis à jour depuis la page administrateur.
const registryUrl = 'https://raw.githubusercontent.com/omzakrevo/carte-scolaire/main/licenses/registry.json';

/// Serveur de l'option multi-appareil (Supabase auto-hébergé de l'éditeur). La clé publique
/// (anon key) est publiée dans le registre par la page administrateur : les clients n'ont
/// rien à saisir.
const defaultSyncUrl = 'https://vps-ef39f3a3.vps.ovh.ca';
const defaultSyncKey = '';

/// Formules de licence.
const licensePlans = <String, String>{
  'M1': '1 mois',
  'M3': '3 mois',
  'M6': '6 mois',
  'Y1': '1 an',
  'LIFE': 'Définitive',
  'RESET': 'Réinitialisation du mot de passe',
};

/// Modules d'une licence émise avant leur apparition : cartes scolaires et pointage.
const legacyModules = {'ecole', 'presence'};

/// Contenu d'un code signé :
/// CS1|id|appareil|formule|expiration(AAAAMMJJ ou 0)|émission(AAAAMMJJ)[|modules séparés par des virgules]
class LicenseInfo {
  final String id;
  final String device;
  final String plan;
  final DateTime? expires;
  final DateTime issued;

  /// Fonctions activées par l'administrateur (voir allModules dans card_kinds.dart).
  final Set<String> modules;

  const LicenseInfo(this.id, this.device, this.plan, this.expires, this.issued, [this.modules = legacyModules]);

  bool get lifetime => expires == null;
  String get planLabel => licensePlans[plan] ?? plan;

  static DateTime? _d(String s) => s == '0' || s.length != 8
      ? null
      : DateTime(int.parse(s.substring(0, 4)), int.parse(s.substring(4, 6)), int.parse(s.substring(6, 8)), 23, 59, 59);

  static LicenseInfo? parse(String payload) {
    final p = payload.split('|');
    if ((p.length != 6 && p.length != 7) || p[0] != 'CS1') return null;
    final issued = _d(p[5]);
    if (issued == null) return null;
    final modules =
        p.length == 7 ? p[6].split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toSet() : legacyModules;
    return LicenseInfo(p[1], p[2], p[3], _d(p[4]), issued, modules);
  }
}

enum LicenseStatus { trial, active, expired, revoked, clockError }

/// Mot de passe de l'application, licence et appareil, stockés sur le téléphone.
class LicenseManager extends ChangeNotifier {
  bool loaded = false;
  bool unlocked = false;
  String deviceId = '';
  String? _salt;
  String? _hash;
  String? code;
  LicenseInfo? license;
  DateTime? _lastSeen;
  Set<String> revoked = {};
  DateTime? registryChecked;
  bool welcomed = false;

  /// Serveur multi-appareil (mis à jour depuis le registre).
  String syncUrl = defaultSyncUrl;
  String syncKey = defaultSyncKey;

  bool get hasPassword => _hash != null;

  /// Pour les tests : application déverrouillée, sans licence.
  @visibleForTesting
  void debugUnlocked() {
    _hash = 'test';
    _salt = 'dGVzdA==';
    deviceId = 'TESTS-00000';
    loaded = unlocked = welcomed = true;
  }

  LicenseStatus get status {
    final l = license;
    if (l == null) return LicenseStatus.trial;
    if (revoked.contains(l.id)) return LicenseStatus.revoked;
    final now = DateTime.now();
    if (_lastSeen != null && now.isBefore(_lastSeen!.subtract(const Duration(days: 2)))) {
      return LicenseStatus.clockError;
    }
    if (l.expires != null && now.isAfter(l.expires!)) return LicenseStatus.expired;
    return LicenseStatus.active;
  }

  bool get isLicensed => status == LicenseStatus.active;

  /// Fonction disponible ? En essai, tout est ouvert (cartes en filigrane) pour découvrir ;
  /// avec une licence, seuls les modules activés par l'administrateur.
  bool hasModule(String m) => !isLicensed || license!.modules.contains(m);

  String get statusLabel => switch (status) {
        LicenseStatus.trial => 'Version d\'essai',
        LicenseStatus.active => license!.lifetime
            ? 'Licence définitive'
            : 'Licence ${license!.planLabel} · jusqu\'au ${_fmt(license!.expires!)}',
        LicenseStatus.expired => 'Licence expirée le ${_fmt(license!.expires!)}',
        LicenseStatus.revoked => 'Licence révoquée',
        LicenseStatus.clockError => 'Date du téléphone incorrecte',
      };

  int? get daysLeft {
    final e = license?.expires;
    if (e == null || !isLicensed) return null;
    return e.difference(DateTime.now()).inDays;
  }

  static String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<File> _file() async => File('${(await Storage.baseDir()).path}${Platform.pathSeparator}security.json');

  Future<void> load() async {
    try {
      final f = await _file();
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        deviceId = j['device'] ?? '';
        _salt = j['salt'];
        _hash = j['hash'];
        code = j['code'];
        _lastSeen = DateTime.tryParse(j['lastSeen'] ?? '');
        revoked = {...(j['revoked'] as List? ?? []).map((e) => e.toString())};
        registryChecked = DateTime.tryParse(j['registryChecked'] ?? '');
        welcomed = j['welcomed'] ?? false;
        final srv = j['syncServer'];
        if (srv is Map) {
          syncUrl = '${srv['url'] ?? defaultSyncUrl}';
          syncKey = '${srv['key'] ?? defaultSyncKey}';
        }
      }
      if (deviceId.isEmpty) deviceId = _newDeviceId();
      if (code != null) license = await _verify(code!);
      final now = DateTime.now();
      if (_lastSeen == null || now.isAfter(_lastSeen!)) _lastSeen = now;
      await _save();
    } catch (_) {
      if (deviceId.isEmpty) deviceId = _newDeviceId();
    }
    loaded = true;
    notifyListeners();
    unawaited(refreshRegistry());
    // Mises à jour de licence publiées par l'administrateur : vérifiées régulièrement.
    _registryTimer?.cancel();
    _registryTimer = Timer.periodic(const Duration(hours: 3), (_) => refreshRegistry());
  }

  Timer? _registryTimer;

  Future<void> _save() async {
    final f = await _file();
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode({
      'device': deviceId,
      'salt': _salt,
      'hash': _hash,
      'code': code,
      'lastSeen': _lastSeen?.toIso8601String(),
      'revoked': revoked.toList(),
      'registryChecked': registryChecked?.toIso8601String(),
      'welcomed': welcomed,
      'syncServer': {'url': syncUrl, 'key': syncKey},
    }));
    await tmp.rename(f.path);
  }

  static String _newDeviceId() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    final s = List.generate(10, (_) => chars[r.nextInt(chars.length)]).join();
    return '${s.substring(0, 5)}-${s.substring(5)}';
  }

  // ---------------- Mot de passe ----------------

  static final _kdf = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 30000, bits: 256);

  Future<String> _derive(String password, String salt) async {
    final key = await _kdf.deriveKeyFromPassword(password: password, nonce: base64Decode(salt));
    return base64Encode(await key.extractBytes());
  }

  Future<void> setPassword(String password) async {
    final r = Random.secure();
    _salt = base64Encode(List.generate(16, (_) => r.nextInt(256)));
    _hash = await _derive(password, _salt!);
    unlocked = true;
    await _save();
    notifyListeners();
  }

  Future<bool> unlock(String password) async {
    if (_hash == null || _salt == null) return false;
    final ok = await _derive(password, _salt!) == _hash;
    if (ok) {
      unlocked = true;
      notifyListeners();
    }
    return ok;
  }

  void lock() {
    unlocked = false;
    notifyListeners();
  }

  Future<void> markWelcomed() async {
    welcomed = true;
    await _save();
    notifyListeners();
  }

  // ---------------- Codes signés ----------------

  static String _clean(String code) => code.replaceAll(RegExp(r'\s'), '');

  Future<LicenseInfo?> _verify(String raw) => verifyCode(raw, deviceId);

  /// Pour les tests : clé publique de remplacement (codes signés par une clé de test).
  @visibleForTesting
  static String? debugPublicKey;

  /// Vérifie la signature d'un code et qu'il a été émis pour [device].
  static Future<LicenseInfo?> verifyCode(String raw, String device) async {
    final code = _clean(raw);
    final parts = code.split('.');
    if (parts.length != 2) return null;
    try {
      final payload = utf8.decode(base64Url.decode(base64Url.normalize(parts[0])));
      final sig = base64Url.decode(base64Url.normalize(parts[1]));
      final ok = await Ed25519().verify(
        utf8.encode(payload),
        signature: Signature(sig, publicKey: SimplePublicKey(base64Decode(debugPublicKey ?? _adminPublicKey), type: KeyPairType.ed25519)),
      );
      if (!ok) return null;
      final info = LicenseInfo.parse(payload);
      if (info == null || info.device != device) return null;
      return info;
    } catch (_) {
      return null;
    }
  }

  /// Active un code de licence. Renvoie un message d'erreur, ou `null` si c'est bon.
  Future<String?> activate(String raw) async {
    final info = await _verify(raw);
    if (info == null) {
      return 'Code invalide pour cet appareil. Vérifiez qu\'il a été créé pour l\'identifiant $deviceId '
          'et collez-le en entier.';
    }
    if (info.plan == 'RESET') return 'Ce code sert à réinitialiser le mot de passe, pas à activer une licence.';
    if (revoked.contains(info.id)) return 'Cette licence a été révoquée.';
    if (info.expires != null && DateTime.now().isAfter(info.expires!)) {
      return 'Cette licence a expiré le ${_fmt(info.expires!)}.';
    }
    code = _clean(raw);
    license = info;
    await _save();
    notifyListeners();
    return null;
  }

  /// Nouveau mot de passe grâce à un code de réinitialisation fourni par l'administrateur.
  Future<String?> resetPassword(String raw, String newPassword) async {
    final info = await _verify(raw);
    if (info == null || info.plan != 'RESET') {
      return 'Code de réinitialisation invalide pour l\'appareil $deviceId.';
    }
    if (DateTime.now().difference(info.issued).inDays > 7) return 'Ce code de réinitialisation a expiré.';
    await setPassword(newPassword);
    return null;
  }

  /// Licence améliorée à distance (prolongée ou avec d'autres modules) : l'administrateur
  /// publie le nouveau code dans le registre, l'appareil l'applique tout seul.
  /// Le message de la dernière mise à jour est gardé pour l'afficher une fois.
  String? upgradeNotice;

  Future<bool> applyUpgrades(Object? upgrades) async {
    if (upgrades is! Map) return false;
    final raw = upgrades[deviceId];
    final codes = raw is List ? raw : (raw == null ? const [] : [raw]);
    LicenseInfo? best;
    String? bestCode;
    for (final c in codes) {
      final info = await _verify('$c');
      if (info == null || info.plan == 'RESET' || revoked.contains(info.id)) continue;
      if (best == null || info.issued.isAfter(best.issued) || (info.issued == best.issued && '$c' != bestCode)) {
        best = info;
        bestCode = _clean('$c');
      }
    }
    final cur = license;
    if (best == null || bestCode == code) return false;
    if (cur != null && best.issued.isBefore(cur.issued)) return false;
    if (best.expires != null && DateTime.now().isAfter(best.expires!)) return false;
    final added = cur == null ? best.modules : best.modules.difference(cur.modules);
    code = bestCode;
    license = best;
    upgradeNotice = [
      'Licence mise à jour : ${best.lifetime ? 'définitive' : 'valable jusqu\'au ${_fmt(best.expires!)}'}',
      if (added.isNotEmpty) 'nouveaux modules : ${added.map((m) => allModules[m] ?? m).join(', ')}',
    ].join(' · ');
    await _save();
    notifyListeners();
    return true;
  }

  /// Récupère la liste des licences révoquées sur GitHub (si Internet est disponible).
  /// Renvoie vrai si la licence a été mise à jour, null si le registre est injoignable.
  Future<bool?> refreshRegistry() async {
    try {
      final r = await http
          .get(Uri.parse('$registryUrl?t=${DateTime.now().millisecondsSinceEpoch ~/ 60000}'))
          .timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return null;
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      revoked = {...(j['revoked'] as List? ?? []).map((e) => e.toString())};
      final srv = j['sync'];
      if (srv is Map && '${srv['key'] ?? ''}'.isNotEmpty) {
        syncUrl = '${srv['url'] ?? defaultSyncUrl}';
        syncKey = '${srv['key']}';
      }
      final upgraded = await applyUpgrades(j['upgrades']);
      registryChecked = DateTime.now();
      final now = DateTime.now();
      if (_lastSeen == null || now.isAfter(_lastSeen!)) _lastSeen = now;
      await _save();
      notifyListeners();
      return upgraded;
    } catch (_) {
      // Hors ligne : on garde la dernière liste connue.
      return null;
    }
  }
}

class LicenseScope extends InheritedNotifier<LicenseManager> {
  const LicenseScope({super.key, required LicenseManager manager, required super.child}) : super(notifier: manager);

  static LicenseManager of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LicenseScope>()!.notifier!;

  /// Mode essai ? (faux si aucune licence n'est fournie, par exemple dans les tests).
  static bool trialOf(BuildContext context) =>
      !(context.dependOnInheritedWidgetOfExactType<LicenseScope>()?.notifier?.isLicensed ?? true);

  /// Filigrane sur les cartes : version d'essai, ou type de carte non activé dans la licence.
  static bool watermarkOf(BuildContext context, String kind) => trialOf(context) || !moduleOf(context, kind);

  /// Module activé ? (vrai sans gestionnaire de licence, par exemple dans les tests).
  static bool moduleOf(BuildContext context, String m) =>
      context.dependOnInheritedWidgetOfExactType<LicenseScope>()?.notifier?.hasModule(m) ?? true;

  static LicenseManager read(BuildContext context) => context.getInheritedWidgetOfExactType<LicenseScope>()!.notifier!;
}
