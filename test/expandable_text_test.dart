import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foumbotlik/widgets/expandable_text.dart';

Widget _host(String text) => MaterialApp(
  home: Scaffold(
    body: SizedBox(
      width: 300,
      child: ExpandableText(
        text: text,
        style: const TextStyle(fontSize: 14, height: 1.4),
        linkColor: Colors.orange,
      ),
    ),
  ),
);

/// Assez long pour déborder de trois lignes sur 300 px de large, assez
/// court pour tenir dans la fenêtre de test une fois déplié — sinon le
/// « Voir moins » se retrouve hors écran et devient intappable.
final _long = List.filled(30, 'Foumbot').join(' ');

void main() {
  group('ExpandableText', () {
    testWidgets('un texte court n’affiche aucun lien', (tester) async {
      await tester.pumpWidget(_host('Deux mots.'));
      expect(find.text('Voir plus'), findsNothing);
      expect(find.text('Voir moins'), findsNothing);
    });

    testWidgets('un texte qui déborde propose « Voir plus »', (tester) async {
      await tester.pumpWidget(_host(_long));
      expect(find.text('Voir plus'), findsOneWidget);
    });

    testWidgets('le lien déplie puis replie le texte', (tester) async {
      await tester.pumpWidget(_host(_long));

      // Replié : le corps est borné à maxLines et coupé par une ellipse.
      Text body() => tester.widget<Text>(find.text(_long));
      expect(body().maxLines, 3);
      expect(body().overflow, TextOverflow.ellipsis);

      await tester.tap(find.text('Voir plus'));
      await tester.pumpAndSettle();

      expect(find.text('Voir moins'), findsOneWidget);
      expect(body().maxLines, isNull);

      await tester.tap(find.text('Voir moins'));
      await tester.pumpAndSettle();

      expect(find.text('Voir plus'), findsOneWidget);
      expect(body().maxLines, 3);
    });
  });
}
