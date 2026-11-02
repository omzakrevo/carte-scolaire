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
///   elements/…      images ajoutées sur la carte (textes, formes et couleurs sont dans modele.json)
///   galerie/…       images de présentation (cartes de visite)
///
/// Les images sont des fichiers ordinaires : on peut les retoucher dans
/// Photoshop puis remettre le ZIP. Un fichier .carte.json seul (images
/// intégrées) est aussi accepté.
Uint8List exportTemplatePackage(SavedTemplate s) {
  final archive = Archive();
  void add(String name, List<int> data) => archive.addFile(ArchiveFile(name, data.length, data));

  final t = s.template.toJson()..remove('background');
  // Images des éléments : fichiers séparés, référencés par leur chemin.
  final elements = <Map<String, dynamic>>[];
  for (final e in s.template.elements) {
    final j = e.toJson();
    if (e.image != null) {
      final path = 'elements/${e.id}.${_ext(e.image!)}';
      add(path, e.image!);
      j['image'] = path;
    }
    elements.add(j);
  }
  t['elements'] = elements;
  final school = s.school?.toJson()
    ?..remove('logo')
    ..remove('emblem')
    ..remove('stamp')
    ..remove('gallery');
  final gallery = s.school?.gallery ?? const <Uint8List>[];
  for (var i = 0; i < gallery.length; i++) {
    add('galerie/${(i + 1).toString().padLeft(2, '0')}.${_ext(gallery[i])}', gallery[i]);
  }
  add(
      'modele.json',
      utf8.encode(const JsonEncoder.withIndent('  ').convert({
        'carteScolaireModele': 3,
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

String _ext(Uint8List b) => b.length > 3 && b[0] == 0x89 && b[1] == 0x50 ? 'png' : 'jpg';

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
  final byPath = <String, Uint8List>{};
  final gallery = <String, Uint8List>{};
  for (final f in archive.files) {
    if (!f.isFile) continue;
    final name = f.name.split('/').last.toLowerCase();
    if (name.startsWith('.') || f.name.contains('__MACOSX')) continue;
    if (name.endsWith('.json')) json ??= f;
    if (!_isImage(name)) continue;
    final data = Uint8List.fromList(f.content as List<int>);
    final path = f.name.replaceAll('\\', '/');
    byPath[path] = data;
    final dir = path.contains('/') ? path.substring(0, path.lastIndexOf('/')).split('/').last.toLowerCase() : '';
    if (dir == 'galerie' || dir == 'gallery') {
      gallery[path] = data;
    } else if (dir != 'elements') {
      images[name] = data;
    }
  }

  SavedTemplate s;
  if (json != null) {
    final j = jsonDecode(utf8.decode(json.content as List<int>)) as Map<String, dynamic>;
    if (j['template'] == null) throw const FormatException('Pas un modèle');
    // Les images des éléments sont référencées par leur chemin dans le ZIP.
    final els = (j['template'] as Map)['elements'];
    final pathImages = <String, Uint8List>{};
    if (els is List) {
      for (final e in els) {
        if (e is Map &&
            e['image'] is String &&
            !(e['image'] as String).startsWith('iVBOR') &&
            (e['image'] as String).length < 200) {
          final p = e['image'] as String;
          final data = byPath[p] ?? byPath.entries.where((x) => x.key.endsWith(p)).map((x) => x.value).firstOrNull;
          e['image'] = null;
          if (data != null) pathImages[e['id'].toString()] = data;
        }
      }
    }
    s = SavedTemplate.fromJson(j)..id = Student.newId();
    for (final e in s.template.elements) {
      final img = pathImages[e.id];
      if (img != null) e.image = img;
    }
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
  if (gallery.isNotEmpty) {
    final sc = s.school ??= SchoolInfo(name: s.name, shortName: '');
    sc.gallery = [for (final k in gallery.keys.toList()..sort()) await prepareBackground(gallery[k]!)];
  }
  if (json == null && bg == null) throw const FormatException('ZIP sans modèle');
  return s;
}
