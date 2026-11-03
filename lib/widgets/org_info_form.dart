import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../services/photo_utils.dart';
import 'common.dart';

/// Informations de l'établissement (ou de l'entreprise) : nom, logo, cachet, direction,
/// coordonnées, en-tête officiel. Utilisées sur les cartes, bulletins et emplois du temps.
class OrgInfoForm extends StatelessWidget {
  final AppState state;

  /// Rubriques affichées dans des cartes séparées (sinon une seule colonne).
  final bool sections;
  const OrgInfoForm({super.key, required this.state, this.sections = true});

  Future<void> _pickImage(
      BuildContext context, Future<Uint8List> Function(Uint8List) prep, void Function(Uint8List) assign) async {
    try {
      final bytes = (await pickOneFile(type: FileType.image))?.$2;
      if (bytes == null) return;
      assign(await prep(bytes));
      state.changed();
    } catch (_) {
      if (context.mounted) toast(context, 'Image illisible : choisissez un fichier PNG ou JPEG.', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = state.school;
    final school = state.isSchool;
    final k = state.projectId;
    void set(void Function() f) {
      f();
      state.changed();
    }

    Widget imageSlot(String label, String hint, Uint8List? img, Future<Uint8List> Function(Uint8List) prep,
            void Function(Uint8List?) assign) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFFF5F6F8),
                border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.all(5),
              child: img != null ? Image.memory(img, fit: BoxFit.contain) : const Icon(Icons.image_outlined),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(hint, style: Theme.of(context).textTheme.bodySmall),
                Wrap(spacing: 4, children: [
                  TextButton(
                    onPressed: () => _pickImage(context, prep, assign),
                    child: Text(img == null ? 'Ajouter' : 'Changer'),
                  ),
                  if (img != null) TextButton(onPressed: () => set(() => assign(null)), child: const Text('Retirer')),
                ]),
              ]),
            ),
          ]),
        );

    Widget field(String id, String label, String value, ValueChanged<String> on, {String? hint, TextInputType? kb}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextSetting(
            key: ValueKey('org-$k-$id'),
            label: label,
            value: value,
            hint: hint,
            keyboard: kb,
            onChanged: (v) => set(() => on(v)),
          ),
        );

    Future<void> addGallery() async {
      try {
        final f = await FilePicker.pickFiles(type: FileType.image);
        for (final x in f.take(9 - s.gallery.length)) {
          s.gallery.add(await prepareBackground(await x.readAsBytes()));
        }
        state.changed();
      } catch (_) {
        if (context.mounted) toast(context, 'Image illisible : choisissez des fichiers PNG ou JPEG.', error: true);
      }
    }

    final groups = <(String, String, List<Widget>)>[
      (
        school ? 'Établissement' : 'Entreprise',
        school ? 'Nom, logo, devise et année scolaire' : 'Nom, logo et slogan',
        [
          imageSlot('Logo', 'Sur les cartes, bulletins et emplois du temps', s.logo, prepareLogo, (b) => s.logo = b),
          field('name', school ? 'Nom de l\'établissement' : 'Nom de l\'entreprise', s.name, (v) => s.name = v,
              hint: school ? 'Collège Privé Évangélique Maranatha' : 'OMZAKREVO INFORMATIQUE'),
          field('short', 'Nom court / sigle', s.shortName, (v) => s.shortName = v,
              hint: school ? 'C.P.E MARANATHA' : 'OMZAKREVO'),
          field('slogan', school ? 'Devise de l\'établissement' : 'Slogan', s.slogan, (v) => s.slogan = v,
              hint: school ? 'DISCIPLINE - TRAVAIL - PROGRÈS' : 'Toujours une solution !'),
          if (school) field('year', 'Année scolaire', s.schoolYear, (v) => s.schoolYear = v, hint: '2026-2027'),
        ],
      ),
      (
        'Coordonnées',
        'Adresse, téléphone, site web',
        [
          field('address', 'Adresse', s.address, (v) => s.address = v, hint: 'Ouagadougou, secteur 15'),
          field('phone', 'Téléphone', s.phone, (v) => s.phone = v, kb: TextInputType.phone),
          field('web', 'Site web / e-mail / réseaux', s.website, (v) => s.website = v),
        ],
      ),
      (
        school ? 'Direction et cachet' : 'Signature et cachet',
        'Signataire des cartes et des bulletins',
        [
          field('signer', school ? 'Nom du directeur / signataire' : 'Nom du signataire', s.signerName,
              (v) => s.signerName = v,
              hint: 'M. BAZIÉ Jean'),
          field('title', 'Titre du signataire', s.directorTitle, (v) => s.directorTitle = v,
              hint: school ? 'Le Directeur, Le Proviseur…' : 'Le Directeur général'),
          imageSlot('Cachet', 'Photo ou scan du cachet : le fond blanc est retiré automatiquement', s.stamp,
              prepareStamp, (b) => s.stamp = b),
        ],
      ),
      if (school)
        (
          'En-tête officiel',
          'Pays, ministère et région (cartes et bulletins)',
          [
            field('country', 'Pays', s.country, (v) => s.country = v),
            field('devise', 'Devise nationale', s.devise, (v) => s.devise = v),
            field('ministry', 'Ministère', s.ministry, (v) => s.ministry = v),
            field('region', 'Région / Province', s.region, (v) => s.region = v,
                hint: 'Région des Cascades - Province de la Léraba'),
            imageSlot('Armoiries / emblème', 'À droite de l\'en-tête (drapeau par défaut)', s.emblem, prepareLogo,
                (b) => s.emblem = b),
          ],
        ),
      if (!school || s.services.isNotEmpty || s.gallery.isNotEmpty)
        (
          'Services et photos',
          'Pour les cartes de visite',
          [
            TextFormField(
              key: ValueKey('org-$k-services'),
              initialValue: s.services,
              minLines: 3,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: 'Services / produits (un par ligne)',
                hintText: 'Maintenance informatique\nRéseaux Wi-Fi\nVidéosurveillance',
              ),
              onChanged: (v) => set(() => s.services = v),
            ),
            const SizedBox(height: 12),
            Text('Images de présentation (${s.gallery.length}/9) : produits, réalisations, locaux…',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (var i = 0; i < s.gallery.length; i++)
                Stack(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(s.gallery[i], width: 72, height: 54, fit: BoxFit.cover),
                  ),
                  Positioned(
                    right: -6,
                    top: -6,
                    child: IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.cancel, size: 18),
                      onPressed: () => set(() => s.gallery.removeAt(i)),
                    ),
                  ),
                ]),
              if (s.gallery.length < 9)
                OutlinedButton.icon(
                    onPressed: addGallery, icon: const Icon(Icons.add_photo_alternate), label: const Text('Ajouter')),
            ]),
          ],
        ),
    ];

    if (!sections) {
      return Section(
        title: school ? 'Établissement' : 'Entreprise',
        subtitle: 'Ces informations apparaissent sur toutes les cartes',
        children: [
          for (final (t, _, ch) in groups) ...[
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 8),
              child: Text(t, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ),
            ...ch,
          ],
        ],
      );
    }
    return LayoutBuilder(builder: (context, box) {
      final cols = box.maxWidth >= 1100 ? 3 : (box.maxWidth >= 720 ? 2 : 1);
      final w = (box.maxWidth - (cols - 1) * 12) / cols;
      return Wrap(spacing: 12, runSpacing: 12, children: [
        for (final (t, sub, ch) in groups) SizedBox(width: w, child: Section(title: t, subtitle: sub, children: ch)),
      ]);
    });
  }
}
