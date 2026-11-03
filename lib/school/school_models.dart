import '../models.dart';

/// Gestion scolaire : classes, matières, périodes, notes, absences et appréciations.
/// Tout est enregistré dans le dossier du projet (gestion.json), sur l'appareil.

String _id(String p) => '$p${Student.newId()}';

double _d(dynamic v, double def) => v is num ? v.toDouble() : (double.tryParse('$v') ?? def);

/// Une matière enseignée dans une classe.
class Subject {
  String id;
  String name;
  double coef;
  String teacher;

  /// Note sur… (vide = barème de la classe). Ex. au primaire : Calcul sur 10, Dictée sur 10.
  double? max;

  /// Matière « Conduite » : reçoit la retenue pour absences.
  bool conduct;

  /// Professeur attribué (voir [GradeBook.teachers]) ; [teacher] garde son nom pour les bulletins.
  String? teacherId;

  /// Nombre de séances (heures) par semaine, pour l'emploi du temps.
  int hours;

  Subject({
    String? id,
    required this.name,
    this.coef = 1,
    this.teacher = '',
    this.max,
    this.conduct = false,
    this.teacherId,
    this.hours = 0,
  }) : id = id ?? _id('m');

  Subject copy({bool newId = false}) => Subject(
      id: newId ? null : id,
      name: name,
      coef: coef,
      teacher: teacher,
      max: max,
      conduct: conduct,
      teacherId: teacherId,
      hours: hours);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'coef': coef,
        'teacher': teacher,
        'max': max,
        'conduct': conduct,
        'teacherId': teacherId,
        'hours': hours,
      };

  factory Subject.fromJson(Map<String, dynamic> j) => Subject(
        teacherId: j['teacherId'],
        hours: (j['hours'] as num?)?.toInt() ?? 0,
        id: j['id'],
        name: j['name'] ?? '',
        coef: _d(j['coef'], 1),
        teacher: j['teacher'] ?? '',
        max: j['max'] == null ? null : _d(j['max'], 20),
        conduct: j['conduct'] ?? false,
      );
}

/// Réglages d'une classe (le nom est celui saisi dans la fiche de l'élève).
class ClassConfig {
  String name;
  List<Subject> subjects;

  /// Barème de la classe : 10 au primaire, 20 au post-primaire et au lycée.
  double scale;

  /// Professeur principal / maître de la classe.
  String titulaire;

  ClassConfig({required this.name, List<Subject>? subjects, this.scale = 20, this.titulaire = ''})
      : subjects = subjects ?? [];

  double maxOf(Subject s) => s.max ?? scale;
  double get coefTotal => subjects.fold(0.0, (a, s) => a + s.coef);

  Map<String, dynamic> toJson() => {
        'name': name,
        'scale': scale,
        'titulaire': titulaire,
        'subjects': subjects.map((e) => e.toJson()).toList(),
      };

  factory ClassConfig.fromJson(Map<String, dynamic> j) => ClassConfig(
        name: j['name'] ?? '',
        scale: _d(j['scale'], 20),
        titulaire: j['titulaire'] ?? '',
        subjects: (j['subjects'] as List? ?? []).map((e) => Subject.fromJson(Map<String, dynamic>.from(e))).toList(),
      );
}

/// Trimestre ou semestre. Les dates servent à compter les absences du pointage.
class Period {
  String id;
  String name;
  DateTime? start;
  DateTime? end;

  /// Poids dans la moyenne annuelle.
  double weight;

  Period({String? id, required this.name, this.start, this.end, this.weight = 1}) : id = id ?? _id('p');

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'start': start?.toIso8601String(),
        'end': end?.toIso8601String(),
        'weight': weight,
      };

  factory Period.fromJson(Map<String, dynamic> j) => Period(
        id: j['id'],
        name: j['name'] ?? '',
        start: DateTime.tryParse(j['start'] ?? ''),
        end: DateTime.tryParse(j['end'] ?? ''),
        weight: _d(j['weight'], 1),
      );
}

/// Type d'évaluation dans une période (devoir, interrogation, composition) et son poids.
class EvalType {
  String id;
  String name;
  double weight;

