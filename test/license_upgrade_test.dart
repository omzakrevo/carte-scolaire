import 'dart:convert';
import 'dart:io';

import 'package:carte_scolaire/services/license.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late SimpleKeyPair keys;
  final ed = Ed25519();

  TestWidgetsFlutterBinding.ensureInitialized();
  final tmp = Directory.systemTemp.createTempSync('lic');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'), (_) async => tmp.path);

  setUpAll(() async {
    keys = await ed.newKeyPair();
    final pub = await keys.extractPublicKey();
    LicenseManager.debugPublicKey = base64Encode(pub.bytes);
  });
  tearDownAll(() => LicenseManager.debugPublicKey = null);

  Future<String> code(String id, String device, String plan, String expires, String issued, String modules) async {
    final payload = ['CS1', id, device, plan, expires, issued, modules].join('|');
    final sig = await ed.sign(utf8.encode(payload), keyPair: keys);
    return '${base64Url.encode(utf8.encode(payload))}.${base64Url.encode(sig.bytes)}';
  }

  test('licence améliorée à distance : prolongée et nouveaux modules', () async {
    final lm = LicenseManager()..debugUnlocked();
    expect(await lm.activate(await code('L-1', 'TESTS-00000', 'M1', '20991201', '20261101', 'ecole')), isNull);
    expect(lm.hasModule('sync'), isFalse);

    final up = await code('L-2', 'TESTS-00000', 'Y1', '21001201', '20261115', 'ecole,presence,sync');
    final other = await code('L-3', 'AUTRE-11111', 'LIFE', '0', '20261115', 'ecole,sync');
    // Code d'un autre appareil ou falsifié : ignoré.
    expect(await lm.applyUpgrades({'TESTS-00000': '${other.split('.').first}.${up.split('.').last}'}), isFalse);
    expect(await lm.applyUpgrades({'AUTRE-11111': other}), isFalse);

    expect(await lm.applyUpgrades({'TESTS-00000': up}), isTrue);
    expect(lm.license!.id, 'L-2');
    expect(lm.hasModule('sync'), isTrue);
    expect(lm.hasModule('presence'), isTrue);
    expect(lm.license!.expires, DateTime(2100, 12, 1, 23, 59, 59));
    expect(lm.upgradeNotice, contains('Multi-appareil'));

    // Déjà appliquée : rien de plus. Un code plus ancien ne revient pas en arrière.
    expect(await lm.applyUpgrades({'TESTS-00000': up}), isFalse);
    final older = await code('L-0', 'TESTS-00000', 'M1', '20991201', '20261001', 'ecole');
    expect(await lm.applyUpgrades({'TESTS-00000': [older]}), isFalse);
    expect(lm.license!.id, 'L-2');

    // Mise à jour révoquée : ignorée.
    lm.revoked = {'L-4'};
    final revoked = await code('L-4', 'TESTS-00000', 'LIFE', '0', '20261116', 'ecole');
    expect(await lm.applyUpgrades({'TESTS-00000': revoked}), isFalse);
  });
}
