import 'dart:io';
import 'dart:typed_data';

import 'package:carte_scolaire/app_state.dart';
import 'package:carte_scolaire/models.dart';
import 'package:carte_scolaire/services/background_removal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Photo d'essai 300 × 400 : fond vert, « personne » rouge au centre.
Uint8List samplePhoto() {
  final im = img.Image(width: 300, height: 400);
  img.fill(im, color: img.ColorRgb8(40, 200, 40));
  img.fillCircle(im, x: 150, y: 220, radius: 110, color: img.ColorRgb8(200, 30, 30));
  return Uint8List.fromList(img.encodeJpg(im, quality: 95));
}

/// Détourage simulé : un disque au centre.
int calls = 0;
Future<Uint8List> fakeSegmenter(Uint8List photo) async {
  calls++;
  final src = img.decodeImage(photo)!;
  final m = img.Image(width: src.width, height: src.height, numChannels: 1);
  img.fillCircle(m, x: src.width ~/ 2, y: (src.height * 0.55).round(), radius: (src.width * 0.37).round(), color: img.ColorRgb8(255, 255, 255));
  return Uint8List.fromList(img.encodePng(m));
}

img.Pixel px(Uint8List jpg, int x, int y) => img.decodeImage(jpg)!.getPixel(x, y);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('entrée du modèle : taille multiple de 32, valeurs dans [-1, 1], ordre RGB par plans', () {
    final inp = prepareModelInput(samplePhoto());
    expect((inp.width, inp.height), (384, 512));
    expect((inp.srcWidth, inp.srcHeight), (300, 400));
    expect(inp.data.length, 3 * 384 * 512);
    // Coin en haut à gauche : fond vert (40, 200, 40).
    expect(inp.data[0], closeTo((40 - 127.5) / 127.5, 0.05));
    expect(inp.data[384 * 512], closeTo((200 - 127.5) / 127.5, 0.05));
  });

  test('sortie du modèle → masque PNG à la taille de la photo', () {
    final out = Float32List(4 * 4)..fillRange(5, 7, 1.0);
    final mask = img.decodePng(maskFromOutput(out, 4, 4, 40, 40))!;
    expect((mask.width, mask.height), (40, 40));
    expect(mask.getPixel(0, 0).r, 0);
  });

  test('composition : fond remplacé, personne intacte', () {
    return fakeSegmenter(samplePhoto()).then((mask) {
      final out = compositeBackground(samplePhoto(), mask, 0xFF1565C0);
      final corner = px(out, 5, 5);
      expect(corner.r, closeTo(0x15, 8));
      expect(corner.b, closeTo(0xC0, 8));
      final center = px(out, 150, 220);
      expect(center.r, greaterThan(170));
      expect(center.g, lessThan(60));
      expect(maskCoverage(mask), inInclusiveRange(0.2, 0.6));
    });
  });

  group('file automatique', () {
    late AppState app;
    late PhotoBackgroundController bg;
    late Student a, b;

    setUp(() {
      calls = 0;
      app = AppState()..loaded = true;
      a = Student(nom: 'Ouédraogo', prenom: 'Awa');
      b = Student(nom: 'Kaboré', prenom: 'Jean');
      app.students.addAll([a, b]);
      bg = PhotoBackgroundController(app, segmenter: fakeSegmenter);
    });
    tearDown(() => bg.dispose());

    Future<void> idle() async {
      while (bg.busy) {
        await Future.delayed(const Duration(milliseconds: 20));
      }
    }

    test('désactivé par défaut : la photo reste telle quelle', () async {
      app.setPhoto(a, samplePhoto());
      await idle();
      expect(calls, 0);
      expect(a.raw, isNull);
    });

    test('nouvelle photo → fond bleu automatiquement ; nouvelle couleur sans recalcul ; retour à l\'origine', () async {
      await bg.setColor(0xFF1565C0);
      final original = samplePhoto();
      app.setPhoto(a, original);
      expect(bg.isProcessing(a), isTrue);
      await idle();
      expect(calls, 1);
      expect(a.photoBg, 0xFF1565C0);
      expect(a.raw, original);
      expect(a.mask, isNotNull);
      expect(px(a.photo!, 5, 5).b, closeTo(0xC0, 8));

      // Couleur blanche : les photos déjà traitées changent, sans relancer le détourage.
      await bg.setColor(0xFFFFFFFF);
      await idle();
      expect(calls, 1);
      expect(a.photoBg, 0xFFFFFFFF);
      expect(px(a.photo!, 5, 5).r, greaterThan(245));

      // Photos prises avant l'activation : « Appliquer aux photos déjà prises ».
      app.photosWithoutHook(b, samplePhoto());
      expect(bg.todo, [b]);
      bg.applyToAll();
      await idle();
      expect(b.photoBg, 0xFFFFFFFF);
      expect(calls, 2);

      app.restorePhotoBackground(a);
      expect(a.photo, original);
      expect(a.raw, isNull);
      expect(a.photoBg, isNull);
    });

    test('photo remplacée pendant le traitement : la nouvelle est gardée puis traitée', () async {
      await bg.setColor(0xFF1565C0);
      app.setPhoto(a, samplePhoto());
      final second = samplePhoto();
      app.setPhoto(a, second);
      await idle();
      expect(a.raw, second);
      expect(a.photoBg, 0xFF1565C0);
    });

    test('personne non détectée : photo inchangée, message d\'erreur', () async {
      bg.segmenter = (p) async {
        final src = img.decodeImage(p)!;
        return Uint8List.fromList(img.encodePng(img.Image(width: src.width, height: src.height, numChannels: 1)));
      };
      await bg.setColor(0xFF1565C0);
      final photo = samplePhoto();
      app.setPhoto(a, photo);
      await idle();
      expect(a.photo, photo);
      expect(a.raw, isNull);
      expect(bg.lastError, contains('non détectée'));
    });

    test('le modèle est bien embarqué dans l\'application', () {
      expect(File('assets/models/modnet.onnx').lengthSync(), greaterThan(10 * 1024 * 1024));
    });
  });
}