  EvalType({String? id, required this.name, this.weight = 1}) : id = id ?? _id('e');

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'weight': weight};

  factory EvalType.fromJson(Map<String, dynamic> j) =>
      EvalType(id: j['id'], name: j['name'] ?? '', weight: _d(j['weight'], 1));
}

/// Distinction ou sanction selon la moyenne générale (ramenée sur 20).
class MentionRule {
  double min;
  double max;
  String label;
  bool positive;

  MentionRule(this.min, this.max, this.label, {this.positive = true});

  Map<String, dynamic> toJson() => {'min': min, 'max': max, 'label': label, 'positive': positive};

  factory MentionRule.fromJson(Map<String, dynamic> j) =>
      MentionRule(_d(j['min'], 0), _d(j['max'], 20), j['label'] ?? '', positive: j['positive'] ?? true);
}

/// Absences d'un élève sur une période (en jours ou demi-journées selon l'établissement).
class AbsenceCount {
  int justified;
  int unjustified;
  int lates;

  AbsenceCount({this.justified = 0, this.unjustified = 0, this.lates = 0});

  int get total => justified + unjustified;
  bool get isEmpty => justified == 0 && unjustified == 0 && lates == 0;

  AbsenceCount operator +(AbsenceCount o) => AbsenceCount(
      justified: justified + o.justified, unjustified: unjustified + o.unjustified, lates: lates + o.lates);

  Map<String, dynamic> toJson() => {'j': justified, 'u': unjustified, 'l': lates};

  factory AbsenceCount.fromJson(Map<String, dynamic> j) =>
      AbsenceCount(justified: j['j'] ?? 0, unjustified: j['u'] ?? 0, lates: j['l'] ?? 0);
}

/// Réglages de la gestion scolaire.
class SchoolSettings {
  List<Period> periods;
  List<EvalType> evals;

  /// Retenue sur la note de conduite par absence non justifiée (en points sur 20).
  double conductPenalty;

  /// Retenue sur la moyenne générale par absence non justifiée (en points sur 20).
  double averagePenalty;

  /// Nombre de retards qui valent une absence non justifiée (0 = les retards ne comptent pas).
  int latesPerAbsence;

  /// Compter les absences du pointage automatiquement (selon les dates des périodes).
  bool useAttendance;

  /// Modèle de bulletin choisi pour l'impression.
  String bulletinModel;

  /// Récapitulatif annuel (moyennes des périodes) sur le bulletin de la dernière période.
  bool annualRecap;

  /// Classement : afficher le rang par matière.
  bool rankPerSubject;

  /// Unité des absences affichée sur le bulletin.
  String absenceUnit;

  List<MentionRule> mentions;

  /// Moyenne d'admission (sur 20) pour la décision de fin d'année.
  double passMark;

  /// Couleur principale des bulletins.
  int bulletinColor;

  SchoolSettings({
    List<Period>? periods,
    List<EvalType>? evals,
    this.conductPenalty = 0.5,
    this.averagePenalty = 0,
    this.latesPerAbsence = 3,
    this.useAttendance = true,
    this.bulletinModel = 'officiel',
    this.annualRecap = true,
    this.rankPerSubject = true,
    this.absenceUnit = 'jour(s)',
    List<MentionRule>? mentions,
    this.passMark = 10,
    this.bulletinColor = 0xFF1B4F8C,
  })  : periods = periods ?? defaultPeriods(),
        evals = evals ?? defaultEvals(),
        mentions = mentions ?? defaultMentions();

  static List<Period> defaultPeriods() {
    final now = DateTime.now();
    final y = now.month >= 8 ? now.year : now.year - 1;
    return [
      Period(name: '1er trimestre', start: DateTime(y, 10, 1), end: DateTime(y, 12, 31)),
      Period(name: '2e trimestre', start: DateTime(y + 1, 1, 1), end: DateTime(y + 1, 3, 31)),
      Period(name: '3e trimestre', start: DateTime(y + 1, 4, 1), end: DateTime(y + 1, 6, 30)),
    ];
  }

  static List<EvalType> defaultEvals() => [
        EvalType(name: 'Devoir 1'),
        EvalType(name: 'Devoir 2'),
        EvalType(name: 'Composition', weight: 2),
      ];

