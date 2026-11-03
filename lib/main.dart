import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'card_kinds.dart';
import 'attendance/attendance_controller.dart';
import 'attendance/attendance_screen.dart';
import 'school/school_controller.dart';
import 'school/establishment_screen.dart';
import 'school/school_screen.dart';
import 'screens/cards_screen.dart';
import 'widgets/org_info_form.dart';
import 'screens/projects_screen.dart';
import 'screens/security_screens.dart';
import 'services/license.dart';
import 'screens/students_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState()..load();
  final license = LicenseManager()..load();
  final attendance = AttendanceController(state)
    ..smsAllowed = (() => license.isLicensed)
    ..start();
  final school = SchoolController(state, attendance: attendance);
  runApp(LicenseScope(
    manager: license,
    child: AppScope(
      state: state,
      child: AttendanceScope(
        controller: attendance,
        child: SchoolScope(controller: school, child: const CarteScolaireApp()),
      ),
    ),
  ));
}

bool get isDesktop =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux);

class CarteScolaireApp extends StatelessWidget {
  const CarteScolaireApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF0B6B3A));
    return MaterialApp(
      title: 'Carte Scolaire',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF4F6F3),
        inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder(), isDense: true),
        cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0B6B3A), brightness: Brightness.dark),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder(), isDense: true),
        cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
      ),
      home: const SecurityGate(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

/// Une destination de la navigation.
class _Dest {
  final String key;
  final IconData icon;
  final IconData selected;
  final String label;
  final Widget page;
  const _Dest(this.key, this.icon, this.selected, this.label, this.page);
}

class _HomeShellState extends State<HomeShell> {
  /// Destination affichée (« hub », « people », « cards », « presence », « notes », « projects »).
  String _key = 'hub';
  String? _segment;
  final _cards = GlobalKey<CardsScreenState>();

  void go(String key) => setState(() => _key = key);

  Future<void> _more(BuildContext context, List<_Dest> extra) async {
    final k = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final d in extra)
            ListTile(
              leading: Icon(d.key == _key ? d.selected : d.icon),
              title: Text(d.label),
              selected: d.key == _key,
              onTap: () => Navigator.pop(c, d.key),
            ),
        ]),
      ),
    );
    if (k != null) go(k);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    if (!state.loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final kind = kindById(state.template.kind);
    final school = state.isSchool;
    // Changement d'espace (projet d'un autre type) : on revient à l'accueil de l'espace.
    if (_segment != state.segment) {
      _segment = state.segment;
      _key = 'hub';
    }
    final attendance = LicenseScope.moduleOf(context, attendanceModule);
    final grades = school && LicenseScope.moduleOf(context, bulletinModule);
    final dest = <_Dest>[
      if (school)
        const _Dest('hub', Icons.apartment_outlined, Icons.apartment, 'Établissement', EstablishmentScreen())
      else
        const _Dest('hub', Icons.business_outlined, Icons.business, 'Entreprise', CompanyScreen()),
      _Dest('people', Icons.groups_outlined, Icons.groups, kind.people,
          StudentsScreen(onNext: () {
            go('cards');
            _cards.currentState?.show(1);
          })),
      if (grades) const _Dest('notes', Icons.grading_outlined, Icons.grading, 'Notes', SchoolScreen()),
      if (attendance)
        _Dest('presence', Icons.fact_check_outlined, Icons.fact_check, school ? 'Présences' : 'Pointage',
            AttendanceScreen(active: _key == 'presence')),
      _Dest('cards', Icons.badge_outlined, Icons.badge, 'Cartes',
          CardsScreen(key: _cards, onGoToPeople: () => go('people'))),
      _Dest('projects', Icons.folder_outlined, Icons.folder, 'Projets', ProjectsScreen(onOpened: () => go('hub'))),
    ];
    var index = dest.indexWhere((d) => d.key == _key);
    if (index < 0) {
      index = 0;
      _key = dest.first.key;
    }
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final stats = Text(
      overflow: TextOverflow.ellipsis,
      '${state.projectName} · ${state.students.length} ${kind.people.toLowerCase()} · ${state.photoCount} photos',
      style: Theme.of(context).textTheme.bodySmall,
    );

    final body = IndexedStack(index: index, children: [for (final d in dest) d.page]);
    if (wide) {
      return Scaffold(
        body: Row(children: [
          NavigationRail(
            selectedIndex: index,
            onDestinationSelected: (i) => go(dest[i].key),
            labelType: NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(children: [
                const AppLogo(size: 40),
                const SizedBox(height: 4),
                Text('Carte\nScolaire',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Tooltip(
                  message: school ? 'Espace établissement' : 'Espace entreprise',
                  child: Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: Icon(school ? Icons.school : Icons.business, size: 16),
                    label: Text(school ? 'École' : 'Entreprise', style: const TextStyle(fontSize: 11)),
                  ),
                ),
              ]),
            ),
            destinations: [
              for (final d in dest)
                NavigationRailDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selected), label: Text(d.label)),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(children: [
              Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                alignment: Alignment.centerLeft,
                child: Row(children: [
                  Text(dest[index].label, style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  Flexible(child: stats),
                  const SizedBox(width: 12),
                  const LicenseChip(),
                ]),
              ),
              const Divider(height: 1),
              Expanded(child: body),
            ]),
          ),
        ]),
      );
    }
    // Téléphone : 5 onglets au maximum, les autres dans « Plus ».
    final overflow = dest.length > 5;
    final main = overflow ? dest.take(4).toList() : dest;
    final extra = overflow ? dest.skip(4).toList() : <_Dest>[];
    final barIndex = index < main.length ? index : main.length;
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(dest[index].label),
          stats,
        ]),
        actions: const [Padding(padding: EdgeInsets.only(right: 8), child: LicenseChip())],
      ),
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: barIndex,
        onDestinationSelected: (i) => i < main.length ? go(main[i].key) : _more(context, extra),
        destinations: [
          for (final d in main) NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selected), label: d.label),
          if (overflow)
            NavigationDestination(
              icon: const Icon(Icons.more_horiz),
              selectedIcon: const Icon(Icons.more_horiz),
              label: index >= main.length ? dest[index].label : 'Plus',
            ),
        ],
      ),
    );
  }
}

