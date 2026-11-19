import 'package:carte_scolaire/app_state.dart';
import 'package:carte_scolaire/models.dart';
import 'package:carte_scolaire/screens/list_tools_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final w in [400.0, 1200.0]) {
    testWidgets('dialogues « pour tout le monde » ($w px)', (tester) async {
      tester.view.physicalSize = Size(w, 860);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final app = AppState()..loaded = true;
      app.students.addAll([Student(nom: 'A', classe: '6A'), Student(nom: 'B', classe: '6B', contact: '70')]);
      late BuildContext ctx;
      await tester.pumpWidget(AppScope(
          state: app,
          child: MaterialApp(home: Builder(builder: (c) {
            ctx = c;
            return const Scaffold();
          }))));
      showMatriculeDialog(ctx, app, onlyClass: '6A');
      await tester.pumpAndSettle();
      expect(find.text('Numéroter 1 fiche(s)'), findsOneWidget);
      await tester.tap(find.text('Seulement « 6A »'));
      await tester.pumpAndSettle();
      expect(find.text('Numéroter 2 fiche(s)'), findsOneWidget);
      await tester.tap(find.text('Seulement « 6A »'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Numéroter 1 fiche(s)'));
      await tester.tap(find.text('Numéroter 1 fiche(s)'));
      await tester.pumpAndSettle();
      expect(app.students.map((e) => e.matricule), ['${DateTime.now().year}-001', '']);

      showFillDialog(ctx, app);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Direction 70 00 00 00');
      await tester.pumpAndSettle();
      expect(find.text('1 fiche(s) modifiée(s).'), findsOneWidget);
      await tester.tap(find.text('Appliquer'));
      await tester.pumpAndSettle();
      expect(app.students.first.contact, 'Direction 70 00 00 00');
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 1));
    });
  }
}
