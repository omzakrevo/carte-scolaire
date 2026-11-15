import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import 'sheet_reader.dart';
import 'storage.dart';

/// Reconnaissance du texte d'une feuille photographiée.
///
/// - Hors ligne (par défaut) : ML Kit sur Android, le moteur OCR intégré à Windows sur PC.
///   La photo ne quitte pas l'appareil.
/// - Lecture IA (facultative) : la photo est envoyée à l'API Claude, plus fiable pour
///   l'écriture à la main ; demande Internet et une clé API (payée à l'usage).
class OcrEngine {
  static bool get offlineSupported => !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isWindows);

  /// Photo redressée (EXIF) et réduite, en JPEG.
  static Uint8List _normalize(List a) {
    final bytes = a[0] as Uint8List;
    final maxSide = a[1] as int;
    final d = img.decodeImage(bytes);
    if (d == null) throw const FormatException('Image illisible');
    var im = img.bakeOrientation(d);
    final long = im.width > im.height ? im.width : im.height;
    if (long > maxSide) {
      im = im.width >= im.height
          ? img.copyResize(im, width: maxSide, interpolation: img.Interpolation.average)
          : img.copyResize(im, height: maxSide, interpolation: img.Interpolation.average);
    }
    return Uint8List.fromList(img.encodeJpg(im, quality: 90));
  }

  static Future<Uint8List> normalize(Uint8List bytes, {int maxSide = 2600}) => compute(_normalize, [bytes, maxSide]);

  static Future<File> _temp(Uint8List bytes, String ext) async {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}${Platform.pathSeparator}feuille_${DateTime.now().microsecondsSinceEpoch}.$ext');
    await f.writeAsBytes(bytes, flush: true);
    return f;
  }

  /// Mots reconnus hors ligne, avec leur position.
  static Future<List<OcrWord>> recognize(Uint8List photo) async {
    if (!offlineSupported) throw UnsupportedError('Lecture hors ligne non disponible sur cet appareil');
    final jpg = await normalize(photo, maxSide: Platform.isWindows ? 2600 : 3000);
    final f = await _temp(jpg, 'jpg');
    try {
      return Platform.isWindows ? await _windows(f) : await _mlkit(f);
    } finally {
      try {
        await f.delete();
      } catch (_) {}
    }
  }

  static Future<List<OcrWord>> _mlkit(File f) async {
    final r = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final res = await r.processImage(InputImage.fromFilePath(f.path));
      return [
        for (final b in res.blocks)
          for (final l in b.lines)
            for (final e in l.elements)
              OcrWord(e.text, e.boundingBox.left, e.boundingBox.top, e.boundingBox.width, e.boundingBox.height),
      ];
    } finally {
      await r.close();
    }
  }

  /// OCR de Windows 10/11 (Windows.Media.Ocr), appelé par PowerShell : rien à installer.
  static Future<List<OcrWord>> _windows(File image) async {
    final script = await _temp(utf8.encode(_windowsScript), 'ps1');
    final out = await _temp(Uint8List(0), 'json');
    try {
      final r = await Process.run('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        script.path,
        '-Image',
        image.path,
        '-Out',
        out.path,
      ]).timeout(const Duration(minutes: 2));
      final text = await out.readAsString();
      if (text.trim().isEmpty) {
        final err = '${r.stderr}'.trim();
        if (err.contains('NO_OCR_LANGUAGE')) {
          throw const FormatException(
              'Aucune langue de reconnaissance installée dans Windows (Paramètres > Heure et langue > Langue : ajoutez Français).');
        }
        throw FormatException('Lecture impossible${err.isEmpty ? '' : ' : ${err.split('\n').first}'}');
      }
      final j = jsonDecode(text);
      final list = j is List ? j : [j];
      return [for (final w in list) if (w is Map) OcrWord.fromJson(w)];
    } finally {
      for (final f in [script, out]) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }
  }

  static const _windowsScript = r'''
param([string]$Image, [string]$Out)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$null = [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]
$null = [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime]
$null = [Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics, ContentType = WindowsRuntime]
$null = [Windows.Globalization.Language, Windows.Globalization, ContentType = WindowsRuntime]
$asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
  $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
})[0]
function Await($op, [Type]$type) {
  $t = $asTask.MakeGenericMethod($type).Invoke($null, @($op))
  $t.Wait(-1) | Out-Null
  $t.Result
}
$file = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($Image)) ([Windows.Storage.StorageFile])
$stream = Await ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
$decoder = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
$bitmap = Await ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
$engine = $null
foreach ($tag in @('fr-FR', 'fr')) {
  $lang = New-Object Windows.Globalization.Language($tag)
  if ([Windows.Media.Ocr.OcrEngine]::IsLanguageSupported($lang)) { $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage($lang); break }
}
if ($engine -eq $null) { $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages() }
if ($engine -eq $null) { [Console]::Error.WriteLine('NO_OCR_LANGUAGE'); exit 2 }
$result = Await ($engine.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])
$words = New-Object System.Collections.ArrayList
foreach ($line in $result.Lines) {
  foreach ($w in $line.Words) {
    $r = $w.BoundingRect
    [void]$words.Add([ordered]@{ t = $w.Text; x = $r.X; y = $r.Y; w = $r.Width; h = $r.Height })
  }
}
$json = ConvertTo-Json -InputObject @($words) -Compress -Depth 3
[System.IO.File]::WriteAllText($Out, $json, (New-Object System.Text.UTF8Encoding($false)))
''';
}

