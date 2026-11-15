import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;

import '../app_state.dart';
import '../models.dart';
import 'background_removal.dart';
import 'photo_utils.dart';

/// Retouches automatiques des photos, entièrement sur l'appareil :
/// - recadrage sur le visage (détecteur YuNet, licence MIT, exécuté par ONNX Runtime) ;
/// - amélioration de la lumière (photos trop sombres, trop claires ou ternes).

// ---------------------------------------------------------------------------
// Détection du visage

class Face {
  final double score;

  /// Centre et taille du visage, yeux (droit puis gauche de la personne), en pixels de la photo.
  final double cx, cy, width, height;
  final double eye1x, eye1y, eye2x, eye2y;
  const Face(this.score, this.cx, this.cy, this.width, this.height, this.eye1x, this.eye1y, this.eye2x, this.eye2y);

  double get eyesX => (eye1x + eye2x) / 2;
  double get eyesY => (eye1y + eye2y) / 2;
  double get eyeDistance => math.sqrt(math.pow(eye2x - eye1x, 2) + math.pow(eye2y - eye1y, 2));
}

const _faceSize = 640;

class FaceInput {
  final Float32List data;

  /// Rapport pixels du modèle / pixels de la photo.
  final double scale;
  final int srcWidth, srcHeight;
  const FaceInput(this.data, this.scale, this.srcWidth, this.srcHeight);
}

/// Photo redressée, ramenée dans un carré 640 × 640 (coin haut-gauche), canaux B, G, R en 0..255.
FaceInput prepareFaceInput(Uint8List photo) {
  final decoded = img.decodeImage(photo);
  if (decoded == null) throw const FormatException('Image illisible');
  final src = img.bakeOrientation(decoded);
  final scale = _faceSize / math.max(src.width, src.height);
  final w = math.max(1, (src.width * scale).round()), h = math.max(1, (src.height * scale).round());
  final small = img.copyResize(src, width: w, height: h, interpolation: img.Interpolation.linear);
  const plane = _faceSize * _faceSize;
  final data = Float32List(3 * plane);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = small.getPixel(x, y);
      final i = y * _faceSize + x;
      data[i] = p.b.toDouble();
      data[plane + i] = p.g.toDouble();
      data[2 * plane + i] = p.r.toDouble();
    }
  }
  return FaceInput(data, scale, src.width, src.height);
}

/// Lit les sorties du modèle (par pas de 8, 16 et 32 pixels) et renvoie le visage principal.
Face? decodeFace(Map<String, List<double>> out, double scale, {double minScore = 0.6}) {
  Face? best;
  var bestRank = 0.0;
  for (final stride in const [8, 16, 32]) {
    final cls = out['cls_$stride'], obj = out['obj_$stride'], box = out['bbox_$stride'], kps = out['kps_$stride'];
    if (cls == null || obj == null || box == null || kps == null) continue;
    final cols = _faceSize ~/ stride;
    for (var i = 0; i < cls.length; i++) {
      final score = math.sqrt(cls[i].clamp(0.0, 1.0) * obj[i].clamp(0.0, 1.0));
      if (score < minScore) continue;
      final r = i ~/ cols, c = i % cols;
      final w = math.exp(box[i * 4 + 2]) * stride / scale, h = math.exp(box[i * 4 + 3]) * stride / scale;
      // Le visage le plus grand et le plus sûr : c'est la personne photographiée.
      final rank = score * math.sqrt(w * h);
      if (rank <= bestRank) continue;
      double kx(int k) => (kps[i * 10 + 2 * k] + c) * stride / scale;
      double ky(int k) => (kps[i * 10 + 2 * k + 1] + r) * stride / scale;
      bestRank = rank;
      best = Face(score, (c + box[i * 4]) * stride / scale, (r + box[i * 4 + 1]) * stride / scale, w, h, kx(0), ky(0),
          kx(1), ky(1));
    }
  }
  return best;
}

/// Cadre 3:4 autour du visage, comme le gabarit de l'écran de cadrage : visage sur un peu moins
/// de la moitié de la largeur, yeux à 38 % de la hauteur. Renvoie (x, y, largeur, hauteur).
(int, int, int, int) faceCropRect(int imgW, int imgH, Face f) {
  final faceW = math.max(f.width, 2.1 * f.eyeDistance);
  var w = faceW / 0.44;
  var h = w * 4 / 3;
  // Photo trop serrée : on prend le plus grand cadre 3:4 possible.
  final k = math.min(1.0, math.min(imgW / w, imgH / h));
  w *= k;
  h *= k;
  var x = f.eyesX - w / 2;
  var y = f.eyesY - h * 0.38;
  x = x.clamp(0.0, math.max(0.0, imgW - w));
  y = y.clamp(0.0, math.max(0.0, imgH - h));
  return (x.round(), y.round(), w.round(), h.round());
}

