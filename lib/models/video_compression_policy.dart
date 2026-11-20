/// Quand compresser une vidéo avant l'envoi, et quand garder le résultat.
///
/// Sans dépendance native, pour être vérifiable en test : la compression
/// elle-même vit dans `VideoCompressionService`.
class VideoCompressionPolicy {
  VideoCompressionPolicy._();

  /// En dessous, la vidéo est déjà légère (quelques secondes, ou déjà
  /// compressée par l'appareil) : la réencoder coûterait du temps et de
  /// la batterie pour rien, et dégraderait l'image.
  static const skipBelowBytes = 4 * 1024 * 1024;

  /// Gain minimal pour garder la version compressée : en dessous de 10 %,
  /// on perd en qualité sans rien gagner de visible sur le forfait.
  static const minSavingRatio = 0.10;

  static bool shouldCompress(int originalBytes) =>
      originalBytes >= skipBelowBytes;

  /// Vrai si la version compressée vaut la peine d'être envoyée à la
  /// place de l'original. Une compression ratée (`null`, fichier vide) ou
  /// qui grossit le fichier — ça arrive sur une vidéo déjà très
  /// compressée — retombe sur l'original.
  static bool keepCompressed({required int originalBytes, int? compressedBytes}) {
    if (compressedBytes == null || compressedBytes <= 0) return false;
    return compressedBytes <= originalBytes * (1 - minSavingRatio);
  }

  /// « 82 Mo → 12 Mo » : affiché nulle part pour l'instant, mais tracé
  /// dans les journaux pour juger le réglage sur de vrais téléphones.
  static String savingLabel(int originalBytes, int sentBytes) {
    String mb(int b) => (b / (1024 * 1024)).toStringAsFixed(1);
    final pct = originalBytes == 0
        ? 0
        : (100 - sentBytes * 100 / originalBytes).round();
    return '${mb(originalBytes)} Mo → ${mb(sentBytes)} Mo (−$pct %)';
  }
}
