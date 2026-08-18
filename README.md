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
