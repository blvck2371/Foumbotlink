import 'dart:io' show File;
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:video_player/video_player.dart';

/// Un média choisi sur l'appareil, avant son envoi, sur mobile **et** sur
/// le web.
///
/// Sur mobile, `image_picker`/`file_picker` rendent un chemin de fichier ;
/// dans un navigateur, il n'y a pas de système de fichiers : c'est une
/// adresse `blob:` qui pointe vers le fichier en mémoire. `File` (dart:io)
/// n'y fonctionne pas. Tout ce qui lit, affiche ou envoie un média local
/// passe donc par ici plutôt que par `File(path)`.
abstract final class LocalMedia {
  /// Un chemin local (fichier mobile ou `blob:` web), par opposition à une
  /// URL déjà envoyée (https://…).
  static bool isLocal(String pathOrUrl) =>
      pathOrUrl.isNotEmpty && !pathOrUrl.startsWith('http');

  /// Image à afficher depuis un média local.
  static ImageProvider image(String path) =>
      kIsWeb ? NetworkImage(path) : FileImage(File(path)) as ImageProvider;

  /// Lecteur vidéo sur un média local.
  static VideoPlayerController video(String path) => kIsWeb
      ? VideoPlayerController.networkUrl(Uri.parse(path))
      : VideoPlayerController.file(File(path));

  /// Taille en octets.
  static Future<int> length(String path) => XFile(path).length();

  static Future<Uint8List> bytes(String path) => XFile(path).readAsBytes();

  /// Le média existe encore (un `blob:` ne survit pas au rechargement de
  /// la page ; un fichier mobile peut avoir été nettoyé).
  static Future<bool> exists(String path) async {
    if (kIsWeb) {
      try {
        await XFile(path).length();
        return true;
      } on Object {
        return false;
      }
    }
    return File(path).exists();
  }

  /// Lance l'envoi du média vers Storage. Mobile : depuis le fichier, en
  /// flux ; web : depuis la mémoire (les octets sont lus d'abord). La
  /// tâche rendue se suit (`snapshotEvents`) ou s'attend comme d'habitude.
  static Future<UploadTask> upload(
    Reference ref,
    String path, [
    SettableMetadata? metadata,
  ]) async {
    if (!kIsWeb) return ref.putFile(File(path), metadata);
    return ref.putData(await bytes(path), metadata);
  }
}
