import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:foumbotlik/theme/app_colors.dart';

/// Luminance relative d'une couleur opaque (WCAG 2.1).
double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) +
      0.7152 * channel(c.g) +
      0.0722 * channel(c.b);
}

/// Rapport de contraste entre deux couleurs opaques, de 1 à 21.
double contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// Composition d'une couleur translucide sur un fond opaque — plusieurs
/// éléments d'une bulle dérivent de l'encre par transparence.
Color _over(Color fg, double alpha, Color bg) => Color.fromARGB(
  255,
  ((fg.r * alpha + bg.r * (1 - alpha)) * 255).round(),
  ((fg.g * alpha + bg.g * (1 - alpha)) * 255).round(),
  ((fg.b * alpha + bg.b * (1 - alpha)) * 255).round(),
);

/// Seuil AA pour du texte courant.
const _texte = 4.5;

/// Seuil AA pour un élément graphique ou un composant d'interface.
const _graphique = 3.0;

void main() {
  // Le fond des messages envoyés a été l'orange vif du thème : le texte
  // blanc n'y atteignait que 3,08:1 et les coches de lecture 1,19:1, d'où
  // des messages illisibles. Ces contrôles empêchent qu'une retouche de
  // palette y ramène l'app sans qu'on s'en aperçoive.
  group('Lisibilité des bulles de conversation', () {
    test('l’orange vif du thème ne convient pas comme fond de message', () {
      // Constat qui justifie la palette dédiée : si un jour ce rapport
      // repassait au-dessus du seuil, la teinte dédiée deviendrait
      // discutable — mais tant qu'il échoue, elle est nécessaire.
      expect(contrast(AppColors.orange, AppColors.white), lessThan(_texte));
    });

    test('texte des messages envoyés, thème clair', () {
      expect(
        contrast(AppColors.bubbleMineLight, AppColors.bubbleInkLight),
        greaterThanOrEqualTo(_texte),
      );
    });

    test('texte des messages envoyés, thème sombre', () {
      expect(
        contrast(AppColors.bubbleMineDark, AppColors.white),
        greaterThanOrEqualTo(_texte),
      );
    });

    test('horodatage et mentions secondaires', () {
      expect(
        contrast(AppColors.bubbleMineLight, AppColors.bubbleMetaLight),
        greaterThanOrEqualTo(_texte),
      );
      expect(
        contrast(AppColors.bubbleMineDark, AppColors.bubbleMetaDark),
        greaterThanOrEqualTo(_texte),
      );
    });

    test('accent : barre de citation, échec d’envoi', () {
      expect(
        contrast(AppColors.bubbleMineLight, AppColors.bubbleAccentLight),
        greaterThanOrEqualTo(_texte),
      );
      expect(
        contrast(AppColors.bubbleMineDark, AppColors.bubbleAccentDark),
        greaterThanOrEqualTo(_texte),
      );
    });

    test('coches « lu »', () {
      expect(
        contrast(AppColors.bubbleMineLight, AppColors.bubbleReadLight),
        greaterThanOrEqualTo(_texte),
      );
      expect(
        contrast(AppColors.bubbleMineDark, AppColors.bubbleReadDark),
        greaterThanOrEqualTo(_texte),
      );
    });

    test('bulle du correspondant', () {
      expect(
        contrast(AppColors.whiteSoft, AppColors.black),
        greaterThanOrEqualTo(_texte),
      );
      expect(
        contrast(AppColors.blackElevated, AppColors.white),
        greaterThanOrEqualTo(_texte),
      );
      expect(
        contrast(AppColors.whiteSoft, AppColors.bubbleAccentLight),
        greaterThanOrEqualTo(_texte),
      );
    });

    test('extrait cité, posé sur un fond creusé dans la bulle', () {
      final insetClair = _over(
        AppColors.bubbleInkLight,
        0.07,
        AppColors.bubbleMineLight,
      );
      final insetSombre = _over(
        AppColors.white,
        0.07,
        AppColors.bubbleMineDark,
      );
      expect(
        contrast(insetClair, AppColors.bubbleMetaLight),
        greaterThanOrEqualTo(_texte),
      );
      expect(
        contrast(insetSombre, AppColors.bubbleMetaDark),
        greaterThanOrEqualTo(_texte),
      );
      expect(
        contrast(insetClair, AppColors.bubbleAccentLight),
        greaterThanOrEqualTo(_texte),
      );
      expect(
        contrast(insetSombre, AppColors.bubbleAccentDark),
        greaterThanOrEqualTo(_texte),
      );
    });

    test('onde du message vocal au repos', () {
      // L'onde est ce qui signale un message vocal : elle doit rester
      // perceptible même à l'arrêt (voir _buildVoice, opacité 0,55).
      final ondeClaire = _over(
        AppColors.bubbleInkLight,
        0.55,
        AppColors.bubbleMineLight,
      );
      final ondeSombre = _over(
        AppColors.white,
        0.55,
        AppColors.bubbleMineDark,
      );
      expect(
        contrast(AppColors.bubbleMineLight, ondeClaire),
        greaterThanOrEqualTo(_graphique),
      );
      expect(
        contrast(AppColors.bubbleMineDark, ondeSombre),
        greaterThanOrEqualTo(_graphique),
      );
    });

    test('les deux bulles restent distinctes en thème clair', () {
      // Elles sont toutes deux claires : sans écart perceptible, seule
      // l'alignement distinguerait l'expéditeur.
      final ecart = (_luminance(AppColors.bubbleMineLight) -
              _luminance(AppColors.whiteSoft))
          .abs();
      expect(ecart, greaterThan(0.02));
    });
  });
}