  static List<MentionRule> defaultMentions() => [
        MentionRule(16, 21, 'Félicitations'),
        MentionRule(14, 16, 'Encouragements'),
        MentionRule(12, 14, 'Tableau d\'honneur'),
        MentionRule(7, 9, 'Avertissement (travail)', positive: false),
        MentionRule(0, 7, 'Blâme (travail)', positive: false),
      ];

  Period? period(String id) {
    for (final p in periods) {
      if (p.id == id) return p;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'periods': periods.map((e) => e.toJson()).toList(),
        'evals': evals.map((e) => e.toJson()).toList(),
        'conductPenalty': conductPenalty,
        'averagePenalty': averagePenalty,
        'latesPerAbsence': latesPerAbsence,
        'useAttendance': useAttendance,
        'bulletinModel': bulletinModel,
        'annualRecap': annualRecap,
        'rankPerSubject': rankPerSubject,
        'absenceUnit': absenceUnit,
        'mentions': mentions.map((e) => e.toJson()).toList(),
        'passMark': passMark,
        'bulletinColor': bulletinColor,
      };

  factory SchoolSettings.fromJson(Map<String, dynamic> j) => SchoolSettings(
        periods: (j['periods'] as List?)?.map((e) => Period.fromJson(Map<String, dynamic>.from(e))).toList(),
        evals: (j['evals'] as List?)?.map((e) => EvalType.fromJson(Map<String, dynamic>.from(e))).toList(),
        conductPenalty: _d(j['conductPenalty'], 0.5),
        averagePenalty: _d(j['averagePenalty'], 0),
        latesPerAbsence: j['latesPerAbsence'] ?? 3,
        useAttendance: j['useAttendance'] ?? true,
        bulletinModel: j['bulletinModel'] ?? 'officiel',
        annualRecap: j['annualRecap'] ?? true,
        rankPerSubject: j['rankPerSubject'] ?? true,
        absenceUnit: j['absenceUnit'] ?? 'jour(s)',
        mentions: (j['mentions'] as List?)?.map((e) => MentionRule.fromJson(Map<String, dynamic>.from(e))).toList(),
        passMark: _d(j['passMark'], 10),
        bulletinColor: j['bulletinColor'] ?? 0xFF1B4F8C,
      );
}

/// Carnet de notes du projet : notes, absences saisies, appréciations et décisions.
class GradeBook {
  SchoolSettings settings;
  Map<String, ClassConfig> classes;

  /// notes[période][élève][matière][évaluation] = note (sur le barème de la matière).
  Map<String, Map<String, Map<String, Map<String, double>>>> notes;

  /// Absences saisies à la main, ajoutées à celles du pointage : absences[période][élève].
  Map<String, Map<String, AbsenceCount>> absences;

  /// Appréciation du conseil de classe : council[période][élève].
  Map<String, Map<String, String>> council;

  /// Décision de fin d'année : decisions[élève] (« Admis(e) en classe supérieure »…).
  Map<String, String> decisions;

  /// Professeurs de l'établissement.
  List<Teacher> teachers;

  /// Jours et créneaux de cours.
  TimetableSettings tt;

  /// Emploi du temps : timetable[classe]['jour|créneau'] = séance.
  Map<String, Map<String, Lesson>> timetable;

  GradeBook({
    List<Teacher>? teachers,
    TimetableSettings? tt,
    Map<String, Map<String, Lesson>>? timetable,
    SchoolSettings? settings,
    Map<String, ClassConfig>? classes,
    Map<String, Map<String, Map<String, Map<String, double>>>>? notes,
    Map<String, Map<String, AbsenceCount>>? absences,
    Map<String, Map<String, String>>? council,
    Map<String, String>? decisions,
  })  : settings = settings ?? SchoolSettings(),
        classes = classes ?? {},
        notes = notes ?? {},
        absences = absences ?? {},
        council = council ?? {},
        decisions = decisions ?? {},
        teachers = teachers ?? [],
        tt = tt ?? TimetableSettings(),
        timetable = timetable ?? {};

