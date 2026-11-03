import '../models.dart';
import 'school_models.dart';

/// Résultat d'un élève dans une matière pour une période.
class SubjectResult {
  final Subject subject;

  /// Notes de chaque évaluation (sur le barème de la matière).
  final Map<String, double?> evals;

  /// Moyenne de la matière sur son barème, après retenue (conduite).
  final double? average;

  /// Moyenne ramenée au barème de la classe.
  final double? onScale;

  /// Points retirés à la conduite pour absences (sur le barème de la matière).
  final double penalty;
  int? rank;
  bool exAequo = false;
  double? classAverage;

  SubjectResult(this.subject, this.evals, this.average, this.onScale, {this.penalty = 0});

  double? weighted() => onScale == null ? null : onScale! * subject.coef;
}

/// Résultat d'un élève pour une période.
class StudentResult {
  final Student student;
  final List<SubjectResult> subjects;
  final AbsenceCount absences;

  /// Moyenne générale sur le barème de la classe, après retenue éventuelle.
  final double? average;
  final double totalPoints;
  final double coefSum;

  /// Points retirés à la moyenne générale pour absences.
  final double averagePenalty;
  int? rank;
  bool exAequo = false;
  String? mention;
  bool mentionPositive = true;
  String council = '';

  StudentResult(this.student, this.subjects, this.absences, this.average, this.totalPoints, this.coefSum,
      {this.averagePenalty = 0});
}

/// Résultats d'une classe pour une période.
class ClassResults {
  final ClassConfig cls;
  final Period period;
  final List<StudentResult> rows;
  final double? classAverage;
  final double? best;
  final double? worst;

  ClassResults(this.cls, this.period, this.rows, this.classAverage, this.best, this.worst);

  int get effectif => rows.length;
  int get ranked => rows.where((r) => r.average != null).length;
  int get passing => rows.where((r) => r.average != null && r.average! >= cls.scale / 2).length;

  StudentResult? of(String studentId) {
    for (final r in rows) {
      if (r.student.id == studentId) return r;
    }
    return null;
  }
}

/// Unités d'absence qui donnent lieu à retenue : absences non justifiées + retards convertis.
int penaltyUnits(AbsenceCount a, SchoolSettings st) =>
    a.unjustified + (st.latesPerAbsence > 0 ? a.lates ~/ st.latesPerAbsence : 0);

/// Moyenne pondérée des évaluations disponibles (null si aucune note).
double? weightedMean(Map<String, double?> notes, List<EvalType> evals) {
  var sum = 0.0, w = 0.0;
  for (final e in evals) {
    final v = notes[e.id];
    if (v == null || e.weight <= 0) continue;
    sum += v * e.weight;
    w += e.weight;
  }
  return w == 0 ? null : sum / w;
}

double round2(double v) => (v * 100).roundToDouble() / 100;

/// Calcule les résultats d'une classe pour une période.
/// [students] : élèves de la classe ; [auto] : absences du pointage par élève.
ClassResults computeClass(GradeBook gb, ClassConfig cls, List<Student> students, Period p,
    {Map<String, AbsenceCount> auto = const {}}) {
  final st = gb.settings;
  final rows = <StudentResult>[];
  for (final s in students) {
    final abs = (auto[s.id] ?? AbsenceCount()) + gb.manualAbsences(p.id, s.id);
    final units = penaltyUnits(abs, st);
    final subj = <SubjectResult>[];
    var total = 0.0, coefs = 0.0;
    for (final m in cls.subjects) {
      final notes = {for (final e in st.evals) e.id: gb.note(p.id, s.id, m.id, e.id)};
      final max = cls.maxOf(m);
      var avg = weightedMean(notes, st.evals);
      var pen = 0.0;
      if (m.conduct && (avg != null || units > 0)) {
        final base = avg ?? max;
        pen = (units * st.conductPenalty * max / 20).clamp(0, base).toDouble();
        avg = base - pen;
      }
      final onScale = avg == null || max <= 0 ? null : avg * cls.scale / max;
      final r = SubjectResult(m, notes, avg, onScale, penalty: pen);
      subj.add(r);
      if (onScale != null && m.coef > 0) {
        total += onScale * m.coef;
        coefs += m.coef;
      }
    }
    double? avg = coefs == 0 ? null : total / coefs;
    var avgPen = 0.0;
    if (avg != null && st.averagePenalty > 0 && units > 0) {
      avgPen = (units * st.averagePenalty * cls.scale / 20).clamp(0, avg).toDouble();
      avg -= avgPen;
    }
    final row = StudentResult(s, subj, abs, avg, total, coefs, averagePenalty: avgPen)
      ..council = gb.council[p.id]?[s.id] ?? '';
    if (avg != null) {
      final m = mentionFor(avg * 20 / cls.scale, st.mentions);
      row.mention = m?.label;
      row.mentionPositive = m?.positive ?? true;
    }
    rows.add(row);
  }

  // Rangs généraux.
  _rank(rows, (r) => r.average, (r, rank, ex) {
    r.rank = rank;
    r.exAequo = ex;
  });
  // Rangs et moyennes de classe par matière.
  for (var i = 0; i < cls.subjects.length; i++) {
    final items = [for (final r in rows) r.subjects[i]];
    _rank(items, (x) => x.onScale, (x, rank, ex) {
      x.rank = rank;
      x.exAequo = ex;
    });
    final vals = items.map((x) => x.average).whereType<double>().toList();
    final ca = vals.isEmpty ? null : vals.reduce((a, b) => a + b) / vals.length;
    for (final x in items) {
      x.classAverage = ca;
    }
  }
  final avgs = rows.map((r) => r.average).whereType<double>().toList();
  return ClassResults(
    cls,
    p,
    rows,
    avgs.isEmpty ? null : avgs.reduce((a, b) => a + b) / avgs.length,
    avgs.isEmpty ? null : avgs.reduce((a, b) => a > b ? a : b),
    avgs.isEmpty ? null : avgs.reduce((a, b) => a < b ? a : b),
  );
}

