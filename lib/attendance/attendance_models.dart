import 'dart:math' as math;
import '../models.dart';

/// Un passage de carte à l'entrée ou à la sortie.
class ScanEvent {
  final String studentId;
  final DateTime time;
  final bool entry;

  /// camera, douchette, manuel
  final String source;

  ScanEvent({required this.studentId, required this.time, required this.entry, this.source = 'camera'});

  Map<String, dynamic> toJson() =>
      {'s': studentId, 't': time.toIso8601String(), 'e': entry, if (source != 'camera') 'src': source};

  factory ScanEvent.fromJson(Map<String, dynamic> j) => ScanEvent(
        studentId: j['s'] as String,
        time: DateTime.parse(j['t'] as String),
        entry: j['e'] as bool,
        source: (j['src'] as String?) ?? 'camera',
      );
}

/// Correction manuelle de la journée d'un élève.
enum DayOverride { present, excused, absent }

/// Toutes les informations d'une journée de classe.
class DayRecord {
  final String date; // AAAA-MM-JJ
  final List<ScanEvent> events;
  final Map<String, DayOverride> overrides;

  /// Résultat de l'envoi du SMS d'absence, par élève (« envoyé 09:02 », « échec : … »).
  final Map<String, String> sms;

  /// Le traitement automatique des absences a été fait ce jour-là.
  bool absencesProcessed;

  /// Jour sans école (férié, congé) : pas d'absence ni de SMS.
  bool closed;

  DayRecord(this.date,
      {List<ScanEvent>? events,
      Map<String, DayOverride>? overrides,
      Map<String, String>? sms,
      this.absencesProcessed = false,
      this.closed = false})
      : events = events ?? [],
        overrides = overrides ?? {},
        sms = sms ?? {};

  bool get isEmpty => events.isEmpty && overrides.isEmpty && sms.isEmpty && !closed && !absencesProcessed;

  List<ScanEvent> eventsOf(String studentId) => events.where((e) => e.studentId == studentId).toList();

  Map<String, dynamic> toJson() => {
        'date': date,
        'events': events.map((e) => e.toJson()).toList(),
        'overrides': overrides.map((k, v) => MapEntry(k, v.name)),
        'sms': sms,
        'processed': absencesProcessed,
        'closed': closed,
      };

  factory DayRecord.fromJson(Map<String, dynamic> j) => DayRecord(
        j['date'] as String,
        events: (j['events'] as List? ?? []).map((e) => ScanEvent.fromJson(Map<String, dynamic>.from(e))).toList(),
        overrides: (j['overrides'] as Map? ?? {}).map((k, v) => MapEntry(
            k.toString(), DayOverride.values.firstWhere((o) => o.name == v, orElse: () => DayOverride.present))),
        sms: (j['sms'] as Map? ?? {}).map((k, v) => MapEntry(k.toString(), v.toString())),
        absencesProcessed: j['processed'] ?? false,
        closed: j['closed'] ?? false,
      );
}

/// Mode de la borne : entrée, sortie, ou automatique (1er passage = entrée, puis alternance).
enum ScanMode { auto, entry, exit }

/// Réglages des présences (un jeu par projet / établissement).
class AttendanceSettings {
  /// Heure de début des cours (« 07:30 ») et tolérance avant d'être en retard.
  String startTime;
  int lateToleranceMin;

  /// Heure à laquelle un élève sans pointage est déclaré absent et le SMS part.
  String absenceTime;

  bool autoSms;
  bool smsWithoutAccents;
  String smsTemplate;

  /// Indicatif du pays ajouté aux numéros à 8 chiffres.
  String countryCode;

  /// Jours d'école : 1 = lundi … 7 = dimanche.
  Set<int> schoolDays;

  /// Ignore un 2e passage de la même carte pendant ce délai.
  int doubleScanSeconds;

  ScanMode mode;

  /// Pointage d'entreprise : heures de travail au lieu des absences d'élèves.
  /// `null` = selon le type de carte du projet (carte professionnelle → entreprise).
  bool? company;