  Teacher? teacher(String? id) {
    if (id == null) return null;
    for (final t in teachers) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// Nom du professeur d'une matière (fiche professeur, sinon nom saisi).
  String teacherName(Subject s) => teacher(s.teacherId)?.name ?? s.teacher;

  /// Attribue un professeur à une matière (ou retire l'attribution).
  void assign(Subject s, Teacher? t) {
    s.teacherId = t?.id;
    s.teacher = t?.name ?? '';
  }

  /// Renomme une classe partout (réglages, emploi du temps).
  void renameClass(String from, String to) {
    final c = classes.remove(from);
    if (c != null) classes[to] = c..name = to;
    final t = timetable.remove(from);
    if (t != null) timetable[to] = t;
  }

  /// Séances par semaine attribuées à un professeur, toutes classes confondues.
  int teacherHours(String teacherId) {
    var h = 0;
    for (final c in classes.values) {
      for (final s in c.subjects) {
        if (s.teacherId == teacherId) h += s.hours;
      }
    }
    return h;
  }

  ClassConfig classOf(String name) => classes.putIfAbsent(name, () => ClassConfig(name: name, scale: guessScale(name)));

  double? note(String period, String student, String subject, String eval) => notes[period]?[student]?[subject]?[eval];

  void setNote(String period, String student, String subject, String eval, double? v) {
    if (v == null) {
      notes[period]?[student]?[subject]?.remove(eval);
      return;
    }
    notes.putIfAbsent(period, () => {}).putIfAbsent(student, () => {}).putIfAbsent(subject, () => {})[eval] = v;
  }

  AbsenceCount manualAbsences(String period, String student) =>
      absences[period]?[student] ?? AbsenceCount();

  void setManualAbsences(String period, String student, AbsenceCount a) {
    if (a.isEmpty) {
      absences[period]?.remove(student);
    } else {
      absences.putIfAbsent(period, () => {})[student] = a;
    }
  }

  Map<String, dynamic> toJson() => {
        'version': 1,
        'settings': settings.toJson(),
        'classes': classes.map((k, v) => MapEntry(k, v.toJson())),
        'notes': notes,
        'absences': absences.map((p, m) => MapEntry(p, m.map((s, a) => MapEntry(s, a.toJson())))),
        'council': council,
        'decisions': decisions,
        'teachers': teachers.map((e) => e.toJson()).toList(),
        'tt': tt.toJson(),
        'timetable': timetable.map((c, m) => MapEntry(c, m.map((k, l) => MapEntry(k, l.toJson())))),
      };

  factory GradeBook.fromJson(Map<String, dynamic> j) {
    Map<String, Map<String, Map<String, Map<String, double>>>> notes = {};
    (j['notes'] as Map? ?? {}).forEach((p, st) {
      (st as Map).forEach((s, subj) {
        (subj as Map).forEach((m, ev) {
          (ev as Map).forEach((e, v) {
            if (v is num) {
              notes
                  .putIfAbsent('$p', () => {})
                  .putIfAbsent('$s', () => {})
                  .putIfAbsent('$m', () => {})['$e'] = v.toDouble();
            }
          });
        });
      });
    });
    return GradeBook(
      settings: j['settings'] == null ? null : SchoolSettings.fromJson(Map<String, dynamic>.from(j['settings'])),
      classes: (j['classes'] as Map? ?? {})
          .map((k, v) => MapEntry('$k', ClassConfig.fromJson(Map<String, dynamic>.from(v as Map)))),
      notes: notes,
      absences: (j['absences'] as Map? ?? {}).map((p, m) => MapEntry(
          '$p',
          (m as Map).map((s, a) => MapEntry('$s', AbsenceCount.fromJson(Map<String, dynamic>.from(a as Map)))))),
      council: (j['council'] as Map? ?? {})
          .map((p, m) => MapEntry('$p', (m as Map).map((s, t) => MapEntry('$s', '$t')))),
      decisions: (j['decisions'] as Map? ?? {}).map((k, v) => MapEntry('$k', '$v')),
      teachers: (j['teachers'] as List? ?? []).map((e) => Teacher.fromJson(Map<String, dynamic>.from(e))).toList(),
      tt: j['tt'] == null ? null : TimetableSettings.fromJson(Map<String, dynamic>.from(j['tt'])),
      timetable: (j['timetable'] as Map? ?? {}).map((c, m) => MapEntry(
          '$c', (m as Map).map((k, l) => MapEntry('$k', Lesson.fromJson(Map<String, dynamic>.from(l as Map)))))),
    );
  }
}

/// Barème probable d'après le nom de la classe : primaire (CP, CE, CM) sur 10, sinon sur 20.
double guessScale(String className) {
  final c = className.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  return RegExp(r'^(CP|CE|CM|CI|SIL|MATERNELLE|PS|MS|GS)').hasMatch(c) ? 10 : 20;
}

/// Jeux de matières prêts à l'emploi (programmes du Burkina Faso, modifiables).
class SubjectPreset {
  final String name;
  final double scale;
  final List<(String, double)> subjects;
  const SubjectPreset(this.name, this.scale, this.subjects);

