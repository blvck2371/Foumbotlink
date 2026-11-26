import 'package:flutter/foundation.dart' show kIsWeb;

/// L'adresse à charger pour une image réseau.
///
/// Web uniquement : les photos Storage sont servies avec un cache d'un an
/// (`immutable`). Un navigateur qui les a reçues avant que le bucket
/// n'autorise les navigateurs (CORS) a gardé cette copie sans autorisation
/// et la réutilise — l'image reste bloquée chez lui, alors qu'elle passe
/// partout ailleurs. Un paramètre en plus change la clé de cache : la
/// photo est redemandée une fois, proprement, puis gardée comme avant.
/// Storage ignore ce paramètre ; sur mobile, rien ne change.
String displayImageUrl(String url) {
  if (!kIsWeb || !url.contains('firebasestorage.googleapis.com')) return url;
  return url.contains('?') ? '$url&web=1' : '$url?web=1';
}
