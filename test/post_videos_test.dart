import 'package:flutter_test/flutter_test.dart';
import 'package:foumbotlik/models/feed_item.dart';

void main() {
  test('lit une publication à une vidéo (ancien format)', () {
    final videos = PostVideoItem.listFromDoc({
      'videoUrl': 'https://v/1.mp4',
      'videoThumbUrl': 'https://v/1.jpg',
      'videoDurationMs': 65000,
    });
    expect(videos, hasLength(1));
    expect(videos.single.thumbUrl, 'https://v/1.jpg');
    expect(videos.single.durationLabel, '1:05');
  });

  test('la liste prime sur l’ancien format', () {
    final videos = PostVideoItem.listFromDoc({
      'videos': [
        {'url': 'https://v/a.mp4'},
        {'url': 'https://v/b.mp4'},
      ],
      'videoUrl': 'https://v/a.mp4',
    });
    expect(videos.map((v) => v.url), ['https://v/a.mp4', 'https://v/b.mp4']);
  });

  test('écrit la liste et la première vidéo pour les anciennes versions', () {
    final fields = PostVideoItem.docFields(const [
      PostVideoItem(url: 'https://v/a.mp4', thumbUrl: 'https://v/a.jpg'),
      PostVideoItem(url: 'https://v/b.mp4'),
    ]);
    expect((fields['videos'] as List), hasLength(2));
    expect(fields['videoUrl'], 'https://v/a.mp4');
    expect(fields['videoThumbUrl'], 'https://v/a.jpg');
    // Relu, on retrouve les deux vidéos.
    expect(PostVideoItem.listFromDoc(fields), hasLength(2));
  });

  test('sans vidéo, aucune entrée parasite', () {
    expect(PostVideoItem.listFromDoc(const {}), isEmpty);
    expect(PostVideoItem.docFields(const []), {'videos': <Object>[]});
  });
}
