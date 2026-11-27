import 'package:flutter_test/flutter_test.dart';
import 'package:foumbotlik/models/post_text.dart';
import 'package:foumbotlik/models/video_compression_policy.dart';

const _jean = PostMention(kind: MentionKind.user, id: 'u1', name: 'Jean');
const _jeanPaul = PostMention(
  kind: MentionKind.user,
  id: 'u2',
  name: 'Jean Paul',
);
const _froid = PostMention(
  kind: MentionKind.pro,
  id: 'p1',
  name: 'Froid Service',
);

void main() {
  group('hashtags', () {
    test('extraits, normalisés, sans doublon', () {
      expect(
        extractHashtags('Grande #Fête ce soir #fete #Foumbot_2026 !'),
        ['fete', 'foumbot_2026'],
      );
    });

    test('ignore C#7, les ancres et le # seul', () {
      expect(extractHashtags('Langage C#7, lien a.com/#top, # seul'), isEmpty);
    });
  });

  group('splitPostText', () {
    test('relie mentions et hashtags', () {
      final parts = splitPostText(
        'Merci @Froid Service pour la clim #chaleur',
        [_froid],
      );
      expect(parts.whereType<MentionPart>().single.mention, _froid);
      expect(parts.whereType<HashtagPart>().single.tag, 'chaleur');
      expect(parts.map((p) => p.text).join(), 
          'Merci @Froid Service pour la clim #chaleur');
    });

    test('la mention la plus longue gagne', () {
      final parts = splitPostText('Bravo @Jean Paul !', [_jean, _jeanPaul]);
      expect(parts.whereType<MentionPart>().single.mention, _jeanPaul);
    });

    test('un @ sans mention enregistrée reste du texte', () {
      final parts = splitPostText('Écrivez à @Inconnu', [_jean]);
      expect(parts.whereType<MentionPart>(), isEmpty);
    });
  });

  test('mentionsStillIn retire une mention effacée du texte', () {
    expect(mentionsStillIn('Merci @Jean', [_jean, _froid]), [_jean]);
  });

  group('activeTrigger', () {
    test('@ en cours de frappe', () {
      final t = activeTrigger('Bonjour @je', 11)!;
      expect(t.trigger, '@');
      expect(t.query, 'je');
      expect(t.start, 8);
    });

    test('pas de déclenchement au milieu d’un mot (e-mail)', () {
      expect(activeTrigger('ecrire a jean@mail', 18), isNull);
    });

    test('un hashtag s’arrête à l’espace', () {
      expect(activeTrigger('#fete ce', 8), isNull);
    });
  });

  test('le fil ne réduit une vidéo qu’au-delà de 8 Mo', () {
    const mb = 1024 * 1024;
    const t = VideoCompressionPolicy.feedCompressAboveBytes;
    expect(VideoCompressionPolicy.shouldCompress(7 * mb, threshold: t), isFalse);
    expect(VideoCompressionPolicy.shouldCompress(8 * mb, threshold: t), isTrue);
    // Chat et statuts gardent leur seuil de 4 Mo.
    expect(VideoCompressionPolicy.shouldCompress(5 * mb), isTrue);
  });
}
