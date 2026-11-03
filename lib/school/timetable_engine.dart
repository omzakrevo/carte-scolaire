import 'dart:math';

import 'school_models.dart';

/// Une séance à placer : une heure d'une matière dans une classe.
class _Session {
  final String cls;
  final Subject subject;
  final String? teacher;
  _Session(this.cls, this.subject, this.teacher);
}

/// Résultat de la génération.
class TimetableResult {
  final Map<String, Map<String, Lesson>> table;

  /// Séances qui n'ont pas trouvé de place : « 3e A – Maths (M. X) ».
  final List<String> unplaced;
  final double penalty;
  TimetableResult(this.table, this.unplaced, this.penalty);
}

/// Conflit : un professeur a deux classes au même créneau.
class Conflict {
  final String slot;
  final String teacherId;
  final List<String> classes;
  Conflict(this.slot, this.teacherId, this.classes);
}

/// Génère l'emploi du temps des [classNames]. Les séances verrouillées (placées à la main)
/// sont gardées ; les autres sont replacées. Plusieurs essais, on garde le meilleur.
TimetableResult generateTimetable(GradeBook gb, List<String> classNames, {int attempts = 40, int seed = 7}) {
  final rnd = Random(seed);
  TimetableResult? best;
  for (var a = 0; a < attempts; a++) {
    final r = _attempt(gb, classNames, rnd);
    if (best == null ||
        r.unplaced.length < best.unplaced.length ||
        (r.unplaced.length == best.unplaced.length && r.penalty < best.penalty)) {
      best = r;
    }
    if (best.unplaced.isEmpty && a >= 8) break;
  }
  return best!;
}

TimetableResult _attempt(GradeBook gb, List<String> classNames, Random rnd) {
  final tt = gb.tt;
  final usable = tt.usable();
  final usableSet = usable.toSet();
  final table = <String, Map<String, Lesson>>{};
  final teacherBusy = <String, Set<String>>{}; // professeur -> créneaux
  final teacherLoad = <String, int>{};

  // Séances verrouillées de toutes les classes (y compris celles non régénérées) : elles occupent les professeurs.
  for (final e in gb.timetable.entries) {
    final cls = gb.classes[e.key];
    final regenerate = classNames.contains(e.key);
    for (final l in e.value.entries) {
      if (regenerate && !l.value.locked) continue;
      table.putIfAbsent(e.key, () => {})[l.key] = Lesson(l.value.subjectId, locked: l.value.locked, room: l.value.room);
      final subj = cls?.subjects.where((s) => s.id == l.value.subjectId).firstOrNull;
      final t = subj?.teacherId;
      if (t != null) {
        teacherBusy.putIfAbsent(t, () => {}).add(l.key);
        teacherLoad[t] = (teacherLoad[t] ?? 0) + 1;
      }
    }
  }

  // Séances à placer.
  final sessions = <_Session>[];
  for (final name in classNames) {
    final cls = gb.classes[name];
    if (cls == null) continue;
    final existing = table[name] ?? {};
    for (final s in cls.subjects) {
      if (s.hours <= 0) continue;
      final already = existing.values.where((l) => l.subjectId == s.id).length;
      for (var i = already; i < s.hours; i++) {
        sessions.add(_Session(name, s, s.teacherId));
      }
    }
  }
  // Les professeurs les plus chargés d'abord, puis les matières aux plus gros volumes.
  final load = <String, int>{};
  for (final s in sessions) {
    if (s.teacher != null) load[s.teacher!] = (load[s.teacher!] ?? 0) + 1;
  }
  final jitter = {for (final s in sessions) s: rnd.nextDouble()};
  sessions.sort((a, b) {
    final la = a.teacher == null ? 0 : load[a.teacher!]!;
    final lb = b.teacher == null ? 0 : load[b.teacher!]!;
    if (la != lb) return lb.compareTo(la);
    if (a.subject.hours != b.subject.hours) return b.subject.hours.compareTo(a.subject.hours);
    return jitter[a]!.compareTo(jitter[b]!);
  });

  final unplaced = <String>[];
  var penalty = 0.0;
  for (final s in sessions) {
    final ct = table.putIfAbsent(s.cls, () => {});
    final teacher = gb.teacher(s.teacher);
    String? bestSlot;
    var bestScore = double.infinity;
    for (final slot in usable) {
      if (ct.containsKey(slot)) continue;
      if (teacher != null) {
        if (teacherBusy[teacher.id]?.contains(slot) ?? false) continue;
        if (teacher.unavailable.contains(slot)) continue;
        if (teacher.maxHours > 0 && (teacherLoad[teacher.id] ?? 0) >= teacher.maxHours) continue;
      }
      final day = slot.split('|').first;
      final idx = int.parse(slot.split('|').last);
      var score = rnd.nextDouble() * 0.6;
      // Même matière le même jour : à éviter, sauf en séance double (créneau voisin).
      var sameDay = 0;
      var adjacent = false;
      for (final e in ct.entries) {
        if (e.value.subjectId != s.subject.id) continue;
        final p = e.key.split('|');
        if (p.first != day) continue;
        sameDay++;
        final j = int.parse(p.last);
        if ((j - idx).abs() == 1 && !_breakBetween(tt, j, idx)) adjacent = true;
      }
      if (sameDay > 0) score += adjacent && sameDay == 1 && s.subject.hours >= 4 ? 2 : 12 * sameDay;
      // Journées équilibrées pour la classe et le professeur.
      score += ct.keys.where((k) => k.startsWith('$day|')).length * 1.0;
      if (teacher != null) score += (teacherBusy[teacher.id] ?? {}).where((k) => k.startsWith('$day|')).length * 0.6;
      // Léger avantage aux créneaux du matin.
      score += idx * 0.15;
      if (score < bestScore) {
        bestScore = score;
        bestSlot = slot;
      }
    }
    if (bestSlot == null || !usableSet.contains(bestSlot)) {
      final tn = teacher == null ? '' : ' (${teacher.name})';
      unplaced.add('${s.cls} – ${s.subject.name}$tn');
      penalty += 100;
      continue;
    }
    ct[bestSlot] = Lesson(s.subject.id);
    penalty += bestScore;
    if (teacher != null) {
      teacherBusy.putIfAbsent(teacher.id, () => {}).add(bestSlot);
      teacherLoad[teacher.id] = (teacherLoad[teacher.id] ?? 0) + 1;
    }
  }
  return TimetableResult(table, _summarize(unplaced), penalty);
}

