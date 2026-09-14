import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foumbotlik/widgets/feed_image.dart';

/// Des chemins locaux (et non des URLs) : `FeedNetworkImage` les rend avec
/// `Image.file`, donc sans le moindre accès réseau — un test de widget ne
/// doit pas dépendre d'un téléchargement.
List<String> _paths(int count) =>
    List.generate(count, (i) => '/tmp/photo_$i.jpg');

Future<void> _pump(WidgetTester tester, int count) async {
  final tapped = <int>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: FeedImageCarousel(
          imageUrls: _paths(count),
          isDark: false,
          layout: FeedImageLayout.mosaic,
          onImageTap: tapped.add,
        ),
      ),
    ),
  );
}

void main() {
  group('Mosaïque de publication', () {
    testWidgets('une seule photo garde le cadre au format de l’image', (
      tester,
    ) async {
      await _pump(tester, 1);
      expect(find.byType(FeedNetworkImage), findsOneWidget);
    });

    testWidgets('deux, trois et quatre photos sont toutes visibles', (
      tester,
    ) async {
      for (final count in [2, 3, 4]) {
        await _pump(tester, count);
        expect(
          find.byType(FeedNetworkImage),
          findsNWidgets(count),
          reason: '$count photos doivent toutes avoir une tuile',
        );
        expect(find.textContaining('+'), findsNothing);
      }
    });

    testWidgets('au-delà de quatre, la dernière tuile annonce le reste', (
      tester,
    ) async {
      await _pump(tester, 6);
      expect(find.byType(FeedNetworkImage), findsNWidgets(4));
      expect(find.text('+2'), findsOneWidget);
    });

    testWidgets('le carrousel, lui, ne montre qu’une photo à la fois', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FeedImageCarousel(imageUrls: _paths(4), isDark: false),
          ),
        ),
      );
      // PageView ne construit que la page visible et ses voisines
      // immédiates : la mosaïque, elle, en affiche quatre d'un coup.
      expect(find.text('1/4'), findsOneWidget);
    });
  });
}
