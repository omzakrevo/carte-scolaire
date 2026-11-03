import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';

import '../app_state.dart';
import '../models.dart';
import '../services/storage.dart';
import 'attendance_models.dart';
import 'sms_service.dart';

/// Résultat d'un passage de carte, affiché par la borne.
class ScanResult {
  final Student? student;
  final bool entry;
  final DateTime time;
  final bool late;

  /// Passage ignoré (même carte relue trop vite).
  final bool duplicate;
  final String code;

  /// Temps de présence cumulé aujourd'hui (minutes), utile en entreprise.
  final int workedMin;

  ScanResult(
      {this.student,
      this.entry = true,
      required this.time,
      this.late = false,
      this.duplicate = false,
      this.code = '',
      this.workedMin = 0});

  bool get unknown => student == null;
}

/// Présences du projet ouvert : pointages, statuts, SMS d'absence automatiques.
/// Tout est enregistré sur l'appareil, dans le dossier du projet.
class AttendanceController extends ChangeNotifier {
  final AppState app;

  /// Le SMS automatique n'est envoyé qu'avec une licence active.
  bool Function() smsAllowed = () => true;

  /// Pour les tests : heure simulée.
  DateTime Function() clock = DateTime.now;

  /// Pour les tests : envoi simulé.
  Future<void> Function(String to, String text) sender = SmsService.send;

  AttendanceSettings settings = AttendanceSettings();
  final Map<String, DayRecord> _days = {};
  String? _projectId;

  /// Pause entre deux SMS (évite le blocage par l'opérateur).
  Duration smsGap = const Duration(milliseconds: 1500);
  bool loaded = false;
  bool sending = false;
  String? lastSendReport;
  Timer? _timer;
  Timer? _saveTimer;
  final Set<String> _dirty = {};

  AttendanceController(this.app) {
    app.addListener(_onApp);
    _onApp();
  }

  /// Lance la vérification périodique de l'heure des absences (appelé au démarrage de l'appli).
  void start() {
    _timer ??= Timer.periodic(const Duration(seconds: 30), (_) => checkAutoAbsences());
  }

