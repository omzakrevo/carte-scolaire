import 'package:carte_scolaire/app_state.dart';
import 'package:carte_scolaire/school/establishment_screen.dart';
import 'package:carte_scolaire/school/school_controller.dart';
import 'package:carte_scolaire/services/license.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('établissement : nom, classe, professeur, attribution, emploi du temps', (tester) async {
    tester.view.physicalSize = const Size(1300, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final app = AppState()..loaded = true;
    final ctrl = SchoolController(app)..loaded = true;
    addTearDown(ctrl.dispose);
    await tester.pumpWidget(LicenseScope(
        manager: LicenseManager()..debugUnlocked(),
        child: AppScope(
            state: app,
            child: SchoolScope(
                controller: ctrl, child: const MaterialApp(home: Scaffold(body: EstablishmentScreen()))))));
    await tester.pumpAndSettle();

    // Nom de l'établissement modifiable directement.
    await tester.enterText(find.widgetWithText(TextField, 'Nom de l\'établissement'), 'Lycée Municipal de Banfora');
    await tester.pump();
    expect(app.school.name, 'Lycée Municipal de Banfora');

    // Nouvelle classe, sans aucun élève, avec le programme du post-primaire deviné d'après son nom.
    await tester.tap(find.widgetWithText(Tab, 'Classes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nouvelle classe'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Nom de la classe'), '6e A');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Créer'));
    await tester.pumpAndSettle();
    expect(ctrl.classOf('6e A').subjects.length, 10);
    expect(app.classes, contains('6e A'), reason: 'la classe existe partout, même sans élève');
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Nouveau professeur, puis attribution des maths de la 6e A.
    await tester.tap(find.widgetWithText(Tab, 'Professeurs'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ajouter un professeur'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Nom et prénom'), 'M. Ouédraogo');
    await tester.tap(find.text('Attribuer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mathématiques'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Attribuer'));
    await tester.pumpAndSettle();
    final t = ctrl.book.teachers.single;
    expect(ctrl.assignments(t.id).single.$2.name, 'Mathématiques');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(find.textContaining('5 h/semaine'), findsOneWidget);

    // Génération de l'emploi du temps.
    await tester.tap(find.widgetWithText(Tab, 'Emploi du temps'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Générer automatiquement'));
    await tester.pumpAndSettle();
    final placed = ctrl.book.timetable['6e A']!.length;
    expect(placed, ctrl.classOf('6e A').subjects.fold(0, (a, s) => a + s.hours));
    expect(find.text('Mathématiques'), findsWidgets);
    await tester.pump(const Duration(seconds: 5));
  });
}
