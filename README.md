# Foumbot Link

Application communautaire pour les habitants de Foumbot (Flutter + Firebase) :
fil d'actualité, statuts 24 h, messagerie (texte, vocal, photo, vidéo),
appels audio/vidéo WebRTC, marché d'annonces, guide des démarches et suivi
des dossiers déposés auprès des structures, météo locale.

## Architecture

| Dossier | Rôle |
|---|---|
| `lib/services/` | Accès Firebase et logique métier (un service GetX par domaine) |
| `lib/controllers/`, `lib/bindings/` | État des écrans (GetX) |
| `lib/screens/`, `lib/widgets/` | Interface |
| `lib/models/` | Modèles et logique pure (testée dans `test/`) |
| `functions/` | Cloud Functions Node 22 : notifications, appels, modération, marché, contacts, TURN, suppression de compte |
| `firestore.rules`, `storage.rules` | Règles de sécurité (testées dans `functions/scripts/`) |
| `public/` | Pages web publiques (Firebase Hosting) : confidentialité, suppression de compte |
| `assets/web/`, `assets/threejs/` | Onboarding 3D (Three.js local) |

Identifiant Android : `com.foumbotlink.app`. Firebase : projet `foumbotlink`
(déjà configuré — `lib/firebase_options.dart`, `google-services.json`).

## Lancer

```bash
flutter pub get
flutter run
```

## Tests

```bash
flutter analyze && flutter test        # logique Dart
cd functions && npm ci
npm run test:rules:all                 # règles Firestore + rattrapage marché (émulateur)
npm run test:delete-account            # suppression de compte (émulateurs)
```

Les mêmes vérifications tournent en CI (`.github/workflows/ci.yml`).

## Publier sur le Play Store

### Clé d'upload (une seule fois)

```bash
keytool -genkey -v -keystore ~/foumbotlink-upload.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Puis créer `android/key.properties` (**jamais versionné**, voir
`android/.gitignore`) :

```properties
storePassword=…
keyPassword=…
keyAlias=upload
storeFile=/Users/<vous>/foumbotlink-upload.jks
```

Sauvegarder le `.jks` et les mots de passe hors de l'ordinateur : sans eux,
plus aucune mise à jour ne peut être publiée (sauf réinitialisation de la
clé d'upload via le support Google). Sans `key.properties`, le build release
retombe sur la clé de debug — utile en local, refusé par la Play Console.

Ajouter ensuite les empreintes SHA-1/SHA-256 de la clé d'upload **et** de la
clé de signature Play (Play Console → Intégrité de l'app) à l'app Android
dans la console Firebase, sinon la connexion par téléphone échoue sur les
installations venant du Play Store.

### Build

```bash
flutter build appbundle --release   # → build/app/outputs/bundle/release/app-release.aab
```

Incrémenter le numéro après le `+` de `version:` dans `pubspec.yaml` à
chaque envoi (c'est le `versionCode`).

### Publication automatique (Codemagic)

Chaque push sur `main` lance `codemagic.yaml` : analyse, tests, build signé
avec la clé d'upload, puis envoi en brouillon sur la piste de test interne
de Google Play. Le `versionCode` est calculé automatiquement (dernier
publié + 1). Configuration dans Codemagic :

- **Android keystores** : la clé d'upload, nom de référence `foumbotlink_upload` ;
- **Variables d'environnement**, groupe `google_play` :
  `GCLOUD_SERVICE_ACCOUNT_CREDENTIALS` = JSON du compte de service ayant
  accès à l'app dans la Play Console.

Le tout premier `.aab` doit être envoyé à la main dans la Play Console
(l'API Google Play refuse une app qui n'a encore aucune version).

### Fiche Play Store

- Politique de confidentialité : https://foumbotlink.web.app/confidentialite
- Suppression de compte : https://foumbotlink.web.app/suppression-compte
  (dans l'app : menu → *Supprimer mon compte*)

## Appels : serveur TURN

Sans relais TURN, deux téléphones en 4G/5G ne s'entendent souvent pas. La
fonction `getIceServers` fournit à l'app des identifiants Cloudflare
temporaires (12 h) ; le jeton ne quitte jamais le serveur.

1. Cloudflare → Realtime → TURN Server → créer une clé.
2. ```bash
   firebase functions:secrets:set CLOUDFLARE_TURN_KEY_ID
   firebase functions:secrets:set CLOUDFLARE_TURN_API_TOKEN
   firebase deploy --only functions:getIceServers
   ```

Tant que ce n'est pas fait, l'app retombe sur `config/webrtc` (Firestore),
puis sur des serveurs publics de démonstration.

## Déployer le backend

```bash
firebase deploy --only firestore:indexes      # d'abord : la construction prend quelques minutes
firebase deploy --only firestore:rules,storage
firebase deploy --only functions
firebase deploy --only hosting
```

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