  @override
  void dispose() {
    app.removeListener(_onApp);
    _timer?.cancel();
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

  // ---------------- Stockage ----------------

  Future<Directory> _dir([String? projectId]) async {
    final pid = projectId ?? _projectId ?? '';
    final s = Platform.pathSeparator;
    final base = (await Storage.baseDir()).path;
    final d = Directory('$base${s}projects$s$pid${s}attendance');
    await d.create(recursive: true);
    return d;
  }

  Future<void> _load() async {
    loaded = false;
    _days.clear();
    settings = AttendanceSettings();
    if (_projectId!.isEmpty) {
      loaded = true;
      notifyListeners();
      return;
    }
    notifyListeners();
    try {
      final d = await _dir();
      final f = File('${d.path}${Platform.pathSeparator}settings.json');
      if (await f.exists()) settings = AttendanceSettings.fromJson(jsonDecode(await f.readAsString()));
      await loadDay(clock());
    } catch (_) {}
    loaded = true;
    notifyListeners();
    checkAutoAbsences();
  }

  Future<DayRecord> loadDay(DateTime date) async {
    final k = dateKey(date);
    final cached = _days[k];
    if (cached != null) return cached;
    DayRecord rec = DayRecord(k);
    try {
      final f = File('${(await _dir()).path}${Platform.pathSeparator}$k.json');
      if (await f.exists()) rec = DayRecord.fromJson(jsonDecode(await f.readAsString()));
    } catch (_) {}
    return _days[k] ??= rec;
  }

  DayRecord? cachedDay(DateTime date) => _days[dateKey(date)];

  /// Jours enregistrés entre deux dates (incluses), chargés depuis le disque.
  Future<List<DayRecord>> daysBetween(DateTime from, DateTime to) async {
    final out = <DayRecord>[];
    final d = await _dir();
    final files =
        await d.list().where((e) => e is File && RegExp(r'\d{4}-\d{2}-\d{2}\.json$').hasMatch(e.path)).toList();
    final a = dateKey(from), b = dateKey(to);
    final keys = files
        .map((f) => f.uri.pathSegments.last.replaceAll('.json', ''))
        .where((k) => k.compareTo(a) >= 0 && k.compareTo(b) <= 0)
        .toSet();
    for (final k in _days.keys) {
      if (k.compareTo(a) >= 0 && k.compareTo(b) <= 0) keys.add(k);
    }
    for (final k in keys.toList()..sort()) {
      out.add(await loadDay(parseDateKey(k)));
    }
    return out;
  }

  void _touch(DayRecord d) {
    _dirty.add(d.date);
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), () => flush());
  }

  Future<void> flush() async {
    _saveTimer?.cancel();
    final pid = _projectId ?? '';
    if (pid.isEmpty || _dirty.isEmpty) return;
    // Copie avant toute attente : le projet peut changer pendant l'écriture.
    final pending = {
      for (final k in _dirty)
        if (_days[k] != null) k: jsonEncode(_days[k]!.toJson())
    };
    _dirty.clear();
    try {
      final d = await _dir(pid);
      for (final e in pending.entries) {
        final f = File('${d.path}${Platform.pathSeparator}${e.key}.json');
        final tmp = File('${f.path}.tmp');
        await tmp.writeAsString(e.value);
        await tmp.rename(f.path);
      }
    } catch (_) {
      if (pid == _projectId) _dirty.addAll(pending.keys);
    }
  }

  Future<void> saveSettings() async {
    notifyListeners();
    try {
      final d = await _dir();
      await File('${d.path}${Platform.pathSeparator}settings.json').writeAsString(jsonEncode(settings.toJson()));
    } catch (_) {}
  }

  // ---------------- Pointage ----------------

  DayRecord get today => _days[dateKey(clock())] ??= DayRecord(dateKey(clock()));

  /// Traite un code lu par la caméra ou la douchette.
  ScanResult scan(String code, {String source = 'camera'}) {
    final now = clock();
    final s = findStudentByCode(code, app.students);
    if (s == null) return ScanResult(time: now, code: code.trim());
    final day = today;
    final previous = day.eventsOf(s.id)..sort((a, b) => a.time.compareTo(b.time));
    if (previous.isNotEmpty && now.difference(previous.last.time).inSeconds < settings.doubleScanSeconds) {
      return ScanResult(student: s, entry: previous.last.entry, time: previous.last.time, duplicate: true, code: code);
    }
    final entry = switch (settings.mode) {
      ScanMode.entry => true,
      ScanMode.exit => false,
      ScanMode.auto => previous.isEmpty || !previous.last.entry,
    };
    day.events.add(ScanEvent(studentId: s.id, time: now, entry: entry, source: source));
    // Un élève qui arrive n'est plus « absent » s'il avait été marqué ainsi.
    if (entry && day.overrides[s.id] == DayOverride.absent) day.overrides.remove(s.id);
    _touch(day);
    final late = entry && previous.where((e) => e.entry).isEmpty && now.isAfter(settings.lateLimit(now));
    final worked = computeDay(s, day, settings, now, now: now).workedMin;
    return ScanResult(student: s, entry: entry, time: now, late: late, code: code, workedMin: worked);
  }

  void setOverride(Student s, DayOverride? o, {DateTime? date}) {
    final day = date == null ? today : (_days[dateKey(date)] ??= DayRecord(dateKey(date)));
    if (o == null) {
      day.overrides.remove(s.id);
    } else {
      day.overrides[s.id] = o;
    }
    _touch(day);
  }

  void setClosed(bool closed) {
    today.closed = closed;
    _touch(today);
  }

  void undoLast(Student s) {
    final day = today;
    final ev = day.eventsOf(s.id)..sort((a, b) => a.time.compareTo(b.time));
    if (ev.isEmpty) return;
    day.events.remove(ev.last);
    _touch(day);
  }

  List<StudentDay> todaySummary() {
    final now = clock();
    return [for (final s in app.students) computeDay(s, today, settings, now, now: now)];
  }

  /// Pointage d'entreprise (heures de travail) ou d'école (absences des élèves).
  bool get isCompany => settings.company ?? !app.isSchool;

  /// Envoi automatique des SMS activé pour le mode en cours.
  bool get autoSmsOn => isCompany ? settings.companySms : settings.autoSms;

  bool get isSchoolDay => settings.schoolDays.contains(clock().weekday) && !today.closed;

  // ---------------- SMS d'absence ----------------

  /// Élèves absents aujourd'hui à qui aucun SMS n'a encore été envoyé avec succès.
  List<StudentDay> pendingAbsences() => todaySummary()
      .where((d) => d.status == DayStatus.absent && !(today.sms[d.student.id]?.startsWith('Envoyé') ?? false))
      .toList();

  String get smsTemplate => isCompany && settings.smsTemplate == AttendanceSettings.defaultTemplate
      ? AttendanceSettings.companyTemplate
      : settings.smsTemplate;

  String messageFor(Student s) =>
      buildSms(smsTemplate, s, app.school, clock(), withoutAccents: settings.smsWithoutAccents);

  /// Appelée régulièrement : après l'heure limite, envoie une seule fois les SMS du jour.
  Future<void> checkAutoAbsences() async {
    if (!loaded || sending || app.students.isEmpty) return;
    final now = clock();
    final day = today;
    if (day.absencesProcessed || !isSchoolDay || now.isBefore(settings.absenceLimit(now))) return;
    // Une école qui n'a pointé personne n'a sans doute pas ouvert : on n'envoie rien.
    if (day.events.isEmpty) return;
    final canSend = SmsService.supported || sender != SmsService.send;
    if (!autoSmsOn || !canSend || !smsAllowed()) {
      day.absencesProcessed = true;
      _touch(day);
      return;
    }
    await sendAbsenceSms();
  }

  /// Envoie le SMS d'absence aux parents. Renvoie (envoyés, échecs, sans numéro).
  Future<(int, int, int)> sendAbsenceSms({List<Student>? only}) async {
    if (sending) return (0, 0, 0);
    sending = true;
    notifyListeners();
    var ok = 0, ko = 0, noPhone = 0;
    final day = today;
    try {
      final targets = only ?? pendingAbsences().map((d) => d.student).toList();
      for (final s in targets) {
        final to = normalizePhone(s.contact, settings.countryCode);
        if (to == null) {
          day.sms[s.id] = 'Pas de numéro';
          noPhone++;
          continue;
        }
        try {
          await sender(to, messageFor(s));
          day.sms[s.id] = 'Envoyé ${hhmm(clock())}';
          ok++;
        } catch (e) {
          day.sms[s.id] = 'Échec : $e';
          ko++;
        }
        _touch(day);
        if (smsGap > Duration.zero) await Future.delayed(smsGap);
      }
      if (only == null) day.absencesProcessed = true;
      lastSendReport =
          '$ok SMS envoyé(s)${ko > 0 ? ', $ko échec(s)' : ''}${noPhone > 0 ? ', $noPhone élève(s) sans numéro' : ''}';
    } finally {
      sending = false;
      _touch(day);
    }
    return (ok, ko, noPhone);
  }
}

class AttendanceScope extends InheritedNotifier<AttendanceController> {
  const AttendanceScope({super.key, required AttendanceController controller, required super.child})
      : super(notifier: controller);

  static AttendanceController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AttendanceScope>()!.notifier!;

  static AttendanceController read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AttendanceScope>()!.notifier!;
}
