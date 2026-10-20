# Carte Scolaire

Application Flutter pour créer et imprimer les cartes scolaires d'un établissement.
Fonctionne sur **Android, iPhone, Windows, macOS et Linux**, sans connexion Internet.

## Télécharger

- **APK Android** : [carte-scolaire.apk](https://github.com/omzakrevo/carte-scolaire/releases/latest/download/carte-scolaire.apk), compilé automatiquement à chaque mise à jour du code (onglet *Actions*, publié dans *Releases*).
- **Site de présentation** : https://omzakrevo.github.io/carte-scolaire/ (dossier `docs/`, publié par GitHub Pages).

## Déroulement

1. **Modèle** : choisir parmi 10 modèles, régler les dimensions (formats prédéfinis ou personnalisés en mm, paysage ou portrait), les couleurs et les informations de l'établissement (logo, armoiries, cachet, nom, devise, pays, devise nationale, ministère, région/province, signataire).
   - **Modifier le modèle** : titre de la carte, texte de l'année, libellé de chaque champ (renommer « Personne à prévenir » en « Contact », etc.), champs affichés ou masqués, taille du texte et de la photo, cachet, signataire, QR code.
   - **Mes modèles** : enregistrer les réglages d'un établissement, les réappliquer, les renommer, les exporter en fichier `.carte.json` et les importer sur un autre appareil.
   - **Fond personnalisé** : importer un fond créé dans Photoshop/Illustrator ; la photo et les infos de l'élève se placent par-dessus (espaces réservés en haut et en bas réglables).
2. **Élèves** : importer la liste depuis Excel (.xlsx) ou CSV, ou saisir les élèves un par un.
3. **Photos** : carte par carte, ajouter la photo puis valider.
   - Téléphone / tablette : *Prendre la photo* (caméra) ou *Galerie*.
   - Ordinateur : *Choisir un fichier* ou *Caméra du téléphone* (voir plus bas).
   - Les photos sont automatiquement recadrées au format identité 3:4.
4. **Impression** : PDF en **planche A4** (10 cartes par feuille au format CR80, traits de coupe, marges réglables) ou en **cartes individuelles** au format exact (imprimante à cartes PVC). Filtre par classe et par cartes validées. Le PDF s'imprime, s'enregistre ou se partage directement depuis l'application.

Le projet est enregistré automatiquement sur l'appareil (liste, photos, réglages).

## Modèles inclus

| Modèle | Style |
|---|---|
| Identité scolaire | En-tête officiel (pays, devise, ministère, région), titre rouge, vague avec nom et devise de l'école |
| Officiel tricolore | En-tête pays + ministère, drapeau, bandeau titre, liseré tricolore |
| Classique bandeau | Bandeau dégradé avec logo, pied avec année scolaire |
| Moderne diagonale | Formes obliques dans les angles |
| Vagues | En-tête ondulé |
| Badge vertical | Portrait 54 × 85,6 mm, photo ronde, emplacement pour lanière |
| Épuré | Barre latérale, beaucoup de blanc |
| Prestige | Fond bleu nuit, filet doré |
| Cahier d'écolier | Lignes et marge rouge, pour le primaire |
| Fond personnalisé | Votre propre fond graphique, infos de l'élève par-dessus |

Tous les modèles affichent les mêmes champs : Matricule, Nom et Prénom, Date de naissance, Lieu de naissance, Sexe, Classe, Personne à prévenir, avec le cachet sur la photo et le nom du signataire dessous. Chaque modèle s'adapte au paysage et au portrait.

## Caméra du téléphone sur la version ordinateur

Sur Windows / macOS / Linux, le bouton **Caméra du téléphone** démarre un petit serveur local et affiche un QR code :

1. Le téléphone est connecté au **même Wi-Fi** que l'ordinateur (ou l'ordinateur est connecté au partage de connexion du téléphone).
2. On scanne le QR code avec l'appareil photo du téléphone : une page s'ouvre dans le navigateur, **aucune application à installer**.
3. *Prendre la photo* : la photo arrive directement sur la carte de l'élève affiché à l'écran, et l'application passe à l'élève suivant (option désactivable).
4. Le téléphone affiche le nom de l'élève en cours et peut naviguer (Précédent / Suivant).