  /// Entreprise : heure de fin de journée et pause (déduite si l'employé ne pointe pas à midi).
  String endTime;
  int breakMin;

  /// Entreprise : SMS à l'employé non pointé (désactivé par défaut).
  bool companySms;

  static const companyTemplate =
      'Bonjour {prenom}, {ecole} n\'a pas enregistré votre arrivée ce {date}. Merci de prévenir votre responsable.';

  static const defaultTemplate =
      'Bonjour, {ecole} vous informe que {prenom} {nom} ({classe}) est absent(e) ce {date}. Merci de nous contacter.';

  AttendanceSettings({
    this.startTime = '07:30',
    this.lateToleranceMin = 10,
    this.absenceTime = '09:00',
    this.autoSms = true,
    this.smsWithoutAccents = false,
    this.smsTemplate = defaultTemplate,
    this.countryCode = '226',
    Set<int>? schoolDays,
    this.doubleScanSeconds = 60,
    this.mode = ScanMode.auto,
    this.company,
    this.endTime = '17:00',
    this.breakMin = 60,
    this.companySms = false,
  }) : schoolDays = schoolDays ?? {1, 2, 3, 4, 5};

  Map<String, dynamic> toJson() => {
        'start': startTime,
        'late': lateToleranceMin,
        'absence': absenceTime,
        'autoSms': autoSms,
        'noAccents': smsWithoutAccents,
        'template': smsTemplate,
        'cc': countryCode,
        'days': schoolDays.toList()..sort(),
        'double': doubleScanSeconds,
        'mode': mode.name,
        'company': company,
        'end': endTime,
        'break': breakMin,
        'companySms': companySms,
      };

  factory AttendanceSettings.fromJson(Map<String, dynamic> j) => AttendanceSettings(
        startTime: j['start'] ?? '07:30',
        lateToleranceMin: j['late'] ?? 10,
        absenceTime: j['absence'] ?? '09:00',
        autoSms: j['autoSms'] ?? true,
        smsWithoutAccents: j['noAccents'] ?? false,
        smsTemplate: (j['template'] as String?)?.trim().isNotEmpty == true ? j['template'] : defaultTemplate,
        countryCode: j['cc'] ?? '226',
        schoolDays: (j['days'] as List?)?.map((e) => e as int).toSet(),
        doubleScanSeconds: j['double'] ?? 60,
        mode: ScanMode.values.firstWhere((m) => m.name == j['mode'], orElse: () => ScanMode.auto),
        company: j['company'] as bool?,
        endTime: j['end'] ?? '17:00',
        breakMin: j['break'] ?? 60,
        companySms: j['companySms'] ?? false,
      );

  static (int, int) parseTime(String s) {
    final m = RegExp(r'^(\d{1,2})[:hH](\d{2})$').firstMatch(s.trim());
    if (m == null) return (8, 0);
    return (int.parse(m[1]!).clamp(0, 23), int.parse(m[2]!).clamp(0, 59));
  }

  DateTime at(DateTime day, String hhmm) {
    final (h, m) = parseTime(hhmm);
    return DateTime(day.year, day.month, day.day, h, m);
  }

  DateTime lateLimit(DateTime day) => at(day, startTime).add(Duration(minutes: lateToleranceMin));
  DateTime absenceLimit(DateTime day) => at(day, absenceTime);
  DateTime endOf(DateTime day) => at(day, endTime);

  /// Durée de travail prévue par jour, en minutes.
  int get expectedMinutes {
    final (h1, m1) = parseTime(startTime);
    final (h2, m2) = parseTime(endTime);
    return math.max(0, (h2 * 60 + m2) - (h1 * 60 + m1) - breakMin);
  }
}

/// Statut d'un élève pour une journée.
enum DayStatus { present, late, absent, excused, notYet }

const dayStatusLabel = {
  DayStatus.present: 'Présent',
  DayStatus.late: 'En retard',
  DayStatus.absent: 'Absent',
  DayStatus.excused: 'Absence justifiée',
  DayStatus.notYet: 'Pas encore arrivé',
};

