import 'package:flutter_test/flutter_test.dart';
import 'package:foumbotlik/models/video_compression_policy.dart';

void main() {
  const mb = 1024 * 1024;

  group('VideoCompressionPolicy', () {
    test('une vidéo déjà légère part telle quelle', () {
      expect(VideoCompressionPolicy.shouldCompress(3 * mb), isFalse);
      expect(VideoCompressionPolicy.shouldCompress(4 * mb), isTrue);
      expect(VideoCompressionPolicy.shouldCompress(80 * mb), isTrue);
    });

    test('on garde la version compressée quand elle fait gagner', () {
      expect(
        VideoCompressionPolicy.keepCompressed(
          originalBytes: 80 * mb,
          compressedBytes: 12 * mb,
        ),
        isTrue,
      );
    });

    test('un gain de moins de 10 % ne vaut pas la perte de qualité', () {
      expect(
        VideoCompressionPolicy.keepCompressed(
          originalBytes: 10 * mb,
          compressedBytes: (9.5 * mb).round(),
        ),
        isFalse,
      );
    });

    test('compression ratée ou qui grossit : retour à l’original', () {
      expect(
        VideoCompressionPolicy.keepCompressed(originalBytes: 10 * mb),
        isFalse,
      );
      expect(
        VideoCompressionPolicy.keepCompressed(
          originalBytes: 10 * mb,
          compressedBytes: 0,
        ),
        isFalse,
      );
      expect(
        VideoCompressionPolicy.keepCompressed(
          originalBytes: 10 * mb,
          compressedBytes: 14 * mb,
        ),
        isFalse,
      );
    });

    test('le gain se lit en clair dans les journaux', () {
      expect(
        VideoCompressionPolicy.savingLabel(80 * mb, 12 * mb),
        '80.0 Mo → 12.0 Mo (−85 %)',
      );
    });
  
    test('taille annoncée : une minute en Standard, puis en HD', () {
      final standard = VideoCompressionPolicy.estimateBytes(
        quality: VideoSendQuality.standard,
        durationMs: 60000,
        originalBytes: 120 * mb,
      );
      final hd = VideoCompressionPolicy.estimateBytes(
        quality: VideoSendQuality.hd,
        durationMs: 60000,
        originalBytes: 120 * mb,
      );
      expect(standard / mb, closeTo(16.5, 0.5));
      expect(hd / mb, closeTo(28.6, 0.5));
      expect(hd, greaterThan(standard));
    });

    test('jamais plus lourd que l’original, ni sans durée connue', () {
      expect(
        VideoCompressionPolicy.estimateBytes(
          quality: VideoSendQuality.hd,
          durationMs: 60000,
          originalBytes: 10 * mb,
        ),
        10 * mb,
      );
      expect(
        VideoCompressionPolicy.estimateBytes(
          quality: VideoSendQuality.standard,
          durationMs: 0,
          originalBytes: 50 * mb,
        ),
        50 * mb,
      );
    });
  });
}
