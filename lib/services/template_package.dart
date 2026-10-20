import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../models.dart';
import 'photo_utils.dart';

/// Fichier de modèle partageable (.zip) :
///
///   modele.json     réglages du modèle et textes de l'établissement
///   fond.jpg        image de fond (modèle « Fond personnalisé »)
///   logo.png        logo de l'école
///   armoiries.png   emblème / armoiries
///   cachet.png      cachet
///
/// Les images sont des fichiers ordinaires : on peut les retoucher dans
/// Photoshop puis remettre le ZIP. Un fichier .carte.json seul (images
/// intégrées) est aussi accepté.
Uint8List exportTemplatePackage(SavedTemplate s) {
  final archive = Archive();
  void add(String name, List<int> data) => archive.addFile(ArchiveFile(name, data.length, data));

  final t = s.template.toJson()..remove('background');
  final school = s.school?.toJson()
    ?..remove('logo')
    ..remove('emblem')
    ..remove('stamp');
  add(
      'modele.json',
      utf8.encode(const JsonEncoder.withIndent('  ').convert({
        'carteScolaireModele': 2,
        'name': s.name,
        'template': t,
        if (school != null) 'school': school,
      })));
  if (s.template.background != null) add('fond.jpg', s.template.background!);
  if (s.school?.logo != null) add('logo.png', s.school!.logo!);
  if (s.school?.emblem != null) add('armoiries.png', s.school!.emblem!);
  if (s.school?.stamp != null) add('cachet.png', s.school!.stamp!);
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

bool _isImage(String n) => RegExp(r'\.(png|jpe?g|webp)$', caseSensitive: false).hasMatch(n);

/// Lit un modèle (.zip ou .json). Lève [FormatException] si le fichier n'en est pas un.
Future<SavedTemplate> importTemplatePackage(Uint8List bytes, String fileName) async {
  final isZip = bytes.length > 4 && bytes[0] == 0x50 && bytes[1] == 0x4B;
  if (!isZip) {
    final j = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    if (j['template'] == null) throw const FormatException('Pas un modèle');
    return SavedTemplate.fromJson(j)..id = Student.newId();
  }

  final archive = ZipDecoder().decodeBytes(bytes);
  ArchiveFile? json;
  final images = <String, Uint8List>{};
  for (final f in archive.files) {
    if (!f.isFile) continue;
    final name = f.name.split('/').last.toLowerCase();
    if (name.startsWith('.') || f.name.contains('__MACOSX')) continue;
    if (name.endsWith('.json')) json ??= f;
    if (_isImage(name)) images[name] = Uint8List.fromList(f.content as List<int>);
  }

  SavedTemplate s;
  if (json != null) {
    final j = jsonDecode(utf8.decode(json.content as List<int>)) as Map<String, dynamic>;
    if (j['template'] == null) throw const FormatException('Pas un modèle');
    s = SavedTemplate.fromJson(j)..id = Student.newId();
  } else {
    // ZIP sans réglages : on crée un modèle « Fond personnalisé » à partir des images.
    final base = fileName.split('/').last.replaceAll(RegExp(r'\.zip$', caseSensitive: false), '');
    s = SavedTemplate(name: base.isEmpty ? 'Modèle importé' : base, template: CardTemplate(designId: 'personnalise'));
  }

  Uint8List? find(List<String> keys) {
    for (final e in images.entries) {
      final stem = e.key.replaceAll(RegExp(r'\.[a-z]+$'), '');
      if (keys.any((k) => stem == k || stem.startsWith(k))) return e.value;
    }
    return null;
  }

  final bg = find(['fond', 'background', 'arriere', 'bg']);
  final logo = find(['logo']);
  final emblem = find(['armoiries', 'embleme', 'emblem', 'blason']);
  final stamp = find(['cachet', 'stamp', 'tampon']);
  if (bg != null) s.template.background = await prepareBackground(bg);
  if (logo != null || emblem != null || stamp != null) {
    final sc = s.school ??= SchoolInfo(name: s.name, shortName: '');
    if (logo != null) sc.logo = await prepareLogo(logo);
    if (emblem != null) sc.emblem = await prepareLogo(emblem);
    if (stamp != null) sc.stamp = await prepareStamp(stamp);
  }
  if (json == null && bg == null) throw const FormatException('ZIP sans modèle');
  return s;
}