  List<Subject> build() => [
        for (final (n, c) in subjects)
          Subject(name: n, coef: c, conduct: n == 'Conduite', hours: defaultHours(n, c, scale)),
      ];
}

/// Volume horaire hebdomadaire indicatif d'une matière (modifiable).
int defaultHours(String name, double coef, double scale) {
  if (name == 'Conduite') return 0;
  final n = name.toLowerCase();
  if (scale == 10) {
    if (n.contains('calcul') || n.contains('dictée') || n.contains('lecture')) return 5;
    if (n.contains('problèmes') || n.contains('rédaction') || n.contains('langage')) return 3;
    return 2;
  }
  if (n.startsWith('français') || n.startsWith('mathématiques')) return coef >= 4 ? 6 : 5;
  if (n.contains('physique')) return coef >= 4 ? 5 : 3;
  if (n.contains('philosophie')) return coef >= 3 ? 4 : 2;
  if (n.contains('eps')) return 2;
  if (n.contains('civique')) return 1;
  return coef >= 3 ? 4 : (coef >= 2 ? 3 : 2);
}

const subjectPresets = <SubjectPreset>[
  SubjectPreset('Primaire (CP – CE)', 10, [
    ('Lecture', 1),
    ('Écriture', 1),
    ('Calcul', 1),
    ('Dictée', 1),
    ('Langage / Expression orale', 1),
    ('Éducation civique et morale', 1),
    ('Observation / Sciences', 1),
    ('Dessin', 1),
    ('Chant / Récitation', 1),
    ('EPS', 1),
  ]),
  SubjectPreset('Primaire (CM)', 10, [
    ('Calcul', 1),
    ('Problèmes', 1),
    ('Dictée / Questions', 1),
    ('Rédaction', 1),
    ('Lecture', 1),
    ('Histoire', 1),
    ('Géographie', 1),
    ('Sciences d\'observation', 1),
    ('Éducation civique et morale', 1),
    ('Écriture', 1),
    ('EPS', 1),
  ]),
  SubjectPreset('Post-primaire (6e – 3e)', 20, [
    ('Français', 3),
    ('Mathématiques', 3),
    ('Anglais', 2),
    ('Histoire-Géographie', 2),
    ('Sciences de la vie et de la terre', 2),
    ('Physique-Chimie', 2),
    ('Allemand / Espagnol', 1),
    ('Éducation civique', 1),
    ('EPS', 1),
    ('Conduite', 1),
  ]),
  SubjectPreset('Lycée série A', 20, [
    ('Français', 4),
    ('Philosophie', 3),
    ('Histoire-Géographie', 3),
    ('Anglais', 3),
    ('Mathématiques', 2),
    ('Allemand / Espagnol', 2),
    ('Sciences de la vie et de la terre', 1),
    ('EPS', 1),
    ('Conduite', 1),
  ]),
  SubjectPreset('Lycée série C', 20, [
    ('Mathématiques', 5),
    ('Physique-Chimie', 5),
    ('Sciences de la vie et de la terre', 2),
    ('Français', 2),
    ('Philosophie', 2),
    ('Anglais', 2),
    ('Histoire-Géographie', 2),
    ('EPS', 1),
    ('Conduite', 1),
  ]),
  SubjectPreset('Lycée série D', 20, [
    ('Mathématiques', 4),
    ('Sciences de la vie et de la terre', 4),
    ('Physique-Chimie', 4),
    ('Français', 2),
    ('Philosophie', 2),
    ('Anglais', 2),
    ('Histoire-Géographie', 2),
    ('EPS', 1),
    ('Conduite', 1),
  ]),
];


// ---------------------------------------------------------------------------
// Professeurs et emploi du temps.

/// Un professeur (ou un maître au primaire).
class Teacher {
  String id;
  String name;
  String phone;
  String email;

