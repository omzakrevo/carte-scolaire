import 'package:carte_scolaire/app_state.dart';
import 'package:carte_scolaire/main.dart';
import 'package:carte_scolaire/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final size in [const Size(1400, 900), const Size(400, 860)]) {
    testWidgets('parcours des 4 étapes (${size.width.toInt()} px)', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final state = AppState()..loaded = true;
      state.students.addAll([
        Student.sample(),
        Student(nom: 'Kaboré', prenom: 'Jean', classe: '6e B'),
      ]);
      await tester.pumpWidget(AppScope(state: state, child: const CarteScolaireApp()));
      await tester.pumpAndSettle();
      expect(find.text('Choisir un modèle'), findsOneWidget);

      for (final label in ['Élèves', 'Photos', 'Impression']) {
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      await tester.scrollUntilVisible(find.text('Générer le PDF'), 300,
          scrollable: find.byType(Scrollable).hitTestable().first);
      expect(find.text('Générer le PDF'), findsOneWidget);

      await tester.tap(find.text('Photos').last);
      await tester.pumpAndSettle();
      expect(find.text('Élève 1 sur 2'), findsOneWidget);
      await tester.tap(find.byTooltip('Suivant (→)'));
      await tester.pumpAndSettle();
      expect(find.text('Élève 2 sur 2'), findsOneWidget);
    });
  }
}