bool _breakBetween(TimetableSettings tt, int a, int b) {
  final lo = min(a, b), hi = max(a, b);
  for (var i = lo + 1; i < hi; i++) {
    if (tt.slots[i].isBreak) return true;
  }
  return false;
}

/// « 3e A – Maths » ×3 → « 3e A – Maths (3 h) ».
List<String> _summarize(List<String> list) {
  final count = <String, int>{};
  for (final e in list) {
    count[e] = (count[e] ?? 0) + 1;
  }
  return [for (final e in count.entries) e.value > 1 ? '${e.key} : ${e.value} h' : '${e.key} : 1 h'];
}

/// Conflits de professeurs (même créneau, deux classes) dans l'emploi du temps actuel.
List<Conflict> findConflicts(GradeBook gb) {
  final at = <String, Map<String, List<String>>>{}; // slot -> teacher -> classes
  for (final e in gb.timetable.entries) {
    final cls = gb.classes[e.key];
    if (cls == null) continue;
    for (final l in e.value.entries) {
      final subj = cls.subjects.where((s) => s.id == l.value.subjectId).firstOrNull;
      final t = subj?.teacherId;
      if (t == null) continue;
      at.putIfAbsent(l.key, () => {}).putIfAbsent(t, () => []).add(e.key);
    }
  }
  return [
    for (final s in at.entries)
      for (final t in s.value.entries)
        if (t.value.length > 1) Conflict(s.key, t.key, t.value),
  ];
}

/// Emploi du temps d'un professeur : créneau → (classe, matière).
Map<String, (String, Subject)> teacherSchedule(GradeBook gb, String teacherId) {
  final out = <String, (String, Subject)>{};
  for (final e in gb.timetable.entries) {
    final cls = gb.classes[e.key];
    if (cls == null) continue;
    for (final l in e.value.entries) {
      final subj = cls.subjects.where((s) => s.id == l.value.subjectId).firstOrNull;
      if (subj != null && subj.teacherId == teacherId) out[l.key] = (e.key, subj);
    }
  }
  return out;
}

/// Séances prévues et placées par matière pour une classe.
Map<String, (int planned, int placed)> classCoverage(GradeBook gb, String className) {
  final cls = gb.classes[className];
  final t = gb.timetable[className] ?? {};
  return {
    for (final s in cls?.subjects ?? <Subject>[])
      if (s.hours > 0) s.id: (s.hours, t.values.where((l) => l.subjectId == s.id).length),
  };
}
