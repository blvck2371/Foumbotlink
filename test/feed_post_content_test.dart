import 'package:flutter_test/flutter_test.dart';
import 'package:foumbotlik/models/feed_item.dart';

FeedItem _post({
  String title = '',
  String body = '',
  List<String> imageUrls = const [],
}) => FeedItem(
  id: 'p1',
  type: FeedType.post,
  title: title,
  body: body,
  authorUid: 'u1',
  authorName: 'Alice',
  authorSubtitle: 'Habitante',
  publishedAt: DateTime(2026, 1, 1),
  imageUrls: imageUrls,
);

void main() {
  group('FeedItem — titre et message facultatifs', () {
    test('un titre vide ou blanc ne compte pas comme un titre', () {
      expect(_post(title: '', body: 'coucou').hasTitle, false);
      expect(_post(title: '   ', body: 'coucou').hasTitle, false);
      expect(_post(title: 'Marché', body: 'coucou').hasTitle, true);
    });

    test('une publication peut n’être que des photos', () {
      final post = _post(imageUrls: ['a.jpg', 'b.jpg']);
      expect(post.hasTitle, false);
      expect(post.hasBody, false);
      expect(post.hasImages, true);
    });
  });

  group('FeedItem.summaryLine', () {
    test('le titre quand il existe', () {
      expect(_post(title: 'Coupure d’eau', body: 'demain').summaryLine,
          'Coupure d’eau');
    });

    test('le message à défaut de titre', () {
      expect(_post(body: 'demain').summaryLine, 'demain');
    });

    test('la mention des photos quand il n’y a aucun texte', () {
      expect(_post(imageUrls: ['a.jpg']).summaryLine, 'Photo');
      expect(_post(imageUrls: ['a.jpg', 'b.jpg']).summaryLine, '2 photos');
    });
  });

  group('FeedItem.shareText', () {
    test('n’ouvre pas sur une ligne vide quand le titre manque', () {
      final text = _post(body: 'La route est coupée.').shareText;
      expect(text.startsWith('La route est coupée.'), true);
      expect(text.contains('Publié par Alice'), true);
    });

    test('garde titre puis message quand les deux existent', () {
      final text = _post(title: 'Route', body: 'Coupée').shareText;
      expect(text.indexOf('Route') < text.indexOf('Coupée'), true);
    });

    test('reste partageable sans aucun texte', () {
      expect(_post(imageUrls: ['a.jpg']).shareText.trim(),
          'Publié par Alice sur Foumbot Link');
    });
  });
}
