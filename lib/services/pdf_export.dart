import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:screenshot/screenshot.dart';

import '../designs/card_designs.dart';
import '../models.dart';
import 'photo_utils.dart';

/// Résolution de rendu : 4 px logiques/mm × 3 = 12 px/mm ≈ 305 dpi.
const _scale = 4.0;
const _pixelRatio = 3.0;

/// Rend une carte en image JPEG haute définition.
Future<Uint8List> renderCard(
  ScreenshotController controller,
  CardTemplate t,
  SchoolInfo school,
  Student s,
) async {
  final size = Size(t.widthMm * _scale, t.heightMm * _scale);
  final png = await controller.captureFromWidget(
    MediaQuery(
      data: MediaQueryData(size: size),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Material(
          type: MaterialType.transparency,
          child: CardView(template: t, school: school, student: s, scale: _scale, rounded: false),
        ),
      ),
    ),
    pixelRatio: _pixelRatio,
    targetSize: size,
    delay: const Duration(milliseconds: 80),
  );
  return pngToJpeg(png);
}

/// Construit le PDF : planche A4 ou une page par carte.
Future<Uint8List> buildCardsPdf({
  required List<Student> students,
  required CardTemplate template,
  required SchoolInfo school,
  required PrintLayout layout,
  void Function(int done, int total)? onProgress,
  bool Function()? cancelled,
}) async {
  final controller = ScreenshotController();
  final images = <Uint8List>[];
  for (var i = 0; i < students.length; i++) {
    if (cancelled?.call() ?? false) throw const _Cancelled();
    images.add(await renderCard(controller, template, school, students[i]));
    onProgress?.call(i + 1, students.length);
  }

  final doc = pw.Document(title: 'Cartes scolaires – ${school.name}', author: school.name);
  const mm = PdfPageFormat.mm;
  final w = template.widthMm, h = template.heightMm;

  if (!layout.a4Sheet) {
    final format = PdfPageFormat(w * mm, h * mm, marginAll: 0);
    for (final im in images) {
      doc.addPage(pw.Page(
        pageFormat: format,
        build: (_) => pw.Image(pw.MemoryImage(im), width: w * mm, height: h * mm, fit: pw.BoxFit.fill),
      ));
    }
    return doc.save();
  }

  final (cols, rows) = layout.grid(w, h);
  if (cols == 0 || rows == 0) {
    throw ArgumentError('La carte est trop grande pour une feuille A4 avec ces marges.');
  }
  final perPage = cols * rows;
  final gridW = cols * w + (cols - 1) * layout.gapMm;
  final gridH = rows * h + (rows - 1) * layout.gapMm;
  final left = (210 - gridW) / 2;
  final top = (297 - gridH) / 2;

  for (var start = 0; start < images.length; start += perPage) {
    final page = images.skip(start).take(perPage).toList();
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4.copyWith(marginTop: 0, marginBottom: 0, marginLeft: 0, marginRight: 0),
      build: (_) {
        final children = <pw.Widget>[];
        for (var i = 0; i < page.length; i++) {
          final c = i % cols, r = i ~/ cols;
          children.add(pw.Positioned(
            left: (left + c * (w + layout.gapMm)) * mm,
            top: (top + r * (h + layout.gapMm)) * mm,
            child: pw.Image(pw.MemoryImage(page[i]), width: w * mm, height: h * mm, fit: pw.BoxFit.fill),
          ));
        }
        if (layout.cutMarks) children.addAll(_cutMarks(cols, rows, w, h, layout.gapMm, left, top));
        return pw.SizedBox(
          width: 210 * mm,
          height: 297 * mm,
          child: pw.Stack(children: children),
        );
      },
    ));
  }
  return doc.save();
}

/// Traits de coupe dans les marges, alignés sur chaque bord de carte.
List<pw.Widget> _cutMarks(int cols, int rows, double w, double h, double gap, double left, double top) {
  const mm = PdfPageFormat.mm;
  const len = 4.0, off = 1.0, thick = 0.25;
  final out = <pw.Widget>[];
  final xs = <double>{};
  final ys = <double>{};
  for (var c = 0; c < cols; c++) {
    xs.add(left + c * (w + gap));
    xs.add(left + c * (w + gap) + w);
  }
  for (var r = 0; r < rows; r++) {
    ys.add(top + r * (h + gap));
    ys.add(top + r * (h + gap) + h);
  }
  final gridBottom = top + rows * h + (rows - 1) * gap;
  final gridRight = left + cols * w + (cols - 1) * gap;
  pw.Widget line(double x, double y, double lw, double lh) => pw.Positioned(
        left: x * mm,
        top: y * mm,
        child: pw.Container(width: lw * mm, height: lh * mm, color: PdfColors.grey700),
      );
  for (final x in xs) {
    final l = top - off < len ? top - off : len;
    if (l > 0.5) {
      out.add(line(x - thick / 2, top - off - l, thick, l));
      out.add(line(x - thick / 2, gridBottom + off, thick, l));
    }
  }
  for (final y in ys) {
    final l = left - off < len ? left - off : len;
    if (l > 0.5) {
      out.add(line(left - off - l, y - thick / 2, l, thick));
      out.add(line(gridRight + off, y - thick / 2, l, thick));
    }
  }
  return out;
}

class _Cancelled implements Exception {
  const _Cancelled();
}

bool isCancelled(Object e) => e is _Cancelled;
