import 'package:carte_scolaire/app_state.dart';
import 'package:carte_scolaire/attendance/attendance_controller.dart';
import 'package:carte_scolaire/main.dart';
import 'package:carte_scolaire/models.dart';
import 'package:carte_scolaire/school/school_controller.dart';
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
      final att = AttendanceController(state);
      addTearDown(att.dispose);
      final school = SchoolController(state, attendance: att);
      addTearDown(school.dispose);
      await tester.pumpWidget(LicenseScope(
          manager: lm,
          child: AppScope(
              state: state,
              child: AttendanceScope(
                  controller: att, child: SchoolScope(controller: school, child: const CarteScolaireApp())))));
      await tester.pumpAndSettle();
      expect(find.text('Choisir un modèle'), findsOneWidget);

      expect(find.text('Version d\'essai'), findsWidgets);
      for (final label in [
        'Présences',
        'Aujourd\'hui',
        'Rapport Excel',
        'Réglages',
        'Projets',
        'Élèves',
        'Photos',
        'Impression',
        'Notes',
        'Classes et matières',
        'Saisie des notes',
        'Résultats',
        'Bulletins',
        'Réglages',
        'Impression',
      ]) {
        // Barre de navigation : par l'info-bulle (libellés masqués sur téléphone) ; onglets : par le texte.
        final byTip = find.byTooltip(label);
        await tester.tap(byTip.evaluate().isNotEmpty ? byTip.last : find.text(label).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: label);
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
    await tester.ensureVisible(find.text('Réinitialiser cet élément'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Réinitialiser cet élément'));
    await tester.pump();
    expect(state.template.layers[id], isNull);
    await tester.pump(const Duration(seconds: 2)); // sauvegarde différée
    expect(tester.takeException(), isNull);
  });

  testWidgets('notes : programme, saisie, résultats, et espace entreprise', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = AppState()..loaded = true;
    state.projects.add(ProjectInfo(name: 'Collège', id: 'p1'));
    state.students.addAll([
      Student(nom: 'Ouédraogo', prenom: 'Awa', classe: '3e A', sexe: 'F'),
      Student(nom: 'Kaboré', prenom: 'Jean', classe: '3e A', sexe: 'M'),
    ]);
    final lm = LicenseManager()..debugUnlocked();
    final att = AttendanceController(state);
    addTearDown(att.dispose);
    final school = SchoolController(state, attendance: att)..loaded = true;
    addTearDown(school.dispose);
    await tester.pumpWidget(LicenseScope(
        manager: lm,
        child: AppScope(
            state: state,
            child: AttendanceScope(
                controller: att, child: SchoolScope(controller: school, child: const CarteScolaireApp())))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Notes').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Programme prêt à l\'emploi'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Post-primaire'));
    await tester.pumpAndSettle();
    expect(school.classOf('3e A').subjects.length, 10);
    expect(find.text('Français'), findsOneWidget);

    await tester.tap(find.text('Saisie des notes'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).hitTestable().first, '14,5');
    await tester.pumpAndSettle();
    final p = school.book.settings.periods.first;
    final fr = school.classOf('3e A').subjects.first;
    final jean = state.students[1]; // premier par ordre alphabétique
    expect(school.book.note(p.id, jean.id, fr.id, school.book.settings.evals.first.id), 14.5);

    await tester.tap(find.text('Résultats'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('14,50'), findsWidgets);
    await tester.tap(find.text('Bulletins'));
    await tester.pumpAndSettle();
    expect(find.text('Moderne'), findsOneWidget);

    // Espace entreprise : pas d'onglet Notes, le pointage s'appelle « Pointage ».
    await tester.tap(find.text('Projets').last);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Entreprises'));
    await tester.pumpAndSettle();
    expect(find.text('Aucun projet entreprise pour l\'instant.'), findsOneWidget);
    state.template.kind = 'pro';
    state.changed();
    await tester.pump();
    expect(state.isSchool, isFalse);
    expect(find.text('Notes'), findsNothing);
    expect(find.text('Pointage'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });
}
