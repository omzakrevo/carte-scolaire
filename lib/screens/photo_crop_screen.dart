import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/photo_utils.dart';

/// Résultat du recadrage : photo prête pour la carte + photo d'origine.
class CropResult {
  final Uint8List photo;
  final Uint8List original;
  const CropResult(this.photo, this.original);
}

/// Recadrage de la photo dans le cadre de la carte (format 3:4) :
/// on déplace et on zoome l'image, elle ne peut pas sortir du cadre.
class PhotoCropScreen extends StatefulWidget {
  /// Photo d'origine déjà normalisée (voir [normalizeOriginal]).
  final Uint8List original;
  final String? title;
  const PhotoCropScreen({super.key, required this.original, this.title});

  /// Ouvre l'écran et renvoie la photo recadrée, ou `null` si annulé.
  static Future<CropResult?> open(BuildContext context, Uint8List original, {String? title}) =>
      Navigator.of(context).push<CropResult>(
        MaterialPageRoute(builder: (_) => PhotoCropScreen(original: original, title: title), fullscreenDialog: true),
      );

  @override
  State<PhotoCropScreen> createState() => _PhotoCropScreenState();
}

class _PhotoCropScreenState extends State<PhotoCropScreen> {
  late Uint8List _bytes = widget.original;
  final _ctrl = TransformationController();
  Size? _imageSize;
  Size _frame = Size.zero;
  double _baseScale = 1;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _decodeSize();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _decodeSize() async {
    final codec = await ui.instantiateImageCodec(_bytes);
    final frame = await codec.getNextFrame();
    if (!mounted) return;
    setState(() {
      _imageSize = Size(frame.image.width.toDouble(), frame.image.height.toDouble());
      _frame = Size.zero; // force le recentrage
    });
  }

  void _center(Size frame) {
    final im = _imageSize!;
    _baseScale =
        (frame.width / im.width) > (frame.height / im.height) ? frame.width / im.width : frame.height / im.height;
    final dw = im.width * _baseScale, dh = im.height * _baseScale;
    setState(() {});
    _ctrl.value = Matrix4.identity()..translateByDouble(-(dw - frame.width) / 2, -(dh - frame.height) / 2, 0, 1);
  }

  Future<void> _rotate(bool clockwise) async {
    setState(() => _busy = true);
    _bytes = await rotatePhoto(_bytes, clockwise);
    _imageSize = null;
    await _decodeSize();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _validate() async {
    final im = _imageSize;
    if (im == null || _frame == Size.zero) return;
    setState(() => _busy = true);
    final m = _ctrl.value;
    final scale = m.getMaxScaleOnAxis();
    final tx = m.storage[12], ty = m.storage[13];
    final k = 1 / (_baseScale * scale);
    final x = (-tx * k).round();
    final y = (-ty * k).round();
    final w = (_frame.width * k).round();
    final h = (_frame.height * k).round();
    final photo = await cropPhoto(_bytes, x, y, w, h);
    if (mounted) Navigator.of(context).pop(CropResult(photo, _bytes));
  }

  @override
  Widget build(BuildContext context) {
    final im = _imageSize;
    return Scaffold(
      backgroundColor: const Color(0xFF111418),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111418),
        foregroundColor: Colors.white,
        title: Text(widget.title ?? 'Cadrer la photo'),
        actions: [
          TextButton(
            onPressed: _busy || im == null ? null : _validate,
            child: const Text('Valider', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text(
              'Glissez pour déplacer, pincez pour zoomer. Placez le visage dans l\'ovale, les yeux sur la ligne.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
          ),
          Expanded(
            child: LayoutBuilder(builder: (context, box) {
              if (im == null) return const Center(child: CircularProgressIndicator());
              var fw = box.maxWidth - 48;
              var fh = fw * 4 / 3;
              if (fh > box.maxHeight - 24) {
                fh = box.maxHeight - 24;
                fw = fh * 3 / 4;
              }
              final frame = Size(fw, fh);
              if (frame != _frame) {
                _frame = frame;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && _imageSize != null) _center(frame);
                });
              }
              return Center(
                child: SizedBox(
                  width: fw,
                  height: fh,
                  child: Stack(children: [
                    ClipRect(
                      child: InteractiveViewer(
                        transformationController: _ctrl,
                        constrained: false,
                        minScale: 1,
                        maxScale: 6,
                        boundaryMargin: EdgeInsets.zero,
                        child: SizedBox(
                          width: im.width * _baseScale,
                          height: im.height * _baseScale,
                          child: Image.memory(_bytes, fit: BoxFit.fill, gaplessPlayback: true),
                        ),
                      ),
                    ),
                    const Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: FaceGuidePainter()))),
                    if (_busy) const Center(child: CircularProgressIndicator()),
                  ]),
                ),
              );
            }),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(alignment: WrapAlignment.center, spacing: 12, runSpacing: 8, children: [
              _tool(Icons.rotate_left, 'Pivoter', _busy ? null : () => _rotate(false)),
              _tool(Icons.rotate_right, 'Pivoter', _busy ? null : () => _rotate(true)),
              _tool(Icons.center_focus_strong, 'Recentrer',
                  _busy || im == null ? null : () => _center(_frame)),
              FilledButton.icon(
                onPressed: _busy || im == null ? null : _validate,
                icon: const Icon(Icons.check),
                label: const Text('Valider le cadrage'),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _tool(IconData icon, String label, VoidCallback? onTap) => OutlinedButton.icon(
        style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white38)),
        onPressed: onTap,
        icon: Icon(icon),
        label: Text(label),
      );
}

/// Gabarit de cadrage : ovale du visage, ligne des yeux, épaules, grille.
class FaceGuidePainter extends CustomPainter {
  final bool dim;
  const FaceGuidePainter({this.dim = true});

  @override
  void paint(Canvas canvas, Size s) {
    final oval =
        Rect.fromCenter(center: Offset(s.width / 2, s.height * 0.40), width: s.width * 0.56, height: s.height * 0.5);
    if (dim) {
      final outside = Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & s)
        ..addOval(oval);
      canvas.drawPath(outside, Paint()..color = const Color(0x55000000));
    }
    final stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;
    // Ovale en pointillés
    final path = Path()..addOval(oval);
    for (final m in path.computeMetrics()) {
      for (double d = 0; d < m.length; d += 14) {
        canvas.drawPath(m.extractPath(d, d + 8), stroke);
      }
    }
    // Ligne des yeux
    final eyes = oval.top + oval.height * 0.42;
    canvas.drawLine(Offset(oval.left + oval.width * 0.12, eyes), Offset(oval.right - oval.width * 0.12, eyes),
        stroke..color = const Color(0xCCFFD54F));
    // Épaules
    final shoulders = Path()
      ..moveTo(s.width * 0.06, s.height)
      ..quadraticBezierTo(s.width * 0.12, s.height * 0.8, s.width * 0.34, s.height * 0.76)
      ..moveTo(s.width * 0.94, s.height)
      ..quadraticBezierTo(s.width * 0.88, s.height * 0.8, s.width * 0.66, s.height * 0.76);
    canvas.drawPath(shoulders, stroke..color = const Color(0x99FFFFFF));
    // Bord du cadre
    canvas.drawRect(
        Offset.zero & s,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3);
  }

  @override
  bool shouldRepaint(FaceGuidePainter o) => o.dim != dim;
}
