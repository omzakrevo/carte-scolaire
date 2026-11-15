import 'package:carte_scolaire/app_state.dart';
import 'package:carte_scolaire/models.dart';
import 'package:carte_scolaire/screens/photo_batch_screen.dart';
import 'package:carte_scolaire/screens/sheet_import_screen.dart';
import 'package:carte_scolaire/services/license.dart';
import 'package:carte_scolaire/sync/sync_controller.dart';
import 'package:carte_scolaire/sync/sync_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(AppState state, Widget child, {SyncController? sync}) {
  final lm = LicenseManager()..debugUnlocked();
  final app = MaterialApp(home: child);
  return LicenseScope(
    manager: lm,
    child: AppScope(state: state, child: sync == null ? app : SyncScope(controller: sync, child: app)),
  );
}

void main() {
  for (final size in [const Size(1200, 900), const Size(400, 860)]) {
    testWidgets('liste collée → tableau → fiches (${size.width.toInt()} px)', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final state = AppState()..loaded = true;
      await tester.pumpWidget(host(state, const SheetImportScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Coller du texte'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Nom et prénoms\tClasse\nOUÉDRAOGO Awa\t6e A\nKABORÉ Jean Paul\t6e B\n');
      await tester.tap(find.text('Lire la liste'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('2 fiche(s) prête(s)'), findsOneWidget);
      await tester.tap(find.textContaining('Ajouter à la liste'));
      await tester.pumpAndSettle();
      expect(state.students.map((e) => e.fullName), ['OUÉDRAOGO Awa', 'KABORÉ Jean Paul']);
      expect(state.students.last.classe, '6e B');
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('écrans photos en lot et multi-appareil (${size.width.toInt()} px)', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final state = AppState()..loaded = true;
      state.students.add(Student(nom: 'SOMÉ', prenom: 'Léa'));
      await tester.pumpWidget(host(state, const PhotoBatchScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Choisir un dossier'), findsOneWidget);
      expect(tester.takeException(), isNull);

      var allowed = false;
      final sync = SyncController(
        licensed: () => allowed,
        beforeSync: () async {},
        afterSync: (_) async {},
        lastEdit: () => DateTime(2000),
      );
      await tester.pumpWidget(host(state, const SyncScreen(), sync: sync));
      await tester.pumpAndSettle();
      expect(find.text('Option payante non activée sur cet appareil'), findsOneWidget);
      allowed = true;
      await tester.pumpWidget(host(state, const Scaffold(body: SyncCard()), sync: sync));
      await tester.pumpWidget(host(state, const SyncScreen(), sync: sync));
      await tester.pumpAndSettle();
      expect(find.text('Se connecter'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
