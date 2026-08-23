import 'package:flutter/material.dart';

/// Modules principaux de Foumbot Link.
enum AppFeatureId {
  infos,
  venteAchat,
  demarches,
  communaute,
  messages,
  idees,
  notifications,
  profil,
  parametres,
}

/// Regroupement des modules dans le tiroir — pour que le menu ait une
/// hiérarchie lisible au lieu d'une liste plate mélangeant fil,
/// services municipaux et compte.
enum AppFeatureSection {
  /// Fil, échanges et vie communautaire.
  community,

  /// Démarches administratives portées par la mairie.
  municipalServices,

  /// Compte et préférences de l'utilisateur.
  account,
}

class AppFeature {
  const AppFeature({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.section,
  });

  final AppFeatureId id;
  final String title;
  final String subtitle;
  final IconData icon;
  final AppFeatureSection section;

  static const all = <AppFeature>[
    AppFeature(
      id: AppFeatureId.infos,
      title: 'Infos & annonces',
      subtitle: 'Actualités et alertes de la commune',
      icon: Icons.campaign_outlined,
      section: AppFeatureSection.community,
    ),
    AppFeature(
      id: AppFeatureId.communaute,
      title: 'Communauté',
      subtitle: 'Échanger entre habitants',
      icon: Icons.people_outlined,
      section: AppFeatureSection.community,
    ),
    AppFeature(
      id: AppFeatureId.messages,
      title: 'Messages',
      subtitle: 'Discuter avec les membres',
      icon: Icons.chat_outlined,
      section: AppFeatureSection.community,
    ),
    AppFeature(
      id: AppFeatureId.idees,
      title: 'Idées & initiatives',
      subtitle: 'Partager et soutenir des projets',
      icon: Icons.lightbulb_outline,
      section: AppFeatureSection.community,
    ),
    AppFeature(
      id: AppFeatureId.venteAchat,
      title: 'Vente & Achat',
      subtitle: 'Marché local entre habitants',
      icon: Icons.storefront_outlined,
      section: AppFeatureSection.community,
    ),
    AppFeature(
      id: AppFeatureId.demarches,
      title: 'Démarches',
      subtitle: 'Services et formalités administratives',
      icon: Icons.assignment_outlined,
      section: AppFeatureSection.municipalServices,
    ),
    AppFeature(
      id: AppFeatureId.notifications,
      title: 'Notifications',
      subtitle: 'Alertes et messages reçus',
      icon: Icons.notifications_outlined,
      section: AppFeatureSection.account,
    ),
    AppFeature(
      id: AppFeatureId.profil,
      title: 'Profil',
      subtitle: 'Compte et informations personnelles',
      icon: Icons.person_outline,
      section: AppFeatureSection.account,
    ),
    AppFeature(
      id: AppFeatureId.parametres,
      title: 'Paramètres',
      subtitle: 'Préférences de l’application',
      icon: Icons.settings_outlined,
      section: AppFeatureSection.account,
    ),
  ];

  static AppFeature byId(AppFeatureId id) =>
      all.firstWhere((f) => f.id == id);
}
