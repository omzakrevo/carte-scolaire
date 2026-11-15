import 'dart:typed_data';

import 'package:carte_scolaire/app_state.dart';
import 'package:carte_scolaire/models.dart';
import 'package:carte_scolaire/services/photo_tools.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List jpg(int w, int h, int level) {
  final im = img.Image(width: w, height: h);
  for (final p in im) {
    // Dégradé autour du niveau donné.
    final v = (level + (p.x % 40) - 20).clamp(0, 255);
    p
      ..r = v
      ..g = v
      ..b = v;
  }
  return Uint8List.fromList(img.encodeJpg(im, quality: 95));
}

double mean(Uint8List b) {
  final im = img.decodeImage(b)!;
  var s = 0.0;
  for (final p in im) {
    s += p.r;
  }
  return s / (im.width * im.height);
}

void main() {
  test('sorties du détecteur → visage, puis cadre 3:4', () {
    // Un seul visage sûr, au pas de 32 : cellule (ligne 5, colonne 8) d'une grille 20 × 20.
    const n = 400;
    final cls = List<double>.filled(n, 0.01), obj = List<double>.filled(n, 0.01);
    final box = List<double>.filled(n * 4, 0), kps = List<double>.filled(n * 10, 0);
    const i = 5 * 20 + 8;
    cls[i] = 0.9;
    obj[i] = 0.9;
    box[i * 4 + 2] = 1.0986; // largeur = e^1.0986 × 32 ≈ 96
    box[i * 4 + 3] = 1.3863; // hauteur ≈ 128
    kps[i * 10] = -0.7; // œil 1 : x = (8 − 0.7) × 32
    kps[i * 10 + 2] = 0.7;
    final empty8 = List<double>.filled(6400, 0), empty16 = List<double>.filled(1600, 0);
    final out = {
      'cls_32': cls, 'obj_32': obj, 'bbox_32': box, 'kps_32': kps,
      'cls_8': empty8, 'obj_8': empty8, 'bbox_8': List<double>.filled(25600, 0), 'kps_8': List<double>.filled(64000, 0),
      'cls_16': empty16, 'obj_16': empty16, 'bbox_16': List<double>.filled(6400, 0), 'kps_16': List<double>.filled(16000, 0),
    };
    // Photo de 1280 px de large : échelle 0,5.
    final f = decodeFace(out, 0.5)!;
    expect(f.score, closeTo(0.9, 0.001));
    expect(f.width, closeTo(192, 1));
    expect(f.eyesX, closeTo(512, 0.1));
    expect(f.eyesY, closeTo(320, 0.1));
    final (x, y, w, h) = faceCropRect(1280, 960, f);
    expect(w / h, closeTo(0.75, 0.01));
    expect(w, closeTo(192 / 0.44, 2));
    expect(x + w / 2, closeTo(512, 1));
    expect((320 - y) / h, closeTo(0.38, 0.01));
    // Visage trop près du bord ou photo trop petite : le cadre reste dans la photo.
    final (x2, y2, w2, h2) = faceCropRect(300, 300, f);
    expect(x2 >= 0 && y2 >= 0 && x2 + w2 <= 300 && y2 + h2 <= 300, isTrue);
    expect(decodeFace({'cls_32': List.filled(n, 0.1), 'obj_32': obj, 'bbox_32': box, 'kps_32': kps}, 1), isNull);
  });

  test('lumière : photo sombre éclaircie, photo correcte laissée telle quelle', () {
    final dark = jpg(120, 160, 45);
    final fixed = enhanceLight(dark)!;
    expect(mean(fixed), greaterThan(mean(dark) + 40));
    expect(enhanceLight(jpg(120, 160, 245)), isNotNull);
    final good = img.Image(width: 120, height: 160);
    for (final p in good) {
      final v = (p.x * 255 / 119).round();
      p
        ..r = v
        ..g = v
        ..b = v;
    }
    expect(measureLight(good).gamma, closeTo(1, 0.08));
  });

  test('toutes les photos : recadrage sur le visage puis lumière, une seule fois', () async {
    final app = AppState()..loaded = true;
    final a = Student(nom: 'A'), b = Student(nom: 'B'), c = Student(nom: 'C');
    app.students.addAll([a, b, c]);
    app.photosWithoutHook(a, jpg(450, 600, 50));
    a.original = jpg(800, 800, 50);
    app.photosWithoutHook(b, jpg(450, 600, 60));
    final hooked = <String>[];
    app.onNewPhoto = (s) => hooked.add(s.nom);
    final tools = PhotoTools(app,
        faceFinder: (bytes) async =>
            bytes.length == a.original!.length ? const Face(0.9, 400, 300, 150, 190, 370, 290, 430, 290) : null);

    final r = await tools.autoCropAll();
    expect((r.done, r.skipped, r.failed), (1, 1, 0));
    expect(hooked, ['A']); // le fond sera refait pour la photo recadrée
    final cropped = img.decodeImage(a.photo!)!;
    expect((cropped.width, cropped.height), (450, 600));
    expect(a.original!.length, greaterThan(a.photo!.length ~/ 4));

    final before = mean(a.photo!);
    final e = await tools.enhanceAll();
    expect(e.done, 2);
    expect(a.enhanced && b.enhanced, isTrue);
    expect(mean(a.photo!), greaterThan(before + 30));
    final v = a.photoVersion;
    expect((await tools.enhanceAll()).done, 0);
    expect(a.photoVersion, v);
    // Recadrage après la lumière : la photo reste éclaircie.
    await tools.autoCrop(a);
    expect(a.enhanced, isTrue);
    expect(mean(a.photo!), greaterThan(before + 30));
    await Future<void>.delayed(const Duration(seconds: 1));
  });
}