// ---------------------------------------------------------------------------
// Lecture IA (API Claude).

class AiSettings {
  String apiKey;
  String model;
  AiSettings({this.apiKey = '', this.model = defaultModel});

  static const defaultModel = 'claude-sonnet-5-5';
  bool get ready => apiKey.trim().isNotEmpty;

  static Future<File> _file() async =>
      File('${(await Storage.baseDir()).path}${Platform.pathSeparator}lecture_ia.json');

  static Future<AiSettings> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return AiSettings();
      final j = jsonDecode(await f.readAsString()) as Map;
      return AiSettings(apiKey: '${j['key'] ?? ''}', model: '${j['model'] ?? defaultModel}');
    } catch (_) {
      return AiSettings();
    }
  }

  Future<void> save() async => (await _file()).writeAsString(jsonEncode({'key': apiKey.trim(), 'model': model.trim()}));
}

/// Envoie la photo à l'IA et renvoie le tableau relu.
Future<List<List<String>>> readSheetWithAi(Uint8List photo, AiSettings s, {http.Client? client}) async {
  final jpg = await OcrEngine.normalize(photo, maxSide: 1800);
  final c = client ?? http.Client();
  try {
    final res = await c
        .post(
          Uri.parse('https://api.anthropic.com/v1/messages'),
          headers: {
            'x-api-key': s.apiKey.trim(),
            'anthropic-version': '2023-06-01',
            'content-type': 'application/json',
          },
          body: jsonEncode({
            'model': s.model.trim().isEmpty ? AiSettings.defaultModel : s.model.trim(),
            'max_tokens': 8000,
            'messages': [
              {
                'role': 'user',
                'content': [
                  {
                    'type': 'image',
                    'source': {'type': 'base64', 'media_type': 'image/jpeg', 'data': base64Encode(jpg)},
                  },
                  {'type': 'text', 'text': aiSheetPrompt},
                ],
              }
            ],
          }),
        )
        .timeout(const Duration(minutes: 3));
    final body = utf8.decode(res.bodyBytes);
    if (res.statusCode != 200) {
      String msg = 'erreur ${res.statusCode}';
      try {
        msg = '${(jsonDecode(body) as Map)['error']?['message'] ?? msg}';
      } catch (_) {}
      if (res.statusCode == 401) msg = 'clé API refusée';
      throw FormatException('Lecture IA impossible : $msg');
    }
    final j = jsonDecode(body) as Map;
    final text = [
      for (final b in (j['content'] as List? ?? []))
        if (b is Map && b['type'] == 'text') '${b['text']}'
    ].join('\n');
    return parseAiTable(text);
  } finally {
    if (client == null) c.close();
  }
}
