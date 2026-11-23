import 'package:flutter_test/flutter_test.dart';
import 'package:foumbotlik/models/live_session.dart';

void main() {
  group('LiveSession.fromMap', () {
    test('lit un live complet tel que publié par startLive', () {
      final s = LiveSession.fromMap('L1', {
        'hostUid': 'awa',
        'hostName': 'Awa',
        'hostPhoto': 'https://x/p.jpg',
        'title': 'Marché du soir',
        'startedAt': 1700000000000,
        'viewers': 12,
        'likes': 340,
        'hostOnline': true,
      })!;
      expect(s.id, 'L1');
      expect(s.hostUid, 'awa');
      expect(s.hostPhoto, 'https://x/p.jpg');
      expect(s.viewers, 12);
      expect(s.likes, 340);
      expect(s.hostOnline, isTrue);
      expect(s.startedAt.millisecondsSinceEpoch, 1700000000000);
    });

    test('écarte un nœud fantôme réécrit par un onDisconnect', () {
      expect(
        LiveSession.fromMap('L1', {'hostOnline': false, 'hostSeenAt': 1}),
        isNull,
      );
      expect(LiveSession.fromMap('L1', null), isNull);
      expect(LiveSession.fromMap('L1', 'texte'), isNull);
    });

    test('valeurs manquantes : titre et nom par défaut, compteurs à 0', () {
      final s = LiveSession.fromMap('L1', {'hostUid': 'awa'})!;
      expect(s.hostName, 'Habitant');
      expect(s.title, 'Live de Habitant');
      expect(s.viewers, 0);
      expect(s.hostOnline, isTrue);
      expect(s.hostPhoto, isNull);
    });

    test('hôte déconnecté', () {
      final s = LiveSession.fromMap('L1', {
        'hostUid': 'awa',
        'hostOnline': false,
      })!;
      expect(s.hostOnline, isFalse);
    });

    test('une photo qui n’est pas une URL est ignorée', () {
      final s = LiveSession.fromMap('L1', {
        'hostUid': 'awa',
        'hostPhoto': 'javascript:alert(1)',
      })!;
      expect(s.hostPhoto, isNull);
    });
  });

  test('listFrom : les plus regardés d’abord, fantômes écartés', () {
    final list = LiveSession.listFrom({
      'a': {'hostUid': 'u1', 'viewers': 3, 'startedAt': 100},
      'b': {'hostUid': 'u2', 'viewers': 9, 'startedAt': 50},
      'c': {'hostUid': 'u3', 'viewers': 3, 'startedAt': 200},
      'fantome': {'hostOnline': false},
    });
    expect(list.map((l) => l.id), ['b', 'c', 'a']);
    expect(LiveSession.listFrom(null), isEmpty);
  });

  group('LiveComment.fromMap', () {
    test('commentaire valide', () {
      final c = LiveComment.fromMap('c1', {
        'uid': 'bob',
        'name': 'Bob',
        'text': 'Bonsoir',
        'at': 1700000000000,
      })!;
      expect(c.text, 'Bonsoir');
      expect(c.name, 'Bob');
    });

    test('sans auteur ou sans texte : ignoré', () {
      expect(LiveComment.fromMap('c1', {'text': 'x'}), isNull);
      expect(LiveComment.fromMap('c1', {'uid': 'bob', 'text': ''}), isNull);
    });
  });

  group('LiveRules', () {
    test('cleanComment aplatit les espaces et coupe à 200', () {
      expect(
        LiveRules.cleanComment('  Salut\n\n  tout   le monde '),
        'Salut tout le monde',
      );
      expect(LiveRules.cleanComment('   \n '), isNull);
      expect(LiveRules.cleanComment('x' * 250)!.length, 200);
    });

    test('cleanTitle coupe à 80', () {
      expect(LiveRules.cleanTitle('  Marché   du soir '), 'Marché du soir');
      expect(LiveRules.cleanTitle('t' * 100).length, 80);
    });

    test('compactCount', () {
      expect(LiveRules.compactCount(7), '7');
      expect(LiveRules.compactCount(999), '999');
      expect(LiveRules.compactCount(1000), '1 k');
      expect(LiveRules.compactCount(1234), '1,2 k');
      expect(LiveRules.compactCount(15400), '15 k');
      expect(LiveRules.compactCount(1300000), '1,3 M');
    });

    test('elapsed', () {
      expect(LiveRules.elapsed(const Duration(seconds: 42)), '0:42');
      expect(
        LiveRules.elapsed(const Duration(minutes: 12, seconds: 5)),
        '12:05',
      );
      expect(
        LiveRules.elapsed(const Duration(hours: 1, minutes: 3, seconds: 9)),
        '1:03:09',
      );
    });
  });

  group('HeartBatcher', () {
    test('groupe les cœurs et plafonne une écriture à 30', () {
      final b = HeartBatcher();
      for (var i = 0; i < 45; i++) {
        b.tap();
      }
      expect(b.take(), 30);
      expect(b.hasPending, isTrue);
      expect(b.take(), 15);
      expect(b.hasPending, isFalse);
      expect(b.take(), 0);
    });

    test(
      'mes cœurs, déjà animés, ne sont pas rejoués au retour du serveur',
      () {
        final b = HeartBatcher();
        for (var i = 0; i < 5; i++) {
          b.tap();
        }
        b.take();
        // Le compteur monte de 8 : 5 sont à moi, 3 viennent des autres.
        expect(b.othersIn(8), 3);
        // Ensuite, tout ce qui arrive vient des autres.
        expect(b.othersIn(4), 4);
        expect(b.othersIn(0), 0);
      },
    );

    test('un envoi raté ne masque pas les cœurs des autres', () {
      final b = HeartBatcher();
      b
        ..tap()
        ..tap();
      final n = b.take();
      b.failed(n);
      expect(b.othersIn(2), 2);
    });
  });
}
