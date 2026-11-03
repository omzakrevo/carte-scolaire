import 'package:flutter/material.dart';

import 'photo_screen.dart';
import 'print_screen.dart';
import 'template_screen.dart';

/// Les cartes, en trois étapes : modèle, photos, impression.
class CardsScreen extends StatefulWidget {
  /// Ouvre la liste des personnes (élèves, employés…).
  final VoidCallback onGoToPeople;
  const CardsScreen({super.key, required this.onGoToPeople});

  @override
  State<CardsScreen> createState() => CardsScreenState();
}

class CardsScreenState extends State<CardsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  /// 0 = modèle, 1 = photos, 2 = impression.
  void show(int step) => _tabs.animateTo(step);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Material(
        color: Theme.of(context).colorScheme.surface,
        child: TabBar(controller: _tabs, tabs: const [
          Tab(icon: Icon(Icons.style_outlined), text: 'Modèle'),
          Tab(icon: Icon(Icons.photo_camera_outlined), text: 'Photos'),
          Tab(icon: Icon(Icons.print_outlined), text: 'Impression'),
        ]),
      ),
      Expanded(
        child: TabBarView(controller: _tabs, physics: const NeverScrollableScrollPhysics(), children: [
          TemplateScreen(onNext: () => show(1)),
          PhotoScreen(onGoToStudents: widget.onGoToPeople, onNext: () => show(2)),
          const PrintScreen(),
        ]),
      ),
    ]);
  }
}
