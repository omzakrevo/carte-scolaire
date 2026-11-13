import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;

import '../app_state.dart';
import '../models.dart';

/// Changement automatique du fond des photos d'identité, entièrement hors ligne.
///
/// Le détourage utilise MODNet (portrait matting, licence Apache 2.0), exécuté par
/// ONNX Runtime sur le téléphone ou l'ordinateur : aucune photo ne quitte l'appareil.

/// Couleurs de fond proposées.
const photoBackgroundColors = <(String, int)>[
  ('Bleu', 0xFF1565C0),
  ('Bleu clair', 0xFF4FA3E0),
  ('Blanc', 0xFFFFFFFF),
  ('Gris clair', 0xFFE3E6EA),
  ('Rouge', 0xFFC62828),
  ('Vert', 0xFF2E7D32),
];

String photoBackgroundName(int color) {
  for (final (n, c) in photoBackgroundColors) {
    if (c == color) return n;
  }
  return 'Personnalisée';
}

/// Entrée du modèle : image ramenée à ~512 px (multiples de 32), normalisée dans [-1, 1], format NCHW.
class ModelInput {
  final Float32List data;
  final int width;
  final int height;
  final int srcWidth;
  final int srcHeight;
  const ModelInput(this.data, this.width, this.height, this.srcWidth, this.srcHeight);
}

ModelInput prepareModelInput(Uint8List photo, {int target = 512}) {
  final decoded = img.decodeImage(photo);
  if (decoded == null) throw const FormatException('Image illisible');
  final src = img.bakeOrientation(decoded);
  final scale = target / math.max(src.width, src.height);
  int snap(double v) => math.max(32, (v / 32).round() * 32);
  final w = snap(src.width * scale), h = snap(src.height * scale);
  final small = img.copyResize(src, width: w, height: h, interpolation: img.Interpolation.linear);
  final data = Float32List(3 * w * h);
  final plane = w * h;
  var i = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = small.getPixel(x, y);
      data[i] = (p.r - 127.5) / 127.5;
      data[plane + i] = (p.g - 127.5) / 127.5;
      data[2 * plane + i] = (p.b - 127.5) / 127.5;
      i++;
    }
  }
  return ModelInput(data, w, h, src.width, src.height);
}

/// Sortie du modèle (valeurs 0..1, taille du modèle) → masque PNG à la taille de la photo.
Uint8List maskFromOutput(Float32List out, int w, int h, int srcW, int srcH) {
  final m = img.Image(width: w, height: h, numChannels: 1);
  var i = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final v = out[i++];
      m.setPixelR(x, y, (v.clamp(0.0, 1.0) * 255).round());
    }
  }
  final big = img.copyResize(m, width: srcW, height: srcH, interpolation: img.Interpolation.linear);
  return Uint8List.fromList(img.encodePng(big));
}

/// Remplace le fond : photo × masque + couleur × (1 − masque).
/// Les bords très transparents sont nettoyés pour éviter un halo de l'ancien fond.
Uint8List compositeBackground(Uint8List photo, Uint8List maskPng, int color) {
  final decoded = img.decodeImage(photo);
  final mask = img.decodePng(maskPng);
  if (decoded == null || mask == null) throw const FormatException('Image illisible');
  final src = img.bakeOrientation(decoded);
  final m = (mask.width == src.width && mask.height == src.height)
      ? mask
      : img.copyResize(mask, width: src.width, height: src.height, interpolation: img.Interpolation.linear);
  final br = (color >> 16) & 0xFF, bg = (color >> 8) & 0xFF, bb = color & 0xFF;
  final out = img.Image(width: src.width, height: src.height);
  for (var y = 0; y < src.height; y++) {
    for (var x = 0; x < src.width; x++) {
      var a = m.getPixel(x, y).r / 255.0;
      // Seuils doux : fond franc → couleur pure, personne franche → photo intacte.
      a = ((a - 0.06) / 0.88).clamp(0.0, 1.0);
      final p = src.getPixel(x, y);
      out.setPixelRgb(
        x,
        y,
        (p.r * a + br * (1 - a)).round(),
        (p.g * a + bg * (1 - a)).round(),
        (p.b * a + bb * (1 - a)).round(),
      );
    }
  }
  return Uint8List.fromList(img.encodeJpg(out, quality: 90));
}

/// Part de la photo occupée par la personne (0..1) : sert à repérer un détourage raté.
double maskCoverage(Uint8List maskPng) {
  final m = img.decodePng(maskPng);
  if (m == null) return 0;
  var sum = 0.0;
  for (final p in m) {
    sum += p.r / 255.0;
  }
  return sum / (m.width * m.height);
}

Future<ModelInput> _prepareIsolate(Uint8List photo) => compute(prepareModelInput, photo);

Future<Uint8List> _maskIsolate(Float32List out, int w, int h, int sw, int sh) =>
    compute((List a) => maskFromOutput(a[0] as Float32List, a[1] as int, a[2] as int, a[3] as int, a[4] as int),
        [out, w, h, sw, sh]);

Future<Uint8List> compositeIsolate(Uint8List photo, Uint8List mask, int color) =>
    compute((List a) => compositeBackground(a[0] as Uint8List, a[1] as Uint8List, a[2] as int), [photo, mask, color]);

