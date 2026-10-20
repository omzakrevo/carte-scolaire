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

  // ---------- Projets ----------
  final List<ProjectInfo> projects = [];
  String projectId = '';
  String get projectName =>
      projects.firstWhere((p) => p.id == projectId, orElse: () => ProjectInfo(name: 'Projet')).name;

  Future<void> load() async {
    try {
      savedTemplates
        ..clear()
        ..addAll(await Storage.loadSavedTemplates());
      final (list, current) = await Storage.loadIndex();
      projects
        ..clear()
        ..addAll(list);
      if (projects.isEmpty) {
        final p = ProjectInfo(name: 'Mon premier projet');
        projects.add(p);
        projectId = p.id;
      } else {
        projectId = projects.any((p) => p.id == current) ? current! : projects.first.id;
        await Storage.loadProject(this, projectId);
      }
    } catch (_) {
      // Premier lancement ou fichier illisible : on garde les valeurs par défaut.
      if (projects.isEmpty) {
        final p = ProjectInfo(name: 'Mon premier projet');
        projects.add(p);
        projectId = p.id;
      }
    }
    loaded = true;
    notifyListeners();
  }

  void changed() {
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), () => flush().catchError((_) {}));
  }

  /// Enregistre immédiatement le projet ouvert et la liste des projets.
  Future<void> flush() async {
    _saveTimer?.cancel();
    if (projectId.isEmpty) return;
    final info = projects.firstWhere((p) => p.id == projectId);
    info
      ..schoolName = school.name
      ..studentCount = students.length
      ..photoCount = photoCount
      ..updated = DateTime.now();
    await Storage.saveProject(this);
    await Storage.saveIndex(projects, projectId);
    await Storage.saveSavedTemplates(savedTemplates);
  }

  /// Nouveau projet. Avec [fromCurrent], reprend le modèle (et l'établissement) actuels.
  Future<void> createProject(String name, {bool keepTemplate = true, bool keepSchool = false}) async {
    await flush();
    final p = ProjectInfo(name: name);
    final t = keepTemplate ? template.copy() : CardTemplate();
    final sc = keepSchool ? SchoolInfo.fromJson(school.toJson()) : SchoolInfo(name: name, shortName: '');
    projects.insert(0, p);
    projectId = p.id;
    template = t;
    school = sc;
    students.clear();
    currentIndex = 0;
    await flush();
    notifyListeners();
  }

  Future<void> openProject(String id) async {
    if (id == projectId) return;
    await flush();
    await Storage.loadProject(this, id);
    await Storage.saveIndex(projects, projectId);
    notifyListeners();
  }

  Future<void> renameProject(ProjectInfo p, String name) async {
    p.name = name;
    await Storage.saveIndex(projects, projectId);
    notifyListeners();
  }

  Future<void> duplicateProject(ProjectInfo p) async {
    await flush();
    final copy = ProjectInfo(
      name: '${p.name} (copie)',
      schoolName: p.schoolName,
      studentCount: p.studentCount,
      photoCount: p.photoCount,
    );
    await Storage.duplicateProject(p.id, copy.id);
    projects.insert(projects.indexOf(p) + 1, copy);
    await Storage.saveIndex(projects, projectId);
    notifyListeners();
  }

  Future<void> deleteProject(ProjectInfo p) async {
    projects.remove(p);
    await Storage.deleteProject(p.id);
    if (p.id == projectId) {
      if (projects.isEmpty) {
        final n = ProjectInfo(name: 'Nouveau projet');
        projects.add(n);
        projectId = n.id;
        template = CardTemplate();
        school = SchoolInfo();
        students.clear();
        await flush();
      } else {
        await Storage.loadProject(this, projects.first.id);
      }
    }
    await Storage.saveIndex(projects, projectId);
    notifyListeners();
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
  void saveTemplateAs(String name, {bool withSchool = true}) {
    savedTemplates.add(SavedTemplate(
      name: name,
      template: template.copy(),
      school: withSchool ? SchoolInfo.fromJson(school.toJson()) : null,
    ));
    changed();
  }

  void overwriteSaved(SavedTemplate t) {
    t.template = template.copy();
    if (t.school != null) t.school = SchoolInfo.fromJson(school.toJson());
    changed();
  }

  /// Applique un modèle enregistré ; avec [withSchool], reprend aussi l'établissement.
  void applySaved(SavedTemplate t, {bool withSchool = false}) {
    template = t.template.copy();
    if (withSchool && t.school != null) school = SchoolInfo.fromJson(t.school!.toJson());
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

  void setPhoto(Student s, Uint8List? bytes, {Uint8List? original, bool keepOriginal = false}) {
    s.photo = bytes;
    if (!keepOriginal) s.original = bytes == null ? null : original;
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
