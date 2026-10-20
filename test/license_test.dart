import 'dart:convert';

import 'package:carte_scolaire/services/license.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const good =
      'Q1MxfEwtVEVTVDAxfEFCQ0RFLUZHSEpLfFkxfDIwOTkxMjMxfDIwMjYxMDIw.ZrKdmXmeI7H2x8qDNoqECq3hcaZ6E4p_7Mydk7YU73gVoSWHzZyL5avyDs2_w2VDXU3CT1N4nEwNKzsN55Q3BQ';
  const expired =
      'Q1MxfEwtVEVTVDAyfEFCQ0RFLUZHSEpLfE0xfDIwMjAwMTAxfDIwMTkxMjAx.acOFodoigFRHzXCGprzkN0ejLLLC4gBi-7bslZ53Lshob62PqOl-ynmoUZjtjw0BygQbT1iVAMO9En8-FQn0BA';

  test('code signé valide pour le bon appareil', () async {
    final i = await LicenseManager.verifyCode(good, 'ABCDE-FGHJK');
    expect(i, isNotNull);
    expect(i!.plan, 'Y1');
    expect(i.id, 'L-TEST01');
    expect(i.expires!.year, 2099);
  });

  test('refusé sur un autre appareil', () async {
    expect(await LicenseManager.verifyCode(good, 'ZZZZZ-ZZZZZ'), isNull);
  });

  test('refusé si le code est modifié', () async {
    final parts = good.split('.');
    final payload = utf8.decode(base64Url.decode(base64Url.normalize(parts[0]))).replaceFirst('|Y1|', '|LIFE|');
    final forged = '${base64Url.encode(utf8.encode(payload)).replaceAll('=', '')}.${parts[1]}';
    expect(await LicenseManager.verifyCode(forged, 'ABCDE-FGHJK'), isNull);
    expect(await LicenseManager.verifyCode('n importe quoi', 'ABCDE-FGHJK'), isNull);
  });

  test('accepte les espaces et retours à la ligne collés', () async {
    final spaced = '${good.substring(0, 20)} \n ${good.substring(20)}';
    expect(await LicenseManager.verifyCode(spaced, 'ABCDE-FGHJK'), isNotNull);
  });

  test('date d\'expiration lue', () async {
    final i = await LicenseManager.verifyCode(expired, 'ABCDE-FGHJK');
    expect(i!.expires!.isBefore(DateTime.now()), isTrue);
  });
}
