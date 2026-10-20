import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import 'storage.dart';

/// Clé publique de l'administrateur. Les codes de licence sont signés avec la
/// clé privée correspondante, que seul l'administrateur possède : impossible de
/// fabriquer un code valide sans elle. Aucune base de données externe.
const _adminPublicKey = '9z6fiwSh9JJ+XGPnVLNmzzVsVMoDjZrj444y0RCO23g=';

/// Registre public des licences (révocations), mis à jour depuis la page administrateur.
const registryUrl = 'https://raw.githubusercontent.com/omzakrevo/carte-scolaire/main/licenses/registry.json';

/// Formules de licence.
const licensePlans = <String, String>{
  'M1': '1 mois',
  'M3': '3 mois',
  'M6': '6 mois',
  'Y1': '1 an',
  'LIFE': 'Définitive',
  'RESET': 'Réinitialisation du mot de passe',
};

/// Contenu d'un code signé : CS1|id|appareil|formule|expiration(AAAAMMJJ ou 0)|émission(AAAAMMJJ)
class LicenseInfo {
  final String id;
  final String device;
  final String plan;
  final DateTime? expires;
  final DateTime issued;

  const LicenseInfo(this.id, this.device, this.plan, this.expires, this.issued);

  bool get lifetime => expires == null;
  String get planLabel => licensePlans[plan] ?? plan;

  static DateTime? _d(String s) => s == '0' || s.length != 8
      ? null
      : DateTime(int.parse(s.substring(0, 4)), int.parse(s.substring(4, 6)), int.parse(s.substring(6, 8)), 23, 59, 59);

  static LicenseInfo? parse(String payload) {
    final p = payload.split('|');
    if (p.length != 6 || p[0] != 'CS1') return null;
    final issued = _d(p[5]);
    if (issued == null) return null;
    return LicenseInfo(p[1], p[2], p[3], _d(p[4]), issued);
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
  }

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
        signature: Signature(sig, publicKey: SimplePublicKey(base64Decode(_adminPublicKey), type: KeyPairType.ed25519)),
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

  /// Récupère la liste des licences révoquées sur GitHub (si Internet est disponible).
  Future<void> refreshRegistry() async {
    try {
      final r = await http.get(Uri.parse(registryUrl)).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return;
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      revoked = {...(j['revoked'] as List? ?? []).map((e) => e.toString())};
      registryChecked = DateTime.now();
      final now = DateTime.now();
      if (_lastSeen == null || now.isAfter(_lastSeen!)) _lastSeen = now;
      await _save();
      notifyListeners();
    } catch (_) {
      // Hors ligne : on garde la dernière liste connue.
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

  static LicenseManager read(BuildContext context) => context.getInheritedWidgetOfExactType<LicenseScope>()!.notifier!;
}
