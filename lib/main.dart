import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'screens/photo_screen.dart';
import 'screens/print_screen.dart';
import 'screens/students_screen.dart';
import 'screens/template_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState()..load();
  runApp(AppScope(state: state, child: const CarteScolaireApp()));
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
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  void goTo(int i) => setState(() => _index = i);

  static const _dest = [
    (Icons.style_outlined, Icons.style, 'Modèle'),
    (Icons.groups_outlined, Icons.groups, 'Élèves'),
    (Icons.photo_camera_outlined, Icons.photo_camera, 'Photos'),
    (Icons.print_outlined, Icons.print, 'Impression'),
  ];

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    if (!state.loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final pages = [
      TemplateScreen(onNext: () => goTo(1)),
      StudentsScreen(onNext: () => goTo(2)),
      PhotoScreen(onGoToStudents: () => goTo(1), onNext: () => goTo(3)),
      const PrintScreen(),
    ];
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final stats = Text(
      '${state.students.length} élèves · ${state.photoCount} photos · ${state.validatedCount} validées',
      style: Theme.of(context).textTheme.bodySmall,
    );

    final body = IndexedStack(index: _index, children: pages);
    if (wide) {
      return Scaffold(
        body: Row(children: [
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: goTo,
            labelType: NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(children: [
                Icon(Icons.badge, size: 32, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 4),
                Text('Carte\nScolaire',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800)),
              ]),
            ),
            destinations: [
              for (final (i, a, l) in _dest)
                NavigationRailDestination(icon: Icon(i), selectedIcon: Icon(a), label: Text(l)),
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
                  Text(_dest[_index].$3, style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  stats,
                ]),
              ),
              const Divider(height: 1),
              Expanded(child: body),
            ]),
          ),
        ]),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_dest[_index].$3),
          stats,
        ]),
      ),
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: goTo,
        destinations: [
          for (final (i, a, l) in _dest) NavigationDestination(icon: Icon(i), selectedIcon: Icon(a), label: l),
        ],
      ),
    );
  }
}