/// Synthèse calculée pour un élève et un jour.
class StudentDay {
  final Student student;
  final DayStatus status;
  final DateTime? arrival;
  final DateTime? departure;

  /// Dernier passage = sortie : l'élève a quitté l'établissement.
  final bool isOut;
  final int scans;
  final String? sms;

  /// Entreprise : minutes travaillées, minutes de retard, départ avant l'heure, sortie non pointée.
  final int workedMin;
  final int lateMin;
  final int earlyMin;
  final bool missingExit;

  StudentDay(this.student, this.status,
      {this.arrival,
      this.departure,
      this.isOut = false,
      this.scans = 0,
      this.sms,
      this.workedMin = 0,
      this.lateMin = 0,
      this.earlyMin = 0,
      this.missingExit = false});
}

/// « 7 h 45 » à partir d'un nombre de minutes.
String hoursLabel(int minutes) {
  final neg = minutes < 0;
  final m = minutes.abs();
  final r = '${m ~/ 60} h ${(m % 60).toString().padLeft(2, '0')}';
  return neg ? '-$r' : r;
}

String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime parseDateKey(String k) {
  final p = k.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

String hhmm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

String frDate(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

const frWeekdays = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];

/// Calcule le statut d'un élève pour une journée.
StudentDay computeDay(Student s, DayRecord? day, AttendanceSettings st, DateTime date, {DateTime? now}) {
  now ??= DateTime.now();
  final events = (day?.eventsOf(s.id) ?? [])..sort((a, b) => a.time.compareTo(b.time));
  final entries = events.where((e) => e.entry).toList();
  final exits = events.where((e) => !e.entry).toList();
  final arrival = entries.isEmpty ? null : entries.first.time;
  final departure = exits.isEmpty ? null : exits.last.time;
  final isOut = events.isNotEmpty && !events.last.entry;
  final ov = day?.overrides[s.id];
  DayStatus status;
  if (ov == DayOverride.excused) {
    status = DayStatus.excused;
  } else if (ov == DayOverride.absent) {
    status = DayStatus.absent;
  } else if (ov == DayOverride.present) {
    status = DayStatus.present;
  } else if (arrival != null) {
    status = arrival.isAfter(st.lateLimit(date)) ? DayStatus.late : DayStatus.present;
  } else {
    final dayEnd = DateTime(date.year, date.month, date.day, 23, 59);
    final pastLimit = now.isAfter(st.absenceLimit(date)) || now.isAfter(dayEnd);
    status = pastLimit ? DayStatus.absent : DayStatus.notYet;
  }
  // Temps de présence : chaque entrée jusqu'à la sortie suivante.
  var worked = 0;
  var intervals = 0;
  var missingExit = false;
  final today = DateTime(now.year, now.month, now.day) == DateTime(date.year, date.month, date.day);
  DateTime? open;
  for (final e in events) {
    if (e.entry) {
      open ??= e.time;
    } else if (open != null) {
      worked += e.time.difference(open).inMinutes;
      intervals++;
      open = null;
    }
  }
  if (open != null) {
    // Toujours à l'intérieur : jusqu'à maintenant aujourd'hui, sinon jusqu'à l'heure de fin (sortie oubliée).
    final until = today ? now : st.endOf(date);
    if (until.isAfter(open)) worked += until.difference(open).inMinutes;
    intervals++;
    if (!today) missingExit = true;
  }
  // Pas de pointage à midi : on retire la pause d'une journée complète.
  if (intervals == 1 && worked > 6 * 60) worked = math.max(0, worked - st.breakMin);
  final lateMin = status == DayStatus.late && arrival != null
      ? math.max(0, arrival.difference(st.at(date, st.startTime)).inMinutes)
      : 0;
  final earlyMin = isOut && departure != null && departure.isBefore(st.endOf(date))
      ? st.endOf(date).difference(departure).inMinutes
      : 0;
  return StudentDay(s, status,
      arrival: arrival,
      departure: departure,
      isOut: isOut,
      scans: events.length,
      sms: day?.sms[s.id],
      workedMin: worked,
      lateMin: lateMin,
      earlyMin: earlyMin,
      missingExit: missingExit);
}

/// Remplace les variables du modèle de SMS.
String buildSms(String template, Student s, SchoolInfo school, DateTime date, {bool withoutAccents = false}) {
  final ecole = school.shortName.trim().isNotEmpty ? school.shortName.trim() : school.name.trim();
  var t = template
      .replaceAll('{prenom}', s.prenom.trim())
      .replaceAll('{nom}', s.nom.trim().toUpperCase())
      .replaceAll('{classe}', s.classe.trim())
      .replaceAll('{matricule}', s.matricule.trim())
      .replaceAll('{ecole}', ecole)
      .replaceAll('{date}', '${frWeekdays[date.weekday - 1]} ${frDate(date)}')
      .replaceAll(RegExp(r'\(\s*\)'), '')
      .replaceAll(RegExp(r' {2,}'), ' ')
      .trim();
  if (withoutAccents) t = removeAccents(t);
  return t;
}

String removeAccents(String s) {
  const from = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿÀÂÄÁÃÅÇÉÈÊËÍÌÎÏÑÓÒÔÖÕÚÙÛÜÝœŒæÆ’«»';
  const to = 'aaaaaaceeeeiiiinooooouuuuyyAAAAAACEEEEIIIINOOOOOUUUUYoOaA\'""';
  final b = StringBuffer();
  for (final r in s.runes) {
    final ch = String.fromCharCode(r);
    final i = from.indexOf(ch);
    if (i < 0) {
      b.write(ch);
    } else if (ch == 'œ') {
      b.write('oe');
    } else if (ch == 'Œ') {
      b.write('OE');
    } else if (ch == 'æ') {
      b.write('ae');
    } else if (ch == 'Æ') {
      b.write('AE');
    } else {
      b.write(to[i]);
    }
  }
  return b.toString();
}

/// Nombre de SMS facturés pour un texte (70 caractères par SMS avec accents, 160 sans).
int smsSegments(String text) {
  const gsm =
      '@£\$¥èéùìòÇ\nØø\rÅåΔ_ΦΓΛΩΠΨΣΘΞÆæßÉ !"#¤%&\'()*+,-./0123456789:;<=>?¡ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÑÜ§¿abcdefghijklmnopqrstuvwxyzäöñüà';
  final unicode = text.runes.any((r) => !gsm.contains(String.fromCharCode(r)));
  final n = text.length;
  if (unicode) return n <= 70 ? 1 : (n / 67).ceil();
  return n <= 160 ? 1 : (n / 153).ceil();
}

/// Met un numéro au format international (+226…).
String? normalizePhone(String raw, String countryCode) {
  var d = raw.replaceAll(RegExp(r'[^\d+]'), '');
  if (d.isEmpty) return null;
  if (d.startsWith('00')) d = '+${d.substring(2)}';
  if (d.startsWith('+')) return d.length >= 9 ? d : null;
  final cc = countryCode.replaceAll(RegExp(r'\D'), '');
  if (d.startsWith(cc) && d.length > cc.length + 6) return '+$d';
  if (d.length >= 8 && d.length <= 10) return '+$cc$d';
  return null;
}

/// Retrouve l'élève à partir du contenu du QR code ou du code-barres lu.
Student? findStudentByCode(String raw, List<Student> students) {
  final code = raw.trim();
  if (code.isEmpty) return null;
  if (code.startsWith('CS:')) {
    final id = code.substring(3);
    for (final s in students) {
      if (s.id == id) return s;
    }
  }
  final lc = code.toLowerCase();
  for (final s in students) {
    if (s.matricule.trim().isNotEmpty && s.matricule.trim().toLowerCase() == lc) return s;
  }
  for (final s in students) {
    if (s.id == code) return s;
    final legacy = [s.fullName, s.classe].where((e) => e.isNotEmpty).join(' | ');
    if (legacy.toLowerCase() == lc) return s;
  }
  return null;
}
