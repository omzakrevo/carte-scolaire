import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';

import '../app_state.dart';
import '../attendance/attendance_controller.dart';
import '../attendance/attendance_models.dart';
import '../models.dart';
import '../services/storage.dart';
import 'school_engine.dart';
import 'school_models.dart';

/// Notes, moyennes et bulletins du projet ouvert. Fichier : projects/<id>/gestion.json.
class SchoolController extends ChangeNotifier {
  final AppState app;
  final AttendanceController? attendance;

  GradeBook book = GradeBook();
  bool loaded = false;
  String? _projectId;
  Timer? _saveTimer;

  /// Absences issues du pointage, par période puis par élève.
  final Map<String, Map<String, AbsenceCount>> _auto = {};

  SchoolController(this.app, {this.attendance}) {
    app.addListener(_onApp);
    _onApp();
  }

  @override
  void dispose() {
    app.removeListener(_onApp);
    _saveTimer?.cancel();
    super.dispose();
  }

  void _onApp() {
    if (app.loaded && app.projectId != _projectId) {
      flush();
      _projectId = app.projectId;
      _load();
    }
  }

  Future<File> _file(String pid) async {
    final s = Platform.pathSeparator;
    final d = Directory('${(await Storage.baseDir()).path}${s}projects$s$pid');
    await d.create(recursive: true);
    return File('${d.path}${s}gestion.json');
  }

  Future<void> _load() async {
    loaded = false;
    book = GradeBook();
    _auto.clear();
    final pid = _projectId ?? '';
    if (pid.isEmpty) {
      loaded = true;
      notifyListeners();
      return;
    }
    notifyListeners();
    try {
      final f = await _file(pid);
      if (await f.exists()) book = GradeBook.fromJson(jsonDecode(await f.readAsString()));
    } catch (_) {}
    if (pid != _projectId) return;
    loaded = true;
    notifyListeners();
  }

  /// À appeler après chaque modification.
  void changed() {
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 700), flush);
  }

  Future<void> flush() async {
    _saveTimer?.cancel();
    final pid = _projectId ?? '';
    if (pid.isEmpty || !loaded) return;
    final text = jsonEncode(book.toJson());
    try {
      final f = await _file(pid);
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(text);
      await tmp.rename(f.path);
    } catch (_) {}
  }

  // ---------------- Classes et élèves ----------------

  List<String> get classNames => app.classes;

  List<Student> studentsOf(String className) =>
      app.students.where((s) => s.classe.trim() == className).toList()
        ..sort((a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));

  ClassConfig classOf(String name) => book.classOf(name);

  // ---------------- Absences ----------------

  Map<String, AbsenceCount> autoAbsences(String periodId) => _auto[periodId] ?? const {};

  /// Recompte les absences du pointage pour une période (selon ses dates).
  Future<void> refreshAbsences(Period p) async {
    final att = attendance;
    if (att == null || !book.settings.useAttendance || p.start == null || p.end == null) {
      _auto.remove(p.id);
      notifyListeners();
      return;
    }
    try {
      await att.flush();
      final days = await att.daysBetween(p.start!, p.end!);
      _auto[p.id] = countAbsences(days, app.students, att.settings);
    } catch (_) {
      _auto.remove(p.id);
    }
    notifyListeners();
  }

  // ---------------- Résultats ----------------

  ClassResults results(String className, Period p) =>
      computeClass(book, classOf(className), studentsOf(className), p, auto: autoAbsences(p.id));

  List<AnnualResult> annual(String className) {
    final cls = classOf(className);
    final per = [for (final p in book.settings.periods) results(className, p)];
    return computeAnnual(book, cls, per);
  }
}

/// Compte les absences d'après les journées de pointage : un jour fermé ou sans aucun
/// passage n'est pas compté (l'établissement n'a pas pointé ce jour-là).
Map<String, AbsenceCount> countAbsences(List<DayRecord> days, List<Student> students, AttendanceSettings st) {
  final out = <String, AbsenceCount>{};
  for (final d in days) {
    if (d.closed || d.events.isEmpty) continue;
    final date = parseDateKey(d.date);
    final endOfDay = DateTime(date.year, date.month, date.day, 23, 59);
    for (final s in students) {
      final r = computeDay(s, d, st, date, now: endOfDay);
      final a = out.putIfAbsent(s.id, () => AbsenceCount());
      switch (r.status) {
        case DayStatus.absent:
          a.unjustified++;
        case DayStatus.excused:
          a.justified++;
        case DayStatus.late:
          a.lates++;
        default:
          break;
      }
    }
  }
  return out;
}

class SchoolScope extends InheritedNotifier<SchoolController> {
  const SchoolScope({super.key, required SchoolController controller, required super.child})
      : super(notifier: controller);

  static SchoolController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SchoolScope>()!.notifier!;

  static SchoolController read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<SchoolScope>()!.notifier!;
}
