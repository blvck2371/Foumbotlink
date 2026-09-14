abstract class AppRoutes {
  static const splash = '/';
  static const onboarding = '/onboarding';
  static const home = '/home';
  static const feature = '/feature';
  static const feedPost = '/feed-post';
  static const savedPosts = '/saved-posts';
  static const compose = '/compose';
  static const auth = '/auth';
  static const market = '/market';
  static const marketDetail = '/market/detail';
  static const marketCompose = '/market/compose';
  static const marketAlerts = '/market/alerts';
  static const userProfile = '/user-profile';
  static const community = '/community';
  static const conversations = '/conversations';
  static const chat = '/chat';
  static const call = '/call';
  static const demarches = '/demarches';
  static const demarcheDetail = '/demarches/detail';

  /// Suivi des dossiers déposés au guichet — la fonctionnalité centrale
  /// de l'app : mon code de suivi et l'état de mes démarches.
  static const dossiers = '/demarches/dossiers';
  static const dossierDetail = '/demarches/dossiers/detail';

  /// Guichet d'une structure validée : réception et avancement.
  static const structureDesk = '/demarches/guichet';

  /// Les démarches qu'une structure publie et tient à jour.
  static const structureDemarches = '/demarches/mes-demarches';
  static const notifications = '/notifications';
  static const settings = '/settings';
}
