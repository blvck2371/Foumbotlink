import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:video_compress/video_compress.dart';

import '../models/video_compression_policy.dart';

/// Vidéo prête à partir : l'original, ou sa version compressée.
class PreparedVideo {
  const PreparedVideo({
    required this.path,
    required this.bytes,
    required this.originalBytes,
    required this.compressed,
  });

  final String path;
  final int bytes;
  final int originalBytes;

  /// Vrai si [path] est un fichier temporaire produit par la compression —
  /// à supprimer une fois l'envoi terminé.
  final bool compressed;

  /// Retire le fichier compressé du disque. L'original, lui, appartient à
  /// la galerie : on n'y touche jamais.
  Future<void> discard() async {
    if (!compressed) return;
    try {
      await File(path).delete();
    } on FileSystemException catch (_) {}
  }
}

/// Compression des vidéos avant l'envoi, par l'encodeur matériel du
/// téléphone (MediaCodec sur Android, AVFoundation sur iOS).
///
/// Un téléphone filme en 1080p ou 4K, soit 60 à 150 Mo la minute : tel
/// quel, c'est un envoi lent, cher sur un forfait mobile, et souvent raté.
/// Ramenée en 960×540 — ce que l'écran d'un téléphone montre de toute
/// façon dans une discussion —, la même minute pèse 8 à 15 Mo.
///
/// Toute défaillance retombe sur l'original : la compression est une
/// économie, jamais une condition de l'envoi.
class VideoCompressionService {
  VideoCompressionService._();

  /// Le plugin ne sait compresser qu'une vidéo à la fois : les demandes
  /// font la queue.
  static Future<void> _queue = Future.value();

  static Future<PreparedVideo> prepare(
    String path, {
    void Function(double progress)? onProgress,
  }) {
    final done = Completer<PreparedVideo>();
    _queue = _queue.then((_) async {
      try {
        done.complete(await _prepare(path, onProgress));
      } catch (e, st) {
        // Fichier illisible, par exemple : l'appelant le saura, et la file
        // reste libre pour les vidéos suivantes.
        done.completeError(e, st);
      }
    });
    return done.future;
  }

  static Future<PreparedVideo> _prepare(
    String path,
    void Function(double progress)? onProgress,
  ) async {
    final original = File(path);
    final originalBytes = await original.length();
    final asIs = PreparedVideo(
      path: path,
      bytes: originalBytes,
      originalBytes: originalBytes,
      compressed: false,
    );
    if (!VideoCompressionPolicy.shouldCompress(originalBytes)) return asIs;

    Subscription? progress;
    if (onProgress != null) {
      progress = VideoCompress.compressProgress$.subscribe(
        (p) => onProgress((p / 100).clamp(0.0, 1.0)),
      );
    }
    try {
      final info = await VideoCompress.compressVideo(
        path,
        quality: VideoQuality.Res960x540Quality,
        frameRate: 30,
        includeAudio: true,
      );
      final out = info?.path;
      if (out == null || info?.isCancel == true) return asIs;
      final outBytes = await File(out).length();
      if (!VideoCompressionPolicy.keepCompressed(
        originalBytes: originalBytes,
        compressedBytes: outBytes,
      )) {
        unawaited(File(out).delete().then((_) {}, onError: (_) {}));
        return asIs;
      }
      developer.log(
        VideoCompressionPolicy.savingLabel(originalBytes, outBytes),
        name: 'VideoCompression',
      );
      return PreparedVideo(
        path: out,
        bytes: outBytes,
        originalBytes: originalBytes,
        compressed: true,
      );
    } catch (e) {
      developer.log('Compression impossible', name: 'VideoCompression', error: e);
      return asIs;
    } finally {
      progress?.unsubscribe();
    }
  }
}
