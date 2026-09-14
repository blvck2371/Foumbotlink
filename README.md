# Foumbot Link

Application Flutter avec **Three.js intégré en local** et un **onboarding** immersif en 3D.

## Lancer

```bash
flutter pub get
flutter run
```

## Structure clé

- `assets/threejs/three.min.js` — bibliothèque Three.js locale
- `assets/web/onboarding.html` — scènes 3D d’onboarding
- `assets/web/map_geometry.js` — géométrie vectorielle de la carte
- `lib/` — GetX (navigation, état, thème)

## Configuration Firebase (comptes)

L'authentification (e-mail + téléphone) et les profils utilisateurs
passent par Firebase. `lib/firebase_options.dart` n'est qu'un
placeholder tant que le projet n'est pas configuré — l'app ne se
lancera pas avant cette étape (le reste, y compris `flutter analyze` et
`flutter test`, fonctionne normalement sans elle).

1. Installer les CLI si besoin :
   ```bash
   npm install -g firebase-tools
   dart pub global activate flutterfire_cli
   ```
2. Se connecter (ouvre le navigateur) :
   ```bash
   firebase login
   ```
3. Depuis la racine du projet, générer la vraie configuration :
   ```bash
   flutterfire configure
   ```
   Ça régénère `lib/firebase_options.dart` avec les clés du projet
   Firebase choisi (ou créé) et enregistre les apps Android/iOS/macOS.
4. Dans la [console Firebase](https://console.firebase.google.com), sur
   le projet choisi :
   - **Authentication → Sign-in method** : activer **E-mail/Mot de
     passe** et **Téléphone**.
   - **Firestore Database** : créer la base (mode production).
   - Pour le téléphone sur iOS : configurer une clé APNs
     (Authentication → Sign-in method → Téléphone) sinon la vérification
     retombe sur reCAPTCHA.

## Marché (vente & achat)

Le marché s'appuie sur des règles, des index et des Cloud Functions : une
modification du code Dart seule ne suffit pas, il faut redéployer la
partie serveur.

### Choix de fond

- **L'ordre d'affichage est aléatoire par défaut.** Personne ici ne
  paiera pour remonter en tête de liste ; sans remontée payante, un tri
  chronologique donnerait toute la visibilité au dernier qui a publié.
  Le mélange la rend à tout le monde. L'ordre est stable pendant une
  session (graine tirée au chargement) et se rebat au
  rafraîchissement.
- **Le numéro du vendeur n'est jamais dans le document public.** Il vit
  dans `market/{id}/contact/info`, lisible seulement par un compte
  connecté, et n'est révélé qu'à la demande. Sans ça, une requête
  suffisait à aspirer les numéros de toute la commune.
- **Aucun paiement, aucune option payante.** La transaction se règle en
  main propre : l'app ne peut pas sécuriser un échange, seulement
  prévenir au bon moment (`lib/services/scam_guard.dart`) et donner à
  voir la réputation du vendeur.
- **Une annonce vendue disparaît de la grille** et ne reste que dans
  « Mes annonces ». Une annonce expire au bout de 60 jours et se relance
  gratuitement, autant de fois qu'on veut.

### Déployer

```bash
firebase deploy --only firestore:indexes   # d'abord : la construction prend quelques minutes
firebase deploy --only firestore:rules,storage
firebase deploy --only functions
```

### Rattrapage des annonces existantes

Le modèle a gagné des champs (`bumpedAt`, `expiresAt`, `keywords`,
compteurs) et le numéro a quitté le document public. Une annonce sans
`bumpedAt` ne remonte dans **aucune** requête triée : elle disparaîtrait
du marché sans le moindre message d'erreur.

Le rattrapage tourne tout seul — `repairMarketListings` passe chaque
nuit, et `onMarketItemCreated` complète toute annonce publiée depuis une
version trop ancienne de l'app. Pour ne pas attendre la nuit :

```bash
cd functions && npm run migrate:market -- --dry-run   # puis sans --dry-run
```

Le script demande des identifiants d'administrateur
(`gcloud auth application-default login`). La logique est partagée avec
les Cloud Functions dans `functions/market_backfill.js` : il n'y a
qu'une seule définition de « ce qui manque à une annonce ».

### Tests

```bash
flutter test                       # logique métier, filtres, anti-arnaque
cd functions
npm run test:rules:market          # règles Firestore du marché
npm run test:backfill              # rattrapage, contre l'émulateur
```

Les jetons de recherche sont calculés des deux côtés (Dart et Node) et
doivent produire exactement la même sortie : une divergence rendrait
silencieusement des annonces introuvables. Les deux implémentations sont
couvertes par des tests sur les mêmes entrées.
