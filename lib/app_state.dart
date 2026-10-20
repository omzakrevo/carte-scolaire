import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'designs/card_designs.dart';
import 'models.dart';
import 'services/storage.dart';

/// État global de l'application (modèle, école, élèves) avec sauvegarde auto.
class AppState extends ChangeNotifier {
  CardTemplate template = CardTemplate();
  SchoolInfo school = SchoolInfo();
  final List<Student> students = [];
  final List<SavedTemplate> savedTemplates = [];
  PrintLayout layout = PrintLayout();
  int currentIndex = 0;
  bool loaded = false;

  Timer? _saveTimer;

  Future<void> load() async {
    try {
      await Storage.load(this);
    } catch (_) {
      // Premier lancement ou fichier illisible : on garde les valeurs par défaut.
    }
    loaded = true;
    notifyListeners();
  }

  void changed() {
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), () {
      Storage.save(this).catchError((_) {});
    });
  }

  // ---------- Modèle ----------
  void selectDesign(CardDesign d) {
    template.designId = d.id;
    template.primary = d.primary;
    template.secondary = d.secondary;
    template.accent = d.accent;
    template.widthMm = d.defaultWidth;
    template.heightMm = d.defaultHeight;
    changed();
  }

  void setSize(double w, double h) {
    template.widthMm = w.clamp(30, 150).toDouble();
    template.heightMm = h.clamp(30, 150).toDouble();
    changed();
  }

  // ---------- Mes modèles ----------
  void saveTemplateAs(String name) {
    savedTemplates.add(SavedTemplate(name: name, template: template.copy()));
    changed();
  }

  void overwriteSaved(SavedTemplate t) {
    t.template = template.copy();
    changed();
  }

  void applySaved(SavedTemplate t) {
    template = t.template.copy();
    changed();
  }

  void renameSaved(SavedTemplate t, String name) {
    t.name = name;
    changed();
  }

  void deleteSaved(SavedTemplate t) {
    savedTemplates.remove(t);
    changed();
  }

  void swapOrientation() => setSize(template.heightMm, template.widthMm);

  // ---------- Élèves ----------
  Student? get current => students.isEmpty ? null : students[currentIndex.clamp(0, students.length - 1)];

  List<String> get classes {
    final set = <String>{
      for (final s in students)
        if (s.classe.trim().isNotEmpty) s.classe.trim()
    };
    final list = set.toList()..sort();
    return list;
  }

  int get photoCount => students.where((s) => s.photo != null).length;
  int get validatedCount => students.where((s) => s.validated).length;

  void addStudents(List<Student> list, {bool replace = false}) {
    if (replace) {
      students.clear();
      currentIndex = 0;
    }
    students.addAll(list);
    changed();
  }

  void upsertStudent(Student s) {
    final i = students.indexWhere((e) => e.id == s.id);
    if (i >= 0) {
      students[i] = s;
    } else {
      students.add(s);
    }
    changed();
  }

  void removeStudent(Student s) {
    students.removeWhere((e) => e.id == s.id);
    if (currentIndex >= students.length) currentIndex = students.isEmpty ? 0 : students.length - 1;
    changed();
  }

  void clearStudents() {
    students.clear();
    currentIndex = 0;
    changed();
  }

  void goTo(int index) {
    if (students.isEmpty) return;
    currentIndex = index.clamp(0, students.length - 1);
    notifyListeners();
  }

  void move(int delta) => goTo(currentIndex + delta);

  /// Premier élève sans photo à partir de la position actuelle.
  void nextWithoutPhoto() {
    for (var k = 1; k <= students.length; k++) {
      final i = (currentIndex + k) % students.length;
      if (students[i].photo == null) {
        goTo(i);
        return;
      }
    }
    move(1);
  }

  void setPhoto(Student s, Uint8List? bytes) {
    s.photo = bytes;
    s.photoVersion++;
    if (bytes == null) s.validated = false;
    changed();
  }

  void setValidated(Student s, bool v) {
    s.validated = v;
    changed();
  }

  List<Student> printable() => students.where((s) {
        if (layout.onlyValidated && !s.validated) return false;
        final c = layout.classFilter;
        if (c != null && c.isNotEmpty && s.classe.trim() != c) return false;
        return true;
      }).toList();
}

/// Rend l'état accessible à tous les écrans.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  static AppState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  static AppState read(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