/// Calcule le masque de la personne. Remplaçable dans les tests.
typedef Segmenter = Future<Uint8List> Function(Uint8List photo);

/// Détourage par le modèle MODNet embarqué (assets/models/modnet.onnx).
class ModnetSegmenter {
  static Future<OrtSession>? _session;

  static bool get supported =>
      !kIsWeb && (Platform.isAndroid || Platform.isWindows || Platform.isIOS || Platform.isMacOS || Platform.isLinux);

  static Future<OrtSession> _load() => _session ??= OnnxRuntime().createSessionFromAsset('assets/models/modnet.onnx').catchError((e) {
        _session = null;
        throw e;
      });

  static Future<Uint8List> segment(Uint8List photo) async {
    final input = await _prepareIsolate(photo);
    final session = await _load();
    final tensor = await OrtValue.fromList(input.data, [1, 3, input.height, input.width]);
    Map<String, OrtValue>? outputs;
    try {
      final name = session.inputNames.isEmpty ? 'input' : session.inputNames.first;
      outputs = await session.run({name: tensor});
      final values = await outputs.values.first.asFlattenedList();
      final out = Float32List(values.length);
      for (var i = 0; i < values.length; i++) {
        out[i] = (values[i] as num).toDouble();
      }
      return await _maskIsolate(out, input.width, input.height, input.srcWidth, input.srcHeight);
    } finally {
      await tensor.dispose();
      for (final v in outputs?.values ?? const <OrtValue>[]) {
        await v.dispose();
      }
    }
  }
}

/// File d'attente : chaque nouvelle photo est détourée en arrière-plan, l'une après l'autre.
class PhotoBackgroundController extends ChangeNotifier {
  final AppState app;
  Segmenter segmenter;

  /// Élèves en cours ou en attente de traitement.
  final List<String> queue = [];
  String? current;
  String? lastError;
  int done = 0;
  bool _running = false;

  PhotoBackgroundController(this.app, {Segmenter? segmenter}) : segmenter = segmenter ?? ModnetSegmenter.segment {
    app.onNewPhoto = _onNewPhoto;
  }

  @override
  void dispose() {
    if (app.onNewPhoto == _onNewPhoto) app.onNewPhoto = null;
    super.dispose();
  }

  int? get color => app.template.photoBackground;
  bool get enabled => color != null;
  bool get busy => current != null || queue.isNotEmpty;
  int get pending => queue.length + (current == null ? 0 : 1);

  bool isProcessing(Student s) => current == s.id || queue.contains(s.id);

  void _onNewPhoto(Student s) {
    if (enabled) enqueue(s);
  }

  void enqueue(Student s) {
    // Une photo en cours de traitement peut être remplacée : la nouvelle passe après.
    if (s.photo == null || queue.contains(s.id)) return;
    queue.add(s.id);
    notifyListeners();
    _run();
  }

  /// Photos dont le fond n'est pas encore changé (ou d'une autre couleur).
  List<Student> get todo => app.students.where((s) => s.photo != null && s.photoBg != color).toList();

  /// Choix de la couleur (null = désactivé). Les photos déjà détourées changent aussitôt de couleur.
  Future<void> setColor(int? c) async {
    app.template.photoBackground = c;
    app.changed();
    notifyListeners();
    if (c == null) return;
    for (final s in app.students.where((s) => s.mask != null && s.raw != null && s.photoBg != c).toList()) {
      enqueue(s);
    }
  }

  /// Change le fond de toutes les photos qui ne l'ont pas encore.
  void applyToAll() {
    for (final s in todo) {
      enqueue(s);
    }
  }

  Future<void> _run() async {
    if (_running) return;
    _running = true;
    try {
      while (queue.isNotEmpty) {
        final id = queue.removeAt(0);
        current = id;
        notifyListeners();
        final s = app.students.where((e) => e.id == id).firstOrNull;
        final c = color;
        if (s == null || s.photo == null || c == null) continue;
        final version = s.photoVersion;
        try {
          final raw = s.raw ?? s.photo!;
          var mask = s.raw != null ? s.mask : null;
          if (mask == null) {
            mask = await segmenter(raw);
            if (maskCoverage(mask) < 0.03) {
              throw const FormatException('personne non détectée');
            }
          }
          final photo = await compositeIsolate(raw, mask, c);
          // La photo a été remplacée pendant le traitement : on laisse la nouvelle.
          if (s.photoVersion != version || !app.students.contains(s)) continue;
          app.setPhotoBackground(s, photo, raw: raw, mask: mask, color: c);
          done++;
          lastError = null;
        } catch (e) {
          lastError = 'Fond non changé pour ${s.fullName} : $e';
        }
      }
    } finally {
      current = null;
      _running = false;
      notifyListeners();
    }
  }
}

class PhotoBackgroundScope extends InheritedNotifier<PhotoBackgroundController> {
  const PhotoBackgroundScope({super.key, required PhotoBackgroundController controller, required super.child})
      : super(notifier: controller);

  static PhotoBackgroundController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PhotoBackgroundScope>()!.notifier!;

  static PhotoBackgroundController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PhotoBackgroundScope>()?.notifier;
}
