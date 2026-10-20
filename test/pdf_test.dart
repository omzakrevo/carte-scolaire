import 'dart:io';

import 'package:carte_scolaire/models.dart';
import 'package:carte_scolaire/services/pdf_export.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('génère une planche A4 et des cartes individuelles', (tester) async {
    final students = List.generate(12, (i) => Student(nom: 'Élève$i', prenom: 'Test', classe: 'CM2', matricule: 'M$i'));
    for (final a4 in [true, false]) {
      final bytes = await tester.runAsync(() => buildCardsPdf(
            students: students,
            template: CardTemplate(),
            school: SchoolInfo(),
            layout: PrintLayout(a4Sheet: a4),
          ));
      expect(bytes, isNotNull);
      final text = String.fromCharCodes(bytes!.take(5));
      expect(text, '%PDF-');
      final pages = RegExp(r'/Type\s*/Page[^s]').allMatches(String.fromCharCodes(bytes)).length;
      expect(pages, a4 ? 2 : 12);
      final dir = Platform.environment['CARD_PREVIEW_DIR'];
      if (dir != null) File('$dir/${a4 ? 'planche' : 'individuel'}.pdf').writeAsBytesSync(bytes);
    }
  });
}
