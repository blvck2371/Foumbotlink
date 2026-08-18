import 'package:flutter/material.dart';

/// Modules principaux de Foumbot Link.
enum AppFeatureId {
  infos,
  venteAchat,
  demarches,
  communaute,
  idees,
  mairie,
  notifications,
  profil,
  parametres,
}

class AppFeature {
  const AppFeature({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final AppFeatureId id;
  final String title;
  final String subtitle;
  final IconData icon;

  static const all = <AppFeature>[
    AppFeature(
      id: AppFeatureId.infos,
      title: 'Infos & annonces',
      subtitle: 'Actualités et alertes de la commune',
      icon: Icons.campaign_outlined,
    ),
    AppFeature(
      id: AppFeatureId.venteAchat,
      title: 'Vente & Achat',
      subtitle: 'Marché local entre habitants',
      icon: Icons.storefront_outlined,
    ),
    AppFeature(
      id: AppFeatureId.communaute,
      title: 'Communauté',
      subtitle: 'Échanger entre habitants',
      icon: Icons.forum_outlined,
    ),
    AppFeature(
      id: AppFeatureId.profil,
      title: 'Profil',
      subtitle: 'Compte et informations personnelles',
      icon: Icons.person_outline,
    ),
    AppFeature(
      id: AppFeatureId.parametres,
      title: 'Paramètres',
      subtitle: 'Préférences de l’application',
      icon: Icons.settings_outlined,
    ),
  ];

  static AppFeature byId(AppFeatureId id) =>
      all.firstWhere((f) => f.id == id);
}
