/// Palette Foumbot Link : orange · blanc · noir
library;

import 'package:flutter/material.dart';

class AppColors {
  static const black = Color(0xFF0A0A0A);
  static const blackSoft = Color(0xFF161616);
  static const blackElevated = Color(0xFF1F1F1F);
  static const white = Color(0xFFFFFFFF);
  static const whiteSoft = Color(0xFFF5F5F5);
  static const whiteMuted = Color(0xFFB3B3B3);
  static const gray = Color(0xFF6B6B6B);
  static const orange = Color(0xFFEF6C00);
  static const orangeDeep = Color(0xFFC65100);
  static const orangeSoft = Color(0xFFFFA040);
  /// Orange assez profond pour porter du texte blanc (5,18:1) **et** pour
  /// être lu sur fond clair (5,18:1 sur blanc, 4,75:1 sur [whiteSoft]).
  /// [orange] échoue dans les deux sens, à 3,08:1 et 2,83:1 : à réserver
  /// aux aplats décoratifs, et à remplacer par celui-ci dès qu'un texte ou
  /// une icône doit rester lisible — pastille de non-lus, mention en
  /// couleur sur fond clair.
  static const orangeReadable = Color(0xFFC2410C);

  /// Accent secondaire (onboarding) — l’UI principale reste orange · blanc · noir
  static const blue = Color(0xFF1E88E5);

  /// Rouge d'erreur. Volontairement distinct de l'orange de marque : un
  /// échec ne doit jamais porter la couleur de l'action principale —
  /// c'était le cas sur l'écran de connexion, où le message d'erreur
  /// ressemblait à un accent graphique.
  static const danger = Color(0xFFD32F2F);

  /// Vert de confirmation, pour distinguer d'un coup d'œil « c'est
  /// parti » de « ça a échoué ». Les deux partageaient la même couleur.
  static const success = Color(0xFF2E7D32);

  /// Rouge « en direct » des lives : le code universel du direct, distinct
  /// de l'orange de la marque et du rouge d'erreur.
  static const live = Color(0xFFE5263D);

  // ---------------------------------------------------------------------
  // Bulles de conversation
  //
  // L'orange vif servait de fond aux messages envoyés : le texte blanc n'y
  // atteignait que 3,08:1, sous le seuil AA de 4,5:1 exigé par du texte
  // courant — et les coches de lecture bleues tombaient à 1,19:1, donc
  // invisibles. Un message se lit longtemps et en petit : la bulle utilise
  // désormais une teinte orange claire (thème clair) ou un brun brûlé
  // (thème sombre), où l'encre dépasse 10:1 tout en gardant l'identité
  // chaude de l'app. Chaque valeur ci-dessous a été mesurée.
  // ---------------------------------------------------------------------

  /// Fond des messages envoyés. Encre : [bubbleInkLight] — 12,79:1.
  static const bubbleMineLight = Color(0xFFFFE9D6);

  /// Fond des messages envoyés, thème sombre. Encre : blanc — 10,16:1.
  static const bubbleMineDark = Color(0xFF6B3105);

  /// Encre des messages envoyés en thème clair : un brun profond plutôt
  /// qu'un noir pur, qui jurerait sur une tuile chaude.
  static const bubbleInkLight = Color(0xFF3D1F08);

  /// Horodatage et mentions secondaires — 5,82:1 sur [bubbleMineLight].
  static const bubbleMetaLight = Color(0xFF8A4A16);

  /// Horodatage et mentions secondaires — 6,59:1 sur [bubbleMineDark].
  static const bubbleMetaDark = Color(0xFFF0C9A6);

  /// Barre de citation, échec d'envoi. 5,35:1 sur la tuile claire, 5,76:1
  /// sur une surface claire neutre — là où l'orange vif échouait à 2,83:1.
  static const bubbleAccentLight = Color(0xFFB3300B);

  /// Équivalent sombre — 5,76:1 sur [bubbleMineDark].
  static const bubbleAccentDark = Color(0xFFFFB27A);

  /// Coches « lu ». Le bleu du thème est trop clair sur une tuile chaude
  /// (3,13:1) : assombri ici à 4,89:1.
  static const bubbleReadLight = Color(0xFF1565C0);

  /// Équivalent sombre — 4,59:1 sur [bubbleMineDark].
  static const bubbleReadDark = Color(0xFF64B5F6);
}
