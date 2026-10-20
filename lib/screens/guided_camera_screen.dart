import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'photo_crop_screen.dart';

/// Appareil photo intégré avec gabarit : l'élève est cadré directement au
/// format de la carte (3:4), visage dans l'ovale.
class GuidedCameraScreen extends StatefulWidget {
  final String studentName;
  const GuidedCameraScreen({super.key, required this.studentName});

  /// Renvoie la photo prise (octets JPEG) ou `null`. Lève une exception si
  /// aucun appareil photo n'est disponible (on bascule alors sur l'appareil du système).
  static Future<Uint8List?> open(BuildContext context, String studentName) async {
    final cams = await availableCameras();
    if (cams.isEmpty) throw StateError('Aucun appareil photo');
    if (!context.mounted) return null;
    return Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(builder: (_) => GuidedCameraScreen(studentName: studentName), fullscreenDialog: true),
    );
  }

  @override
  State<GuidedCameraScreen> createState() => _GuidedCameraScreenState();
}

class _GuidedCameraScreenState extends State<GuidedCameraScreen> with WidgetsBindingObserver {
  List<CameraDescription> _cams = [];
  CameraController? _ctrl;
  int _index = 0;
  FlashMode _flash = FlashMode.off;
  bool _shooting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    try {
      _cams = await availableCameras();
      final back = _cams.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
      _index = back < 0 ? 0 : back;
      await _start();
    } catch (e) {
      setState(() => _error = 'Appareil photo indisponible : vérifiez l\'autorisation dans les réglages du téléphone.');
    }
  }

  Future<void> _start() async {
    final old = _ctrl;
    _ctrl = null;
    if (mounted) setState(() {});
    await old?.dispose();
    final c = CameraController(_cams[_index], ResolutionPreset.veryHigh,
        enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
    await c.initialize();
    try {
      await c.setFlashMode(_flash);
    } catch (_) {}
    if (!mounted) {
      await c.dispose();
      return;
    }
    setState(() => _ctrl = c);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _ctrl;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      c.dispose();
      _ctrl = null;
    } else if (state == AppLifecycleState.resumed) {
      _start();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ctrl?.dispose();
    super.dispose();
  }

  Future<void> _shoot() async {
    final c = _ctrl;
    if (c == null || _shooting) return;
    setState(() => _shooting = true);
    try {
      final file = await c.takePicture();
      final bytes = await file.readAsBytes();
      if (mounted) Navigator.of(context).pop(bytes);
    } catch (e) {
      if (mounted) {
        setState(() => _shooting = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Échec de la prise de vue : $e')));
      }
    }
  }

  Future<void> _toggleFlash() async {
    _flash = switch (_flash) {
      FlashMode.off => FlashMode.auto,
      FlashMode.auto => FlashMode.always,
      _ => FlashMode.off,
    };
    try {
      await _ctrl?.setFlashMode(_flash);
    } catch (_) {}
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = _ctrl;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.studentName, overflow: TextOverflow.ellipsis),
      ),
      body: SafeArea(
        child: Column(children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('Visage dans l\'ovale, yeux sur la ligne jaune, fond uni et bien éclairé.',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
          ),
          Expanded(
            child: Center(
              child: _error != null
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
                    )
                  : c == null || !c.value.isInitialized
                      ? const CircularProgressIndicator()
                      : AspectRatio(
                          aspectRatio: 3 / 4,
                          child: Stack(fit: StackFit.expand, children: [
                            ClipRect(
                              child: FittedBox(
                                fit: BoxFit.cover,
                                child: SizedBox(
                                  width: 1000,
                                  height: 1000 * c.value.aspectRatio,
                                  child: CameraPreview(c),
                                ),
                              ),
                            ),
                            const IgnorePointer(child: CustomPaint(painter: FaceGuidePainter())),
                          ]),
                        ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              IconButton(
                tooltip: 'Flash',
                color: Colors.white,
                iconSize: 30,
                onPressed: c == null ? null : _toggleFlash,
                icon: Icon(switch (_flash) {
                  FlashMode.auto => Icons.flash_auto,
                  FlashMode.always => Icons.flash_on,
                  _ => Icons.flash_off,
                }),
              ),
              GestureDetector(
                onTap: _shoot,
                child: Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 4),
                  ),
                  padding: const EdgeInsets.all(5),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _shooting ? Colors.white38 : Colors.white,
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Changer de caméra',
                color: Colors.white,
                iconSize: 30,
                onPressed: _cams.length < 2
                    ? null
                    : () {
                        _index = (_index + 1) % _cams.length;
                        _start();
                      },
                icon: const Icon(Icons.cameraswitch),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
