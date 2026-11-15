import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Import d'un lot de photos : chaque photo reçoit son heure de prise, le lot est trié,
/// puis les photos sont attribuées dans l'ordre de la liste des noms.

/// Origine de l'heure retenue pour une photo.
enum TakenSource { exif, fileName, fileDate, none }

class BatchPhoto {
  final String name;
  final String? path;
  Uint8List? bytes;
  DateTime? taken;
  TakenSource source;
  BatchPhoto(this.name, {this.path, this.bytes, this.taken, this.source = TakenSource.none});
}

/// « 2026:11:14 09:30:12 » (format EXIF).
DateTime? parseExifDate(String? v) {
  if (v == null) return null;
  final m = RegExp(r'(\d{4})[:\-](\d{2})[:\-](\d{2})[ T](\d{2}):(\d{2}):(\d{2})').firstMatch(v);
  if (m == null) return null;
  final p = [for (var i = 1; i <= 6; i++) int.parse(m[i]!)];
  if (p[0] < 1990 || p[1] < 1 || p[1] > 12 || p[2] < 1 || p[2] > 31) return null;
  return DateTime(p[0], p[1], p[2], p[3], p[4], p[5]);
}

/// Heure de prise lue dans les données EXIF d'un JPEG.
DateTime? exifTakenDate(Uint8List bytes) {
  try {
    final e = img.decodeJpgExif(bytes);
    if (e == null) return null;
    final sub = e.exifIfd;
    return parseExifDate(sub[0x9003]?.toString()) ??
        parseExifDate(sub[0x9004]?.toString()) ??
        parseExifDate(e.imageIfd[0x0132]?.toString());
  } catch (_) {
    return null;
  }
}

/// Date dans le nom du fichier : IMG_20261114_093012.jpg, PXL_20261114_093012345.jpg,
/// WhatsApp Image 2026-11-14 at 09.30.12.jpeg, Screenshot_2026-11-14-09-30-12.png…
DateTime? fileNameDate(String name) {
  final m = RegExp(r'(20\d{2}|19\d{2})[-_.]?(\d{2})[-_.]?(\d{2})\D{0,4}?(\d{2})[-_.:h]?(\d{2})[-_.:m]?(\d{2})')
      .firstMatch(name);
  if (m == null) return null;
  final p = [for (var i = 1; i <= 6; i++) int.parse(m[i]!)];
  if (p[1] < 1 || p[1] > 12 || p[2] < 1 || p[2] > 31 || p[3] > 23 || p[4] > 59 || p[5] > 59) return null;
  return DateTime(p[0], p[1], p[2], p[3], p[4], p[5]);
}

/// Comparaison « naturelle » des noms de fichier (IMG_2 avant IMG_10).
int naturalCompare(String a, String b) {
  final re = RegExp(r'(\d+)|(\D+)');
  final pa = re.allMatches(a.toLowerCase()).map((m) => m[0]!).toList();
  final pb = re.allMatches(b.toLowerCase()).map((m) => m[0]!).toList();
  for (var i = 0; i < pa.length && i < pb.length; i++) {
    final na = int.tryParse(pa[i]), nb = int.tryParse(pb[i]);
    final c = (na != null && nb != null) ? na.compareTo(nb) : pa[i].compareTo(pb[i]);
    if (c != 0) return c;
  }
  return pa.length.compareTo(pb.length);
}

/// Trie par heure de prise (les photos sans heure à la fin), puis par nom de fichier.
void sortByTaken(List<BatchPhoto> list, {bool byName = false}) {
  list.sort((a, b) {
    if (!byName) {
      final ta = a.taken, tb = b.taken;
      if (ta != null && tb != null && ta != tb) return ta.compareTo(tb);
      if (ta != null && tb == null) return -1;
      if (ta == null && tb != null) return 1;
    }
    return naturalCompare(a.name, b.name);
  });
}

/// Photos attribuées aux personnes, case par case. `slots[i]` va à la i-ème personne ;
/// les photos en trop restent dans [spare].
class PhotoAssignment {
  final int people;
  final List<BatchPhoto?> slots;
  final List<BatchPhoto> spare;

  PhotoAssignment(this.people, List<BatchPhoto> photos)
      : slots = [for (var i = 0; i < people; i++) i < photos.length ? photos[i] : null],
        spare = photos.length > people ? photos.sublist(people) : [];

  int get assigned => slots.where((e) => e != null).length;

  /// Cette personne n'a pas de photo : les photos suivantes descendent d'une case.
  void insertGap(int i) {
    final list = <BatchPhoto?>[...slots];
    list.insert(i, null);
    final last = list.length > people ? list.removeLast() : null;
    slots
      ..clear()
      ..addAll(list);
    if (last != null) spare.insert(0, last);
  }

  /// Photo en trop (ratée, en double) : elle est retirée et les suivantes remontent.
  void removeAt(int i) {
    final p = slots[i];
    slots.removeAt(i);
    slots.add(spare.isEmpty ? null : spare.removeAt(0));
    if (p != null) _discarded.add(p);
  }

  final List<BatchPhoto> _discarded = [];
  List<BatchPhoto> get discarded => _discarded;

  /// Échange les photos de deux personnes.
  void swap(int i, int j) {
    final t = slots[i];
    slots[i] = slots[j];
    slots[j] = t;
  }

  /// Donne une photo restante (ou écartée) à la personne [i] ; sa photo actuelle part dans les restantes.
  void assignSpare(BatchPhoto p, int i) {
    spare.remove(p);
    _discarded.remove(p);
    final old = slots[i];
    slots[i] = p;
    if (old != null) spare.insert(0, old);
  }

  /// Retire la photo de la personne [i] sans décaler (elle passe dans les restantes).
  void clear(int i) {
    final p = slots[i];
    if (p == null) return;
    slots[i] = null;
    spare.insert(0, p);
  }
}
