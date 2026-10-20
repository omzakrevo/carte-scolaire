import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

final _rand = Random();

/// Un élève et sa photo d'identité.
class Student {
  String id;
  String matricule;
  String nom;
  String prenom;
  String classe;
  String dateNaissance;
  String lieuNaissance;
  String sexe;
  String contact;
  Uint8List? photo;

  /// Photo d'origine (avant recadrage), pour pouvoir recadrer à nouveau.
  Uint8List? original;
  int photoVersion;
  bool validated;

  Student({
    String? id,
    this.matricule = '',
    this.nom = '',
    this.prenom = '',
    this.classe = '',
    this.dateNaissance = '',
    this.lieuNaissance = '',
    this.sexe = '',
    this.contact = '',
    this.photo,
    this.original,
    this.photoVersion = 0,
    this.validated = false,
  }) : id = id ?? newId();

  static String newId() => '${DateTime.now().microsecondsSinceEpoch}${_rand.nextInt(9999)}';

  String get fullName => '${nom.toUpperCase()} $prenom'.trim();

  String get initials {
    final a = nom.isNotEmpty ? nom[0] : '';
    final b = prenom.isNotEmpty ? prenom[0] : '';
    final r = (a + b).toUpperCase();
    return r.isEmpty ? '?' : r;
  }

  /// Contenu du QR code imprimé sur la carte.
  String get qrData => matricule.isNotEmpty ? matricule : [fullName, classe].where((e) => e.isNotEmpty).join(' | ');

  Map<String, dynamic> toJson() => {
        'id': id,
        'matricule': matricule,
        'nom': nom,
        'prenom': prenom,
        'classe': classe,
        'dateNaissance': dateNaissance,
        'lieuNaissance': lieuNaissance,
        'sexe': sexe,
        'contact': contact,
        'photoVersion': photoVersion,
        'validated': validated,
      };

  factory Student.fromJson(Map<String, dynamic> j) => Student(
        id: j['id'] as String?,
        matricule: j['matricule'] ?? '',
        nom: j['nom'] ?? '',
        prenom: j['prenom'] ?? '',
        classe: j['classe'] ?? '',
        dateNaissance: j['dateNaissance'] ?? '',
        lieuNaissance: j['lieuNaissance'] ?? '',
        sexe: j['sexe'] ?? '',
        contact: j['contact'] ?? '',
        photoVersion: j['photoVersion'] ?? 0,
        validated: j['validated'] ?? false,
      );

  static Student sample() => Student(
        id: 'exemple',
        matricule: '2026-CM2-014',
        nom: 'Ouédraogo',
        prenom: 'Awa Mariam',
        classe: 'CM2 A',
        dateNaissance: '12/03/2015',
        lieuNaissance: 'Ouagadougou',
        sexe: 'F',
        contact: '70 00 00 00',
      );
}

/// Informations de l'établissement imprimées sur la carte.
class SchoolInfo {
  String name;
  String shortName;
  String slogan;
  String address;
  String phone;
  String schoolYear;
  String country;
  String devise;
  String ministry;
  String region;
  String directorTitle;
  String signerName;
  Uint8List? logo;

  /// Emblème / armoiries affichés à droite de l'en-tête.
  Uint8List? emblem;

  /// Cachet de l'établissement, posé sur le coin de la photo.
  Uint8List? stamp;

  SchoolInfo({
    this.name = 'Complexe Scolaire Les Étoiles',
    this.shortName = 'C.S. LES ÉTOILES',
    this.slogan = 'DISCIPLINE - TRAVAIL - PROGRÈS',
    this.address = 'Ouagadougou, secteur 15',
    this.phone = '25 00 00 00',
    String? schoolYear,
    this.country = 'BURKINA FASO',
    this.devise = 'Unité-Progrès-Justice',
    this.ministry = 'Ministère de l\'Éducation Nationale',
    this.region = '',
    this.directorTitle = 'Le Directeur',
    this.signerName = '',
    this.logo,
    this.emblem,
    this.stamp,
  }) : schoolYear = schoolYear ?? defaultYear();

  static String defaultYear() {
    final now = DateTime.now();
    final start = now.month >= 8 ? now.year : now.year - 1;
    return '$start-${start + 1}';
  }

  static String? _b64(Uint8List? b) => b == null ? null : base64Encode(b);
  static Uint8List? _unb64(dynamic s) => s == null ? null : base64Decode(s as String);

  Map<String, dynamic> toJson() => {
        'name': name,
        'shortName': shortName,
        'slogan': slogan,
        'address': address,
        'phone': phone,
        'schoolYear': schoolYear,
        'country': country,
        'devise': devise,
        'ministry': ministry,
        'region': region,
        'directorTitle': directorTitle,
        'signerName': signerName,
        'logo': _b64(logo),
        'emblem': _b64(emblem),
        'stamp': _b64(stamp),
      };

