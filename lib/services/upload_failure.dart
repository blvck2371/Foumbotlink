import 'package:firebase_core/firebase_core.dart';

/// Ce qu'un échec de publication dit vraiment.
///
/// Les deux écrans de rédaction (publication du fil, annonce du marché)
/// affichaient « Vérifiez votre connexion » pour n'importe quelle
/// exception — ce qui envoyait chercher un problème de réseau là où
/// c'était un refus de droits Storage, un fichier trop lourd ou un envoi
/// trop long, et rendait le vrai problème introuvable.
///
/// Le code Firebase reste dans le message pour les cas non identifiés :
/// c'est la seule prise que la personne puisse nous rapporter.
String uploadFailureMessage(Object error) {
  if (error is! FirebaseException) {
    return 'Vérifiez votre connexion puis réessayez.';
  }
  return switch (error.code) {
    'unauthorized' || 'permission-denied' =>
      'Vos droits ne permettent pas d’envoyer ces photos '
          '(${error.code}). Reconnectez-vous puis réessayez.',
    'retry-limit-exceeded' || 'canceled' =>
      'L’envoi des photos a pris trop de temps. Réessayez, ou publiez '
          'avec moins de photos si la connexion est faible.',
    'quota-exceeded' =>
      'L’espace de stockage est saturé (${error.code}). Signalez-le à '
          'l’équipe.',
    'unavailable' || 'deadline-exceeded' =>
      'Le serveur n’a pas répondu à temps. Vérifiez votre connexion puis '
          'réessayez.',
    _ =>
      'Échec de l’envoi (${error.plugin} · ${error.code}). Réessayez dans '
          'un instant.',
  };
}
