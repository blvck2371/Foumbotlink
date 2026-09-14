import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foumbotlik/models/user_status.dart';
import 'package:foumbotlik/widgets/status_ring.dart';

UserStatus _status({
  Duration age = Duration.zero,
  Duration? life,
  String? imageUrl,
  String? videoUrl,
  String text = '',
  int viewsCount = 0,
  bool viewedByMe = false,
}) {
  final createdAt = DateTime.now().subtract(age);
  return UserStatus(
    id: 's1',
    authorUid: 'u1',
    authorName: 'Alice',
    createdAt: createdAt,
    expiresAt: createdAt.add(life ?? UserStatus.lifetime),
    imageUrl: imageUrl,
    videoUrl: videoUrl,
    text: text,
    viewsCount: viewsCount,
    viewedByMe: viewedByMe,
  );
}

void main() {
  group('UserStatus — durée de vie', () {
    test('un statut tout juste publié vit 24 h', () {
      expect(UserStatus.lifetime, const Duration(hours: 24));
      expect(_status().isExpired, false);
    });

    test('passé son échéance, il est expiré', () {
      expect(_status(age: const Duration(hours: 25)).isExpired, true);
    });

    test('« il reste » compte en heures puis en minutes', () {
      expect(_status(age: const Duration(hours: 2)).remainingLabel,
          'il reste 21 h');
      expect(
        _status(age: const Duration(hours: 23, minutes: 30)).remainingLabel,
        'il reste 29 min',
      );
    });

    test('un statut expiré ne promet plus de temps restant', () {
      final expired = _status(age: const Duration(hours: 30));
      expect(expired.remaining, Duration.zero);
      expect(expired.remainingLabel, 'expiré');
    });

    test('l’âge se lit en minutes puis en heures', () {
      expect(_status().ageLabel, 'à l’instant');
      expect(_status(age: const Duration(minutes: 5)).ageLabel, 'il y a 5 min');
      expect(_status(age: const Duration(hours: 3)).ageLabel, 'il y a 3 h');
    });
  });

  group('UserStatus — contenu et vues', () {
    test('photo et texte sont indépendants', () {
      expect(_status(text: 'Bonjour').hasText, true);
      expect(_status(text: '   ').hasText, false);
      expect(_status().hasImage, false);
      expect(_status(imageUrl: 'https://x/y.jpg').hasImage, true);
    });

    test('un statut est texte, photo ou vidéo', () {
      expect(_status(text: 'Bonjour').kind, StatusKind.text);
      expect(_status(imageUrl: 'https://x/y.jpg').kind, StatusKind.image);
      expect(_status(videoUrl: 'https://x/y.mp4').kind, StatusKind.video);
    });

    test('la vidéo l’emporte si les deux médias traînent', () {
      final both = _status(
        imageUrl: 'https://x/y.jpg',
        videoUrl: 'https://x/y.mp4',
      );
      expect(both.kind, StatusKind.video);
      expect(both.hasMedia, true);
    });

    test('un statut texte ne porte aucun média', () {
      expect(_status(text: 'Bonjour').hasMedia, false);
      expect(_status(videoUrl: 'https://x/y.mp4').hasVideo, true);
      expect(_status(videoUrl: '').hasVideo, false);
    });

    test('le compteur de vues s’accorde', () {
      expect(_status().viewsLabel, '0 vue');
      expect(_status(viewsCount: 1).viewsLabel, '1 vue');
      expect(_status(viewsCount: 12).viewsLabel, '12 vues');
    });

    test('copyWith ne touche qu’aux vues', () {
      final seen = _status(viewsCount: 3, videoUrl: 'https://x/y.mp4')
          .copyWith(
        viewsCount: 4,
        viewedByMe: true,
      );
      expect(seen.viewsCount, 4);
      expect(seen.viewedByMe, true);
      expect(seen.id, 's1');
      expect(seen.authorName, 'Alice');
      // Le média doit survivre à la recopie : le perdre transformerait un
      // statut vidéo en statut texte au premier comptage de vue.
      expect(seen.videoUrl, 'https://x/y.mp4');
      expect(seen.kind, StatusKind.video);
    });
  });

  group('StatusRing', () {
    Future<void> pump(WidgetTester tester,
        {required bool hasStatuses, bool hasUnseen = false}) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatusRing(
              radius: 20,
              hasStatuses: hasStatuses,
              hasUnseen: hasUnseen,
              child: const SizedBox(
                key: Key('avatar'),
                width: 40,
                height: 40,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('sans statut, l’avatar est rendu tel quel', (tester) async {
      await pump(tester, hasStatuses: false);
      expect(find.byKey(const Key('avatar')), findsOneWidget);
      // Pas d'anneau : aucun cercle en dégradé n'est peint.
      final gradients = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) => (c.decoration as BoxDecoration?)?.gradient != null);
      expect(gradients, isEmpty);
    });

    testWidgets('avec des statuts, un anneau entoure l’avatar', (tester) async {
      await pump(tester, hasStatuses: true, hasUnseen: true);
      expect(find.byKey(const Key('avatar')), findsOneWidget);
      final gradients = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) => (c.decoration as BoxDecoration?)?.gradient != null);
      expect(gradients, isNotEmpty);
    });
  });
}