  factory SchoolInfo.fromJson(Map<String, dynamic> j) => SchoolInfo(
        name: j['name'] ?? '',
        shortName: j['shortName'] ?? '',
        slogan: j['slogan'] ?? '',
        address: j['address'] ?? '',
        phone: j['phone'] ?? '',
        schoolYear: j['schoolYear'],
        country: j['country'] ?? '',
        devise: j['devise'] ?? '',
        ministry: j['ministry'] ?? '',
        region: j['region'] ?? '',
        directorTitle: j['directorTitle'] ?? '',
        signerName: j['signerName'] ?? '',
        logo: _unb64(j['logo']),
        emblem: _unb64(j['emblem']),
        stamp: _unb64(j['stamp']),
      );
}

/// Les champs d'un élève imprimables sur la carte, dans l'ordre d'affichage.
const cardFields = <String>[
  'matricule',
  'nomPrenom',
  'dateNaissance',
  'lieuNaissance',
  'sexe',
  'classe',
  'contact',
];

const defaultLabels = <String, String>{
  'matricule': 'Matricule',
  'nomPrenom': 'Nom et Prénom',
  'dateNaissance': 'Date de naissance',
  'lieuNaissance': 'Lieu de naissance',
  'sexe': 'Sexe',
  'classe': 'Classe',
  'contact': 'Personne à prévenir',
};

/// Réglages du modèle de carte : design, dimensions, couleurs, textes, champs.
class CardTemplate {
  String designId;
  double widthMm;
  double heightMm;
  int primary;
  int secondary;
  int accent;
  String title;
  String yearLabel;

  /// Libellés modifiables des champs (voir [defaultLabels]).
  Map<String, String> labels;

  /// Champs masqués (voir [cardFields]).
  Set<String> hidden;
  bool showQr;
  bool showSignature;
  bool showStamp;
  double textScale;
  double photoScale;

  /// Image de fond (modèle « Fond personnalisé » ou en filigrane).
  Uint8List? background;

  /// Hauteurs réservées en haut / en bas du fond personnalisé (0 à 0,5).
  double headerSpace;
  double footerSpace;

  /// Position, taille et visibilité de chaque calque (voir [cardLayers]).
  Map<String, LayerAdjust> layers;

  CardTemplate({
    this.designId = 'identite',
    this.widthMm = 85.6,
    this.heightMm = 54,
    this.primary = 0xFFE31E24,
    this.secondary = 0xFF1B2A6B,
    this.accent = 0xFFFFF3B0,
    this.title = 'CARTE D\'IDENTITÉ SCOLAIRE',
    this.yearLabel = 'ANNÉE SCOLAIRE',
    Map<String, String>? labels,
    Set<String>? hidden,
    this.showQr = false,
    this.showSignature = true,
    this.showStamp = true,
    this.textScale = 1.0,
    this.photoScale = 1.0,
    this.background,
    this.headerSpace = 0.3,
    this.footerSpace = 0.12,
    Map<String, LayerAdjust>? layers,
  })  : layers = layers ?? {},
        labels = {...defaultLabels, ...?labels},
        hidden = hidden ?? <String>{};

  bool get landscape => widthMm >= heightMm;

  bool shows(String field) => !hidden.contains(field);
  LayerAdjust layer(String id) => layers.putIfAbsent(id, () => LayerAdjust());
  String label(String field) => labels[field] ?? defaultLabels[field] ?? field;

  /// Copie indépendante (l'image de fond, immuable, est partagée).
  CardTemplate copy() {
    final j = toJson()..remove('background');
    return CardTemplate.fromJson(j)..background = background;
  }

  Map<String, dynamic> toJson() => {
        'designId': designId,
        'widthMm': widthMm,
        'heightMm': heightMm,
        'primary': primary,
        'secondary': secondary,
        'accent': accent,
        'title': title,
        'yearLabel': yearLabel,
        'labels': labels,
        'hidden': hidden.toList(),
        'showQr': showQr,
        'showSignature': showSignature,
        'showStamp': showStamp,
        'textScale': textScale,
        'photoScale': photoScale,
        'background': background == null ? null : base64Encode(background!),
        'headerSpace': headerSpace,
        'footerSpace': footerSpace,
        'layers': {
          for (final e in layers.entries)
            if (!e.value.isDefault) e.key: e.value.toJson(),
        },
      };

  factory CardTemplate.fromJson(Map<String, dynamic> j) => CardTemplate(
        designId: j['designId'] ?? 'identite',
        widthMm: (j['widthMm'] ?? 85.6).toDouble(),
        heightMm: (j['heightMm'] ?? 54).toDouble(),
        primary: j['primary'] ?? 0xFFE31E24,
        secondary: j['secondary'] ?? 0xFF1B2A6B,
        accent: j['accent'] ?? 0xFFFFF3B0,
        title: j['title'] ?? 'CARTE D\'IDENTITÉ SCOLAIRE',
        yearLabel: j['yearLabel'] ?? 'ANNÉE SCOLAIRE',
        labels: (j['labels'] as Map?)?.map((k, v) => MapEntry(k.toString(), v.toString())),
        hidden: (j['hidden'] as List?)?.map((e) => e.toString()).toSet(),
        showQr: j['showQr'] ?? false,
        showSignature: j['showSignature'] ?? true,
        showStamp: j['showStamp'] ?? true,
        textScale: (j['textScale'] ?? 1.0).toDouble(),
        photoScale: (j['photoScale'] ?? 1.0).toDouble(),
        background: j['background'] == null ? null : base64Decode(j['background']),
        headerSpace: (j['headerSpace'] ?? 0.3).toDouble(),
        footerSpace: (j['footerSpace'] ?? 0.12).toDouble(),
        layers: (j['layers'] as Map?)?.map(
          (k, v) => MapEntry(k.toString(), LayerAdjust.fromJson(Map<String, dynamic>.from(v as Map))),
        ),
      );
}

