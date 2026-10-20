import 'package:carte_scolaire/app_state.dart';
import 'package:carte_scolaire/main.dart';
import 'package:carte_scolaire/models.dart';
import 'package:carte_scolaire/screens/layout_editor_screen.dart';
import 'package:carte_scolaire/services/license.dart';
import 'package:carte_scolaire/designs/card_designs.dart';
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
      final lm = LicenseManager()..debugUnlocked();
      await tester
          .pumpWidget(LicenseScope(manager: lm, child: AppScope(state: state, child: const CarteScolaireApp())));
      await tester.pumpAndSettle();
      expect(find.text('Choisir un modèle'), findsOneWidget);

      expect(find.text('Version d\'essai'), findsWidgets);
      for (final label in ['Projets', 'Élèves', 'Photos', 'Impression']) {
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

  testWidgets('éditeur de disposition : glisser déplace l\'élément', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = AppState()..loaded = true;
    state.students.add(Student.sample());
    await tester.pumpWidget(AppScope(state: state, child: const MaterialApp(home: LayoutEditorScreen())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Logo'));
    await tester.pump();
    await tester.drag(find.byType(CardView).first, const Offset(60, 30));
    await tester.pumpAndSettle();
    // L'élément touché est sélectionné et suit le doigt.
    final moved = state.template.layers.entries.where((e) => e.value.dx > 1 && e.value.dy > 0.5).toList();
    expect(moved, hasLength(1));
    final id = moved.first.key;
    await tester.tap(find.text(cardLayers[id]!).first);
    await tester.pump();
    await tester.tap(find.text('Réinitialiser cet élément'));
    await tester.pump();
    expect(state.template.layers[id], isNull);
    await tester.pump(const Duration(seconds: 2)); // sauvegarde différée
    expect(tester.takeException(), isNull);
  });
}