/// Cherche le visage d'une photo. Remplaçable dans les tests.
typedef FaceFinder = Future<Face?> Function(Uint8List photo);

class YunetFaceFinder {
  static Future<OrtSession>? _session;

  static Future<OrtSession> _load() =>
      _session ??= OnnxRuntime().createSessionFromAsset('assets/models/yunet.onnx', options: ortOptions()).catchError((e) {
        _session = null;
        throw e;
      });

  static Future<Face?> find(Uint8List photo) async {
    final input = await compute(prepareFaceInput, photo);
    final session = await _load();
    final tensor = await OrtValue.fromList(input.data, [1, 3, _faceSize, _faceSize]);
    Map<String, OrtValue>? outputs;
    try {
      final name = session.inputNames.isEmpty ? 'input' : session.inputNames.first;
      outputs = await session.run({name: tensor});
      final values = <String, List<double>>{};
      for (final e in outputs.entries) {
        values[e.key] = [for (final v in await e.value.asFlattenedList()) (v as num).toDouble()];
      }
      return decodeFace(values, input.scale);
    } finally {
      await tensor.dispose();
      for (final v in outputs?.values ?? const <OrtValue>[]) {
        await v.dispose();
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Lumière

/// Réglage calculé sur la zone du visage : noir, blanc et gamma.
class LightFix {
  final int black, white;
  final double gamma;
  const LightFix(this.black, this.white, this.gamma);

  bool get neutral => black <= 2 && white >= 253 && (gamma - 1).abs() < 0.04;

  Uint8List get table {
    final t = Uint8List(256);
    final range = math.max(1, white - black);
    for (var i = 0; i < 256; i++) {
      final v = ((i - black) / range).clamp(0.0, 1.0);
      t[i] = (math.pow(v, gamma) * 255).round().clamp(0, 255);
    }
    return t;
  }
}

/// Mesure la lumière au centre de la photo (visage et haut du buste) et calcule la correction :
/// contraste étiré avec prudence, puis luminosité moyenne ramenée à un niveau agréable.
LightFix measureLight(img.Image im) {
  final hist = List<int>.filled(256, 0);
  final x0 = (im.width * 0.2).round(), x1 = (im.width * 0.8).round();
  final y0 = (im.height * 0.12).round(), y1 = (im.height * 0.78).round();
  var n = 0;
  for (var y = y0; y < y1; y += 2) {
    for (var x = x0; x < x1; x += 2) {
      final p = im.getPixel(x, y);
      hist[(0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round().clamp(0, 255)]++;
      n++;
    }
  }
  if (n == 0) return const LightFix(0, 255, 1);
  int percentile(double q) {
    var acc = 0;
    for (var i = 0; i < 256; i++) {
      acc += hist[i];
      if (acc >= n * q) return i;
    }
    return 255;
  }

  // Jamais plus de 45 niveaux retirés de chaque côté : pas d'effet brutal.
  final black = math.min(percentile(0.01), 45);
  final white = math.max(percentile(0.995), 150);
  final median = ((percentile(0.5) - black) / math.max(1, white - black)).clamp(0.02, 0.98);
  // Luminosité médiane visée : 0,52 (peau claire ou foncée restent naturelles grâce aux bornes).
  final gamma = (math.log(0.52) / math.log(median)).clamp(0.5, 1.35);
  return LightFix(black, white, gamma);
}

/// Photo mieux éclairée (JPEG). Renvoie null si la photo est déjà bien exposée.
Uint8List? enhanceLight(Uint8List photo) {
  final decoded = img.decodeImage(photo);
  if (decoded == null) throw const FormatException('Image illisible');
  final im = img.bakeOrientation(decoded);
  final fix = measureLight(im);
  if (fix.neutral) return null;
  final t = fix.table;
  for (final p in im) {
    p
      ..r = t[p.r.toInt()]
      ..g = t[p.g.toInt()]
      ..b = t[p.b.toInt()];
  }
  return Uint8List.fromList(img.encodeJpg(im, quality: 92));
}

Future<Uint8List?> enhanceLightIsolate(Uint8List photo) => compute(enhanceLight, photo);

// ---------------------------------------------------------------------------
// Traitement de toutes les photos

class BatchResult {
  int done = 0, skipped = 0, failed = 0;
}

/// Outils appliqués à toutes les photos, avec avancement.
class PhotoTools extends ChangeNotifier {
  final AppState app;
  final PhotoBackgroundController? background;
  FaceFinder faceFinder;

  PhotoTools(this.app, {this.background, FaceFinder? faceFinder}) : faceFinder = faceFinder ?? YunetFaceFinder.find;

  static bool get supported => ModnetSegmenter.supported;

  String? running;
  int done = 0, total = 0;
  bool _cancel = false;

  bool get busy => running != null;
  void cancel() => _cancel = true;

  Future<BatchResult> _each(String label, List<Student> list, Future<bool?> Function(Student) action) async {
    final r = BatchResult();
    if (busy) return r;
    running = label;
    done = 0;
    total = list.length;
    _cancel = false;
    notifyListeners();
    try {
      for (final s in list) {
        if (_cancel) break;
        try {
          if (!app.students.contains(s) || s.photo == null) {
            r.skipped++;
          } else {
            final ok = await action(s);
            ok == true ? r.done++ : r.skipped++;
          }
        } catch (_) {
          r.failed++;
        }
        done++;
        notifyListeners();
      }
    } finally {
      running = null;
      notifyListeners();
    }
    return r;
  }

  List<Student> _withPhoto(Iterable<Student>? only) =>
      (only ?? app.students).where((s) => s.photo != null).toList();

  /// Recadre une photo sur le visage, à partir de la photo d'origine. Faux si aucun visage.
  Future<bool> autoCrop(Student s) async {
    final src = s.original ?? s.raw ?? s.photo;
    if (src == null) return false;
    final version = s.photoVersion;
    final face = await faceFinder(src);
    if (face == null) return false;
    final size = await compute(_imageSize, src);
    final (x, y, w, h) = faceCropRect(size.$1, size.$2, face);
    var photo = await cropPhoto(src, x, y, w, h);
    final enhanced = s.enhanced;
    if (enhanced) photo = await enhanceLightIsolate(photo) ?? photo;
    if (s.photoVersion != version) return false;
    // Nouvelle photo : le fond est refait automatiquement si une couleur est choisie.
    app.setPhoto(s, photo, original: src);
    s.enhanced = enhanced;
    return true;
  }

  Future<BatchResult> autoCropAll({Iterable<Student>? only}) =>
      _each('Recadrage automatique', _withPhoto(only), autoCrop);

  /// Améliore la lumière d'une photo (une seule fois). Le fond coloré est conservé.
  Future<bool> enhance(Student s) async {
    if (s.photo == null || s.enhanced) return false;
    if (background?.isProcessing(s) ?? false) return false;
    final version = s.photoVersion;
    final raw = s.raw, mask = s.mask, color = s.photoBg;
    if (raw != null && mask != null && color != null) {
      final better = await enhanceLightIsolate(raw);
      if (s.photoVersion != version) return false;
      if (better == null) {
        s.enhanced = true;
        return false;
      }
      final photo = await compositeIsolate(better, mask, color);
      if (s.photoVersion != version) return false;
      app.setPhotoPixels(s, photo, raw: better);
    } else {
      final better = await enhanceLightIsolate(s.photo!);
      if (s.photoVersion != version) return false;
      if (better == null) {
        s.enhanced = true;
        return false;
      }
      app.setPhotoPixels(s, better);
    }
    return true;
  }

  Future<BatchResult> enhanceAll({Iterable<Student>? only}) =>
      _each('Amélioration de la lumière', _withPhoto(only).where((s) => !s.enhanced).toList(), enhance);
}

(int, int) _imageSize(Uint8List bytes) {
  final d = img.decodeImage(bytes);
  if (d == null) throw const FormatException('Image illisible');
  final im = img.bakeOrientation(d);
  return (im.width, im.height);
}

class PhotoToolsScope extends InheritedNotifier<PhotoTools> {
  const PhotoToolsScope({super.key, required PhotoTools tools, required super.child}) : super(notifier: tools);

  static PhotoTools? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PhotoToolsScope>()?.notifier;
}
