import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Recadre au format photo d'identité 3:4, corrige l'orientation EXIF
/// et réduit la taille (450 × 600 px suffisent pour une impression nette).
Future<Uint8List> preparePhoto(Uint8List bytes) => compute(_preparePhoto, bytes);

Uint8List _preparePhoto(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw const FormatException('Image illisible');
  var im = img.bakeOrientation(decoded);
  const ratio = 3 / 4;
  int w = im.width, h = im.height;
  int cw, ch;
  if (w / h > ratio) {
    ch = h;
    cw = (h * ratio).round();
  } else {
    cw = w;
    ch = (w / ratio).round();
  }
  // Légèrement décalé vers le haut : le visage est rarement au centre exact.
  final x = ((w - cw) / 2).round();
  final y = ((h - ch) * 0.35).round();
  im = img.copyCrop(im, x: x, y: y, width: cw, height: ch);
  if (im.width > 450) im = img.copyResize(im, width: 450, interpolation: img.Interpolation.cubic);
  return Uint8List.fromList(img.encodeJpg(im, quality: 88));
}

/// Réduit un logo à 400 px maximum en conservant la transparence.
Future<Uint8List> prepareLogo(Uint8List bytes) => compute(_prepareLogo, bytes);

Uint8List _prepareLogo(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw const FormatException('Image illisible');
  var im = img.bakeOrientation(decoded);
  if (im.width > 400 || im.height > 400) {
    im = im.width >= im.height ? img.copyResize(im, width: 400) : img.copyResize(im, height: 400);
  }
  return Uint8List.fromList(img.encodePng(im));
}

/// Convertit le PNG d'une carte en JPEG pour garder un PDF léger.
Future<Uint8List> pngToJpeg(Uint8List png) => compute(_pngToJpeg, png);

Uint8List _pngToJpeg(Uint8List png) {
  final im = img.decodePng(png)!;
  final flat = img.Image(width: im.width, height: im.height);
  img.fill(flat, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(flat, im);
  return Uint8List.fromList(img.encodeJpg(flat, quality: 92));
}

/// Cachet scanné : le fond blanc devient transparent.
Future<Uint8List> prepareStamp(Uint8List bytes) => compute(_prepareStamp, bytes);

Uint8List _prepareStamp(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw const FormatException('Image illisible');
  var im = img.bakeOrientation(decoded);
  if (im.width > 500 || im.height > 500) {
    im = im.width >= im.height ? img.copyResize(im, width: 500) : img.copyResize(im, height: 500);
  }
  final out = im.convert(numChannels: 4);
  for (final p in out) {
    final lum = (p.r + p.g + p.b) / 3;
    if (lum > 215) {
      p.a = 0;
    } else if (lum > 170) {
      p.a = (p.a * (215 - lum) / 45).round();
    }
  }
  return Uint8List.fromList(img.encodePng(out));
}

/// Image de fond de carte : 2000 px de large maximum, JPEG.
Future<Uint8List> prepareBackground(Uint8List bytes) => compute(_prepareBackground, bytes);

Uint8List _prepareBackground(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw const FormatException('Image illisible');
  var im = img.bakeOrientation(decoded);
  final longSide = im.width >= im.height ? im.width : im.height;
  if (longSide > 2000) {
    im = im.width >= im.height ? img.copyResize(im, width: 2000) : img.copyResize(im, height: 2000);
  }
  return Uint8List.fromList(img.encodeJpg(im, quality: 90));
}

/// Photo d'origine normalisée : orientation corrigée, 1600 px maximum, JPEG.
/// Sert de base au recadrage (et au recadrage ultérieur).
Future<Uint8List> normalizeOriginal(Uint8List bytes) => compute(_normalizeOriginal, bytes);

Uint8List _normalizeOriginal(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw const FormatException('Image illisible');
  var im = img.bakeOrientation(decoded);
  final longSide = im.width >= im.height ? im.width : im.height;
  if (longSide > 1600) {
    im = im.width >= im.height ? img.copyResize(im, width: 1600) : img.copyResize(im, height: 1600);
  }
  return Uint8List.fromList(img.encodeJpg(im, quality: 90));
}

/// Tourne une photo de 90° (sens horaire si [clockwise]).
Future<Uint8List> rotatePhoto(Uint8List bytes, bool clockwise) => compute(_rotatePhoto, (bytes, clockwise ? 90 : -90));

Uint8List _rotatePhoto((Uint8List, int) a) {
  final im = img.decodeImage(a.$1)!;
  return Uint8List.fromList(img.encodeJpg(img.copyRotate(im, angle: a.$2), quality: 90));
}

/// Découpe la zone choisie (en pixels de l'image) et la met au format 450 × 600.
Future<Uint8List> cropPhoto(Uint8List bytes, int x, int y, int w, int h) => compute(_cropPhoto, (bytes, x, y, w, h));

Uint8List _cropPhoto((Uint8List, int, int, int, int) a) {
  final (bytes, x, y, w, h) = a;
  var im = img.decodeImage(bytes)!;
  final cx = x.clamp(0, im.width - 1);
  final cy = y.clamp(0, im.height - 1);
  im = img.copyCrop(im, x: cx, y: cy, width: w.clamp(1, im.width - cx), height: h.clamp(1, im.height - cy));
  im = img.copyResize(im, width: 450, height: 600, interpolation: img.Interpolation.cubic);
  return Uint8List.fromList(img.encodeJpg(im, quality: 90));
}