/// Accueil de l'espace entreprise : informations de l'entreprise.
class CompanyScreen extends StatelessWidget {
  const CompanyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text(app.school.name.isEmpty ? 'Votre entreprise' : app.school.name,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
      Text('Ces informations figurent sur les cartes (professionnelles, membre, visiteur, visite).',
          style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 14),
      OrgInfoForm(state: app),
    ]);
  }
}

/// Mot de passe, verrouillage et première activation avant d'entrer dans l'application.
class SecurityGate extends StatelessWidget {
  const SecurityGate({super.key});

  @override
  Widget build(BuildContext context) {
    final lm = LicenseScope.of(context);
    if (!lm.loaded) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (!lm.hasPassword) return const SetupPasswordScreen();
    if (!lm.unlocked) return const LockScreen();
    if (!lm.welcomed) return const LicenseScreen(onboarding: true);
    return const HomeShell();
  }
}

/// Pastille « Licence / Essai » qui ouvre l'écran de licence.
class LicenseChip extends StatelessWidget {
  const LicenseChip({super.key});

  @override
  Widget build(BuildContext context) {
    final lm = LicenseScope.of(context);
    final ok = lm.isLicensed;
    return ActionChip(
      avatar: Icon(ok ? Icons.verified : Icons.hourglass_bottom,
          size: 18, color: ok ? const Color(0xFF0B6B3A) : const Color(0xFFB25E00)),
      label: Text(ok ? 'Licence' : 'Version d\'essai'),
      onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LicenseScreen())),
    );
  }
}
