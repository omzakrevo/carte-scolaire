import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

/// Ajout d'un appareil au compte par un code court (ou son QR code).
///
/// Le premier appareil chiffre les identifiants du compte avec une clé tirée du code,
/// puis les dépose sur le serveur sous l'empreinte du code. Le serveur ne voit ni le code
/// ni les identifiants ; le second appareil les récupère une seule fois, dans les 15 minutes.

const _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

/// Code de 10 caractères (≈ 50 bits), affiché « ABCD-EFG-HJK ».
String newPairingCode([Random? r]) {
  final rnd = r ?? Random.secure();
  final s = List.generate(10, (_) => _alphabet[rnd.nextInt(_alphabet.length)]).join();
  return '${s.substring(0, 4)}-${s.substring(4, 7)}-${s.substring(7)}';
}

/// Code saisi à la main ou lu dans un QR code (« CSPAIR:ABCD-EFG-HJK »).
String? normalizePairingCode(String raw) {
  var t = raw.trim().toUpperCase();
  if (t.startsWith('CSPAIR:')) t = t.substring(7);
  t = t.replaceAll(RegExp(r'[^A-Z0-9]'), '');
  if (t.length != 10 || t.split('').any((c) => !_alphabet.contains(c))) return null;
  return '${t.substring(0, 4)}-${t.substring(4, 7)}-${t.substring(7)}';
}

String pairingQr(String code) => 'CSPAIR:$code';

Future<List<int>> _sha(String s) async => (await Sha256().hash(utf8.encode(s))).bytes;

/// Identifiant sous lequel le paquet est déposé (empreinte du code, 64 caractères).
Future<String> pairingId(String code) async =>
    (await _sha('carte-scolaire/id/$code')).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Future<String> sealCredentials(String code, String email, String password) async {
  final key = SecretKey(await _sha('carte-scolaire/cle/$code'));
  final box = await AesGcm.with256bits().encrypt(utf8.encode(jsonEncode({'e': email, 'p': password})), secretKey: key);
  return base64Encode(box.concatenation());
}

Future<(String, String)?> openCredentials(String code, String sealed) async {
  try {
    final key = SecretKey(await _sha('carte-scolaire/cle/$code'));
    final algo = AesGcm.with256bits();
    final box = SecretBox.fromConcatenation(base64Decode(sealed),
        nonceLength: algo.nonceLength, macLength: algo.macAlgorithm.macLength);
    final j = jsonDecode(utf8.decode(await algo.decrypt(box, secretKey: key))) as Map;
    return ('${j['e']}', '${j['p']}');
  } catch (_) {
    return null;
  }
}

/// Identifiants du compte, créés par l'application (personne n'a rien à saisir).
(String, String) newAccountCredentials([Random? r]) {
  final rnd = r ?? Random.secure();
  const low = 'abcdefghijkmnpqrstuvwxyz23456789';
  final id = List.generate(12, (_) => low[rnd.nextInt(low.length)]).join();
  const pw = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789';
  final pass = List.generate(32, (_) => pw[rnd.nextInt(pw.length)]).join();
  return ('cs-$id@carte-scolaire.app', pass);
}