  /// Matières enseignées (texte libre : « Maths, PC »).
  String subjects;

  /// Séances maximum par semaine (0 = sans limite).
  int maxHours;

  /// Créneaux où le professeur n'est pas disponible : « jour|créneau ».
  Set<String> unavailable;

  Teacher({
    String? id,
    required this.name,
    this.phone = '',
    this.email = '',
    this.subjects = '',
    this.maxHours = 0,
    Set<String>? unavailable,
  })  : id = id ?? _id('t'),
        unavailable = unavailable ?? {};

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        'email': email,
        'subjects': subjects,
        'maxHours': maxHours,
        'unavailable': unavailable.toList(),
      };

  factory Teacher.fromJson(Map<String, dynamic> j) => Teacher(
        id: j['id'],
        name: j['name'] ?? '',
        phone: j['phone'] ?? '',
        email: j['email'] ?? '',
        subjects: j['subjects'] ?? '',
        maxHours: (j['maxHours'] as num?)?.toInt() ?? 0,
        unavailable: {...(j['unavailable'] as List? ?? []).map((e) => '$e')},
      );
}

/// Créneau horaire d'une journée (« 07:00 – 08:00 ») ou pause.
class TimeSlot {
  String start;
  String end;
  bool isBreak;
  String label;

  TimeSlot(this.start, this.end, {this.isBreak = false, this.label = ''});

  String get text => '$start – $end';

  Map<String, dynamic> toJson() => {'start': start, 'end': end, 'break': isBreak, 'label': label};

  factory TimeSlot.fromJson(Map<String, dynamic> j) =>
      TimeSlot(j['start'] ?? '', j['end'] ?? '', isBreak: j['break'] ?? false, label: j['label'] ?? '');
}

const weekDays = ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi'];

/// Jours de cours, créneaux et créneaux fermés à toutes les classes.
class TimetableSettings {
  /// Jours de cours : 1 = lundi … 6 = samedi.
  List<int> days;
  List<TimeSlot> slots;

  /// Créneaux sans cours pour tout l'établissement (ex. mercredi après-midi) : « jour|créneau ».
  Set<String> closed;

  TimetableSettings({List<int>? days, List<TimeSlot>? slots, Set<String>? closed})
      : days = days ?? [1, 2, 3, 4, 5],
        slots = slots ?? defaultSlots(),
        closed = closed ?? {'3|6', '3|7'};

  static List<TimeSlot> defaultSlots() => [
        TimeSlot('07:00', '08:00'),
        TimeSlot('08:00', '09:00'),
        TimeSlot('09:00', '10:00'),
        TimeSlot('10:00', '10:15', isBreak: true, label: 'Récréation'),
        TimeSlot('10:15', '11:15'),
        TimeSlot('11:15', '12:15'),
        TimeSlot('15:00', '16:00'),
        TimeSlot('16:00', '17:00'),
      ];

  /// Créneaux de cours utilisables (hors pauses et créneaux fermés).
  List<String> usable() => [
        for (final d in days)
          for (var i = 0; i < slots.length; i++)
            if (!slots[i].isBreak && !closed.contains('$d|$i')) '$d|$i',
      ];

  Map<String, dynamic> toJson() => {
        'days': days,
        'slots': slots.map((e) => e.toJson()).toList(),
        'closed': closed.toList(),
      };

  factory TimetableSettings.fromJson(Map<String, dynamic> j) => TimetableSettings(
        days: (j['days'] as List?)?.map((e) => (e as num).toInt()).toList(),
        slots: (j['slots'] as List?)?.map((e) => TimeSlot.fromJson(Map<String, dynamic>.from(e))).toList(),
        closed: (j['closed'] as List?)?.map((e) => '$e').toSet(),
      );
}

/// Une séance de l'emploi du temps. [locked] : placée à la main, gardée à la régénération.
class Lesson {
  String subjectId;
  bool locked;
  String room;

  Lesson(this.subjectId, {this.locked = false, this.room = ''});

  Map<String, dynamic> toJson() => {'s': subjectId, if (locked) 'l': true, if (room.isNotEmpty) 'r': room};

  factory Lesson.fromJson(Map<String, dynamic> j) => Lesson(j['s'] ?? '', locked: j['l'] ?? false, room: j['r'] ?? '');
}