/// Réglage d'un calque déplaçable de la carte : décalage (mm), échelle, masqué.
class LayerAdjust {
  double dx;
  double dy;
  double scale;
  bool hidden;

  LayerAdjust({this.dx = 0, this.dy = 0, this.scale = 1, this.hidden = false});

  bool get isDefault => dx == 0 && dy == 0 && scale == 1 && !hidden;

  Map<String, dynamic> toJson() => {'dx': dx, 'dy': dy, 'scale': scale, 'hidden': hidden};

  factory LayerAdjust.fromJson(Map<String, dynamic> j) => LayerAdjust(
        dx: (j['dx'] ?? 0).toDouble(),
        dy: (j['dy'] ?? 0).toDouble(),
        scale: (j['scale'] ?? 1).toDouble(),
        hidden: j['hidden'] ?? false,
      );
}

/// Les calques déplaçables, avec leur nom affiché.
const cardLayers = <String, String>{
  'photo': 'Photo',
  'stamp': 'Cachet',
  'logo': 'Logo',
  'emblem': 'Emblème / armoiries',
  'header': 'Texte du haut',
  'title': 'Titre',
  'name': 'Nom en grand (portrait)',
  'info': 'Infos de l\'élève',
  'footer': 'Texte du bas',
  'qr': 'QR code',
};

/// Un modèle enregistré par l'utilisateur (« Mes modèles »).
class SavedTemplate {
  String id;
  String name;
  CardTemplate template;

  /// Infos de l'établissement enregistrées avec le modèle (logo, armoiries, cachet, textes).
  SchoolInfo? school;

  SavedTemplate({String? id, required this.name, required this.template, this.school}) : id = id ?? Student.newId();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'template': template.toJson(),
        if (school != null) 'school': school!.toJson(),
      };

  factory SavedTemplate.fromJson(Map<String, dynamic> j) => SavedTemplate(
        id: j['id'],
        name: j['name'] ?? 'Mon modèle',
        template: CardTemplate.fromJson(Map<String, dynamic>.from(j['template'] ?? {})),
        school: j['school'] == null ? null : SchoolInfo.fromJson(Map<String, dynamic>.from(j['school'])),
      );
}

/// Formats de carte proposés.
class SizePreset {
  final String label;
  final double w;
  final double h;
  const SizePreset(this.label, this.w, this.h);
}

const sizePresets = <SizePreset>[
  SizePreset('Format carte bancaire (CR80) 85,6 × 54 mm', 85.6, 54),
  SizePreset('Badge vertical 54 × 85,6 mm', 54, 85.6),
  SizePreset('Grand format 90 × 60 mm', 90, 60),
  SizePreset('Format A7 paysage 105 × 74 mm', 105, 74),
  SizePreset('Format A7 portrait 74 × 105 mm', 74, 105),
];

/// Mise en page de l'impression.
class PrintLayout {
  bool a4Sheet;
  double marginMm;
  double gapMm;
  bool cutMarks;
  bool onlyValidated;
  String? classFilter;

  PrintLayout({
    this.a4Sheet = true,
    this.marginMm = 6,
    this.gapMm = 3,
    this.cutMarks = true,
    this.onlyValidated = false,
    this.classFilter,
  });

  /// Nombre de colonnes et lignes d'une planche A4 portrait.
  (int cols, int rows) grid(double w, double h) {
    const pw = 210.0, ph = 297.0;
    final cols = ((pw - 2 * marginMm + gapMm) / (w + gapMm)).floor();
    final rows = ((ph - 2 * marginMm + gapMm) / (h + gapMm)).floor();
    return (max(cols, 0), max(rows, 0));
  }
}

/// Résumé d'un projet (un établissement) pour la liste des projets.
class ProjectInfo {
  String id;
  String name;
  String schoolName;
  int studentCount;
  int photoCount;
  DateTime updated;

  ProjectInfo({
    String? id,
    required this.name,
    this.schoolName = '',
    this.studentCount = 0,
    this.photoCount = 0,
    DateTime? updated,
  })  : id = id ?? 'p${Student.newId()}',
        updated = updated ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'schoolName': schoolName,
        'studentCount': studentCount,
        'photoCount': photoCount,
        'updated': updated.toIso8601String(),
      };

  factory ProjectInfo.fromJson(Map<String, dynamic> j) => ProjectInfo(
        id: j['id'],
        name: j['name'] ?? 'Projet',
        schoolName: j['schoolName'] ?? '',
        studentCount: j['studentCount'] ?? 0,
        photoCount: j['photoCount'] ?? 0,
        updated: DateTime.tryParse(j['updated'] ?? ''),
      );
}