Le lien contient une clé aléatoire : seuls les téléphones qui ont scanné le QR code peuvent envoyer des photos.
Sous Windows, accepter la demande du pare-feu (réseaux privés) au premier lancement.


## Projets

Un projet par établissement (onglet **Projets**) : modèle, établissement, élèves et photos sont gardés séparément. Créer, ouvrir, renommer, dupliquer, supprimer.

## Disposition des éléments

Dans **Modèle → Déplacer et redimensionner les éléments** : touchez un élément (photo, logo, armoiries, cachet, texte du haut, titre, infos de l'élève, texte du bas, QR code) puis glissez-le ; pincez ou utilisez le curseur pour l'agrandir ou le réduire. Chaque élément peut aussi être masqué.

## Photos

- **Recadrage** : après chaque photo, un écran de cadrage au format de la carte (3:4) avec un gabarit (ovale du visage, ligne des yeux). Le bouton **Recadrer** permet de refaire le cadrage plus tard à partir de la photo d'origine.
- **Appareil photo guidé** (Android, iPhone) : la prise de vue se fait directement dans le cadre de la carte, visage dans l'ovale.

## Modèles partageables

**Mes modèles → Exporter en fichier ZIP** produit `modele.json` + `fond.jpg`, `logo.png`, `armoiries.png`, `cachet.png`. **Ajouter un modèle** accepte ce ZIP (ou un `.carte.json`). Un ZIP contenant seulement `fond.png` (et éventuellement `logo.png`, `cachet.png`…) crée directement un modèle « Fond personnalisé ».

## Licences et mot de passe

- Au premier lancement, l'utilisateur choisit un **mot de passe** ; l'application se verrouille à chaque ouverture.
- Sans licence, l'application fonctionne en **version d'essai** : les cartes générées portent le filigrane « VERSION D'ESSAI ».
- Une licence (1, 3, 6 mois, 1 an ou définitive) est un **code signé** lié à l'identifiant de l'appareil. Il est vérifié sur le téléphone, sans base de données : la signature se fait avec une clé privée que seul l'administrateur possède (jamais publiée sur GitHub).
- **Page administrateur** : https://omzakrevo.github.io/carte-scolaire/admin/ — attribuer, révoquer, codes de réinitialisation du mot de passe, sauvegarde. Elle publie `licenses/registry.json` (révocations) que l'application consulte quand elle a Internet.

## Format du fichier Excel

Le fichier `modele_liste_eleves.xlsx` sert d'exemple. Les colonnes sont reconnues d'après leur titre, dans n'importe quel ordre :
`Matricule`, `Nom` (ou `Nom et prénoms` dans une seule colonne), `Prénom(s)`, `Classe`, `Date de naissance`, `Lieu de naissance`, `Sexe`, `Personne à prévenir` (ou `Contact`, `Téléphone`).
Seule la colonne **Nom** est obligatoire. Une ligne de titre au-dessus des en-têtes (ex. « LISTE DE LA CLASSE ») est ignorée.

## Lancer le projet

Prérequis : Flutter 3.24 ou plus récent.

```bash
flutter pub get
flutter run                 # appareil connecté
flutter run -d windows      # version ordinateur
flutter build apk --release # Android
flutter build windows       # exécutable Windows
```

## Organisation du code

```
lib/
  main.dart                  navigation (rail sur ordinateur, barre en bas sur téléphone)
  app_state.dart             état global + sauvegarde automatique
  models.dart                élève, établissement, modèle de carte, mise en page
  designs/card_designs.dart  les 10 modèles (un seul rendu pour l'aperçu et le PDF)
  screens/                   modèle, élèves, photos, impression
  services/
    student_import.dart      lecture Excel / CSV
    photo_utils.dart         recadrage 3:4, logo, conversion JPEG
    phone_bridge.dart        serveur local pour la caméra du téléphone
    pdf_export.dart          rendu ~300 dpi, planche A4, traits de coupe
    storage.dart             enregistrement sur l'appareil
test/                        rendus des 8 modèles, import Excel/CSV, PDF, parcours complet
```

Ajouter un modèle : écrire une fonction `Widget _monModele(CardCtx c)` dans `card_designs.dart` et l'ajouter à la liste `cardDesigns`. Les briques `c.photo`, `c.info`, `c.qr`, `c.logo` et `c.body` gèrent la mise en page paysage/portrait.
