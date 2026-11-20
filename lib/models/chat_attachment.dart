/// Règles des pièces jointes de discussion, sans dépendance Firebase :
/// type MIME, nom de stockage, plafonds. Tenues ici pour être vérifiables
/// en test, et partagées par l'envoi (`ChatService`) et l'affichage.
class ChatAttachment {
  ChatAttachment._();

  /// Plafond des pièces jointes hors vidéo — le même que la règle Storage
  /// `chat/` (20 Mo). Vérifié **avant** l'envoi : sinon le fichier monte
  /// en entier pour finir sur un « unauthorized » qui n'explique rien.
  static const maxFileBytes = 20 * 1024 * 1024;

  /// Plafond d'une vidéo, aligné sur la règle Storage (60 Mo).
  static const maxVideoBytes = 60 * 1024 * 1024;

  static const _types = {
    // Documents
    'pdf': 'application/pdf',
    'doc': 'application/msword',
    'docx':
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls': 'application/vnd.ms-excel',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'ppt': 'application/vnd.ms-powerpoint',
    'pptx':
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'odt': 'application/vnd.oasis.opendocument.text',
    'ods': 'application/vnd.oasis.opendocument.spreadsheet',
    'txt': 'text/plain',
    'csv': 'text/csv',
    'rtf': 'application/rtf',
    'zip': 'application/zip',
    'rar': 'application/vnd.rar',
    '7z': 'application/x-7z-compressed',
    'apk': 'application/vnd.android.package-archive',
    // Images
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'heic': 'image/heic',
    'heif': 'image/heif',
    // Audio
    'm4a': 'audio/mp4',
    'aac': 'audio/aac',
    'mp3': 'audio/mpeg',
    'wav': 'audio/wav',
    'ogg': 'audio/ogg',
    'opus': 'audio/ogg',
    'amr': 'audio/amr',
    // Vidéo
    'mp4': 'video/mp4',
    'mov': 'video/quicktime',
    'qt': 'video/quicktime',
    'm4v': 'video/x-m4v',
    'webm': 'video/webm',
    '3gp': 'video/3gpp',
  };

  /// Extension en minuscules, sans le point ; vide s'il n'y en a pas.
  static String extensionOf(String name) {
    final base = name.split(RegExp(r'[/\\]')).last;
    final dot = base.lastIndexOf('.');
    if (dot <= 0 || dot == base.length - 1) return '';
    return base.substring(dot + 1).toLowerCase();
  }

  /// Type MIME réel, d'après l'extension. Sans lui, Storage sert le
  /// fichier en `application/octet-stream` : le téléphone d'en face ne
  /// sait alors pas qu'un PDF est un PDF, ni qu'un vocal se lit.
  static String contentTypeFor(String name) =>
      _types[extensionOf(name)] ?? 'application/octet-stream';

  /// Type d'une photo de discussion. Le sélecteur recompresse en JPEG la
  /// plupart des photos, mais une capture d'écran reste en PNG : l'annoncer
  /// en JPEG tromperait le décodeur d'en face.
  static String imageContentTypeFor(String path) {
    final type = contentTypeFor(path);
    return type.startsWith('image/') ? type : 'image/jpeg';
  }

  /// Nom de fichier sûr pour un chemin Storage.
  ///
  /// Le nom d'origine part tel quel dans le message (`fileName`), c'est
  /// lui qu'on affiche ; celui-ci ne sert qu'au chemin. Un `#`, un `?`,
  /// un `/` ou des accents y cassaient l'URL de téléchargement ou
  /// créaient des sous-dossiers fantômes.
  static String safeStorageName(String name) {
    final ext = extensionOf(name);
    final base = name.split(RegExp(r'[/\\]')).last;
    var stem = ext.isEmpty ? base : base.substring(0, base.length - ext.length - 1);
    stem = _stripAccents(stem)
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^[._]+|[._]+$'), '');
    if (stem.isEmpty) stem = 'document';
    if (stem.length > 60) stem = stem.substring(0, 60);
    final safeExt = RegExp(r'^[a-z0-9]{1,8}$').hasMatch(ext) ? ext : '';
    return safeExt.isEmpty ? stem : '$stem.$safeExt';
  }

  static const _accents = {
    'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'ç': 'c', 'é': 'e', 'è': 'e',
    'ê': 'e', 'ë': 'e', 'î': 'i', 'ï': 'i', 'í': 'i', 'ô': 'o', 'ö': 'o',
    'ó': 'o', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ú': 'u', 'ÿ': 'y', 'ñ': 'n',
    'œ': 'oe', 'æ': 'ae',
  };

  static String _stripAccents(String input) {
    final out = StringBuffer();
    for (final ch in input.split('')) {
      final lower = ch.toLowerCase();
      final plain = _accents[lower];
      if (plain == null) {
        out.write(ch);
      } else {
        out.write(ch == lower ? plain : plain.toUpperCase());
      }
    }
    return out.toString();
  }

  /// En-tête `Content-Disposition` : le navigateur ou la visionneuse qui
  /// ouvre le fichier le nomme comme l'expéditeur l'a nommé, accents
  /// compris (RFC 6266 / 5987).
  static String contentDispositionFor(String name) {
    final ascii = safeStorageName(name);
    final encoded = Uri.encodeComponent(name.split(RegExp(r'[/\\]')).last);
    return "inline; filename=\"$ascii\"; filename*=UTF-8''$encoded";
  }

  /// « 1,2 Mo », « 340 Ko ».
  static String sizeLabel(int bytes) {
    if (bytes >= 1024 * 1024) {
      final mb = bytes / (1024 * 1024);
      return '${mb.toStringAsFixed(mb >= 10 ? 0 : 1).replaceAll('.', ',')} Mo';
    }
    final kb = (bytes / 1024).ceil();
    return '${kb < 1 ? 1 : kb} Ko';
  }

  /// Libellé court affiché dans la bulle : « PDF », « DOCX »…
  static String badgeFor(String? name) {
    final ext = extensionOf(name ?? '');
    return ext.isEmpty || ext.length > 4 ? 'FICHIER' : ext.toUpperCase();
  }
}

/// Fichier refusé avant même de partir parce qu'il dépasse le plafond.
///
/// Son `toString()` est ce que la personne lit dans l'alerte d'échec.
class ChatFileTooLarge implements Exception {
  const ChatFileTooLarge({
    required this.bytes,
    required this.maxBytes,
    this.what = 'Fichier',
  });

  final int bytes;
  final int maxBytes;
  final String what;

  @override
  String toString() =>
      '$what de ${ChatAttachment.sizeLabel(bytes)} : le maximum est '
      '${ChatAttachment.sizeLabel(maxBytes)}.';
}