/// Classement « compétition » : 1, 2, 2, 4… ; égalité au centième près.
void _rank<T>(List<T> items, double? Function(T) value, void Function(T, int, bool) set) {
  final vals = <T, double>{
    for (final i in items)
      if (value(i) != null) i: round2(value(i)!)
  };
  for (final i in items) {
    final v = vals[i];
    if (v == null) {
      set(i, 0, false);
      continue;
    }
    final better = vals.values.where((x) => x > v).length;
    final same = vals.values.where((x) => x == v).length;
    set(i, better + 1, same > 1);
  }
}

MentionRule? mentionFor(double on20, List<MentionRule> rules) {
  for (final m in rules) {
    if (on20 >= m.min && on20 < m.max) return m;
  }
  return null;
}

/// Appréciation automatique d'une note ramenée sur 20.
String appreciation(double? on20) {
  if (on20 == null) return '';
  if (on20 >= 18) return 'Excellent';
  if (on20 >= 16) return 'Très bien';
  if (on20 >= 14) return 'Bien';
  if (on20 >= 12) return 'Assez bien';
  if (on20 >= 10) return 'Passable';
  if (on20 >= 8) return 'Insuffisant';
  if (on20 >= 5) return 'Faible';
  return 'Très faible';
}

/// « 1er », « 1re », « 2e », avec « ex » en cas d'égalité.
String ordinal(int? rank, {bool female = false, bool exAequo = false}) {
  if (rank == null || rank <= 0) return '—';
  final s = rank == 1 ? (female ? '1re' : '1er') : '${rank}e';
  return exAequo ? '$s ex' : s;
}

bool isFemale(Student s) => s.sexe.trim().toUpperCase().startsWith('F');

/// Note affichée « 12,50 » (ou vide).
String fmt(double? v, {int digits = 2}) => v == null ? '' : v.toStringAsFixed(digits).replaceAll('.', ',');

/// Lecture d'une note saisie (« 12,5 », « 12.5 ») ; null si vide ou invalide.
double? parseNote(String raw) {
  final t = raw.trim().replaceAll(',', '.');
  if (t.isEmpty) return null;
  return double.tryParse(t);
}

/// Résultat annuel d'un élève : moyennes des périodes et moyenne annuelle.
class AnnualResult {
  final Student student;
  final Map<String, double?> periodAverages;
  final double? average;
  int? rank;
  bool exAequo = false;
  String decision = '';

  AnnualResult(this.student, this.periodAverages, this.average);
}

List<AnnualResult> computeAnnual(GradeBook gb, ClassConfig cls, List<ClassResults> perPeriod) {
  final students = perPeriod.isEmpty ? <Student>[] : perPeriod.first.rows.map((r) => r.student).toList();
  final out = <AnnualResult>[];
  for (final s in students) {
    final pa = <String, double?>{};
    var sum = 0.0, w = 0.0;
    for (final pr in perPeriod) {
      final a = pr.of(s.id)?.average;
      pa[pr.period.id] = a;
      if (a != null && pr.period.weight > 0) {
        sum += a * pr.period.weight;
        w += pr.period.weight;
      }
    }
    final avg = w == 0 ? null : sum / w;
    final r = AnnualResult(s, pa, avg);
    final manual = gb.decisions[s.id];
    if (manual != null && manual.trim().isNotEmpty) {
      r.decision = manual;
    } else if (avg != null) {
      r.decision = avg * 20 / cls.scale >= gb.settings.passMark
          ? (isFemale(s) ? 'Admise en classe supérieure' : 'Admis en classe supérieure')
          : 'Redouble';
    }
    out.add(r);
  }
  _rank(out, (r) => r.average, (r, rank, ex) {
    r.rank = rank;
    r.exAequo = ex;
  });
  return out;
}
