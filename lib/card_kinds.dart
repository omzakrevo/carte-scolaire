import 'models.dart';

/// Type de carte : change le titre, les libellés, les champs affichés et les mots
/// employés dans l'application (élèves, membres, employés…).
/// Chaque type est un module que l'administrateur active dans la licence.
class CardKind {
  final String id;
  final String name;
  final String description;

  /// Mots de l'interface : « Élèves », « élève », « Classe », « Établissement ».
  final String people;
  final String person;
  final String group;
  final String org;
  final String title;
  final String yearLabel;
  final Map<String, String> labels;
  final Set<String> hidden;
  final String design;
  final bool showQr;

  /// Pointage : école (retards, absences, SMS aux parents) ou entreprise (heures de travail).
  final bool company;

  const CardKind({
    required this.id,
    required this.name,
    required this.description,
    required this.people,
    required this.person,
    required this.group,
    required this.org,
    required this.title,
    required this.yearLabel,
    required this.labels,
    required this.hidden,
    required this.design,
    this.showQr = false,
    this.company = false,
  });
}

const cardKinds = <CardKind>[
  CardKind(
    id: 'ecole',
    name: 'Carte scolaire',
    description: 'Élèves d\'une école, d\'un collège ou d\'un lycée',
    people: 'Élèves',
    person: 'élève',
    group: 'Classe',
    org: 'Établissement',
    title: 'CARTE D\'IDENTITÉ SCOLAIRE',
    yearLabel: 'ANNÉE SCOLAIRE',
    labels: defaultLabels,
    hidden: newFields,
    design: 'identite',
  ),
  CardKind(
    id: 'membre',
    name: 'Carte de membre',
    description: 'Association, club, mutuelle, église, syndicat',
    people: 'Membres',
    person: 'membre',
    group: 'Catégorie',
    org: 'Association',
    title: 'CARTE DE MEMBRE',
    yearLabel: 'VALIDITÉ',
    labels: {
      'matricule': 'N° membre',
      'nomPrenom': 'Nom et Prénom',
      'service': 'Fonction',
      'dateNaissance': 'Né(e) le',
      'lieuNaissance': 'À',
      'sexe': 'Sexe',
      'classe': 'Catégorie',
      'contact': 'Téléphone',
      'email': 'E-mail',
      'adresse': 'Adresse',
    },
    hidden: {'service', 'lieuNaissance', 'sexe', 'email', 'adresse'},
    design: 'membre_vague',
    showQr: true,
  ),
  CardKind(
    id: 'pro',
    name: 'Carte professionnelle',
    description: 'Badge d\'employé : entreprise, ONG, administration',
    people: 'Employés',
    person: 'employé',
    group: 'Service',
    org: 'Entreprise',
    title: 'CARTE PROFESSIONNELLE',
    yearLabel: 'VALIDITÉ',
    labels: {
      'matricule': 'Matricule',
      'nomPrenom': 'Nom et Prénom',
      'service': 'Fonction',
      'dateNaissance': 'Né(e) le',
      'lieuNaissance': 'À',
      'sexe': 'Sexe',
      'classe': 'Service',
      'contact': 'Téléphone',
      'email': 'E-mail',
      'adresse': 'Adresse',
    },
    hidden: {'dateNaissance', 'lieuNaissance', 'sexe', 'email', 'adresse'},
    design: 'diagonale',
    showQr: true,
    company: true,
  ),
  CardKind(
    id: 'visiteur',
    name: 'Carte visiteur',
    description: 'Badge numéroté pour les visiteurs d\'un site ou d\'un événement',
    people: 'Badges visiteurs',
    person: 'badge',
    group: 'Zone / service',
    org: 'Structure',
    title: 'VISITEUR',
    yearLabel: '',
    labels: {
      'matricule': 'Badge N°',
      'nomPrenom': 'Nom',
      'service': 'Motif',
      'dateNaissance': 'Date',
      'lieuNaissance': 'Lieu',
      'sexe': 'Sexe',
      'classe': 'Zone autorisée',
      'contact': 'Téléphone',
      'email': 'E-mail',
      'adresse': 'Adresse',
    },
    hidden: {'nomPrenom', 'service', 'dateNaissance', 'lieuNaissance', 'sexe', 'contact', 'email', 'adresse'},
    design: 'visiteur',
    showQr: true,
    company: true,
  ),
  CardKind(
    id: 'visite',
    name: 'Carte de visite',
    description: 'Nom, fonction et coordonnées, avec QR code de contact',
    people: 'Personnes',
    person: 'personne',
    group: 'Service',
    org: 'Entreprise',
    title: '',
    yearLabel: '',
    labels: {
      'matricule': 'Référence',
      'nomPrenom': 'Nom et Prénom',
      'service': 'Fonction',
      'dateNaissance': 'Date de naissance',
      'lieuNaissance': 'Lieu de naissance',
      'sexe': 'Sexe',
      'classe': 'Service',
      'contact': 'Téléphone',
      'email': 'E-mail',
      'adresse': 'Adresse',
    },
    hidden: {'matricule', 'dateNaissance', 'lieuNaissance', 'sexe', 'classe'},
    design: 'visite_bandeau_nom',
    showQr: true,
  ),
];

CardKind kindById(String id) => cardKinds.firstWhere((k) => k.id == id, orElse: () => cardKinds.first);

/// Module de pointage des présences (activé séparément par l'administrateur).
const attendanceModule = 'presence';

/// Module de gestion scolaire : classes, matières, notes, moyennes et bulletins.
const bulletinModule = 'bulletin';

/// Tous les modules, avec leur nom, pour la page administrateur et l'écran licence.
final allModules = <String, String>{
  for (final k in cardKinds) k.id: k.name,
  attendanceModule: 'Pointage des présences',
  bulletinModule: 'Gestion scolaire et bulletins',
};

// ---------------------------------------------------------------------------
// Deux espaces séparés : les établissements scolaires et les entreprises/organisations.

const segmentSchool = 'etablissement';
const segmentCompany = 'entreprise';

String segmentOfKind(String kind) => kind == 'ecole' ? segmentSchool : segmentCompany;

List<CardKind> kindsOfSegment(String segment) =>
    cardKinds.where((k) => segmentOfKind(k.id) == segment).toList();

String segmentName(String segment) => segment == segmentCompany ? 'Entreprises' : 'Établissements';

/// Applique les réglages par défaut d'un type de carte au modèle.
void applyKind(CardTemplate t, CardKind k, {bool changeDesign = true}) {
  t.kind = k.id;
  t.title = k.title;
  t.yearLabel = k.yearLabel;
  t.labels = {...defaultLabels, ...k.labels};
  t.hidden = {...k.hidden};
  t.showQr = k.showQr || t.showQr;
  if (k.id == 'visite' || k.id == 'visiteur') t.showSignature = false;
  if (changeDesign) t.designId = k.design;
  // La plupart des cartes de visite ont un dos : services et photos par défaut.
  if (changeDesign && k.id == 'visite' && !t.hasVerso) t.versoDesign = 'verso_services';
}
