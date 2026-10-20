import 'dart:io';

import 'package:carte_scolaire/services/license.dart';
import 'package:flutter_test/flutter_test.dart';

/// Vérifie qu'un code émis par la page administrateur (JavaScript) est accepté
/// par l'application. Fichier fourni par JS_CODES=chemin (ignoré sinon).
void main() {
  final path = Platform.environment['JS_CODES'];
  test('codes de la page administrateur acceptés', () async {
    final lines = File(path!).readAsLinesSync();
    final lic = await LicenseManager.verifyCode(lines[0], 'ABCDE-FGHJK');
    expect(lic?.plan, 'Y1');
    expect(lic!.expires!.isAfter(DateTime.now().add(const Duration(days: 360))), isTrue);
    final reset = await LicenseManager.verifyCode(lines[1], 'ABCDE-FGHJK');
    expect(reset?.plan, 'RESET');
  }, skip: path == null ? 'JS_CODES non défini' : null);
}
