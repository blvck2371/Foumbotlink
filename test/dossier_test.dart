import 'package:flutter_test/flutter_test.dart';
import 'package:foumbotlik/models/dossier.dart';

void main() {
  group('TrackingCode — génération', () {
    test('produit toujours sept caractères de l’alphabet', () {
      for (var i = 0; i < 200; i++) {
        final code = TrackingCode.generate();
        expect(code.length, TrackingCode.length);
        expect(TrackingCode.isValid(code), isTrue, reason: code);
      }
    });

    test('n’emploie jamais les caractères qui se confondent à l’écrit', () {
      // C'est la garantie qui compte : le code est recopié à la main sur
      // une chemise, puis relu par quelqu'un d'autre au guichet.
      const confusable = ['O', '0', 'I', 'L', '1'];
      for (var i = 0; i < 200; i++) {
        final code = TrackingCode.generate();
        for (final char in confusable) {
          expect(code.contains(char), isFalse, reason: '$code contient $char');
        }
      }
    });

    test('deux tirages successifs diffèrent', () {
      final codes = {for (var i = 0; i < 50; i++) TrackingCode.generate()};
      // 31⁷ combinaisons : 50 tirages identiques signaleraient un
      // générateur cassé, pas un coup de malchance.
      expect(codes.length, greaterThan(45));
    });
  });

  group('TrackingCode — saisie au guichet', () {
    test('tolère minuscules, espaces et tirets', () {
      expect(TrackingCode.normalize('abc 234-5'), 'ABC2345');
      expect(TrackingCode.normalize('ABC2345'), 'ABC2345');
    });

    test('accepte un code valide', () {
      expect(TrackingCode.describeProblem('abc 2345'), isNull);
    });

    test('réclame une saisie quand le champ est vide', () {
      expect(TrackingCode.describeProblem('   '), isNotNull);
    });

    test('signale les caractères ambigus au lieu de deviner', () {
      // Deviner enverrait le dossier sur le compte de quelqu'un d'autre :
      // l'agent a la chemise sous les yeux, c'est à lui de relire.
      final problem = TrackingCode.describeProblem('ABC234O');
      expect(problem, isNotNull);
      expect(problem, contains('O'));
    });

    test('signale une longueur incorrecte', () {
      final problem = TrackingCode.describeProblem('ABC23');
      expect(problem, contains('7'));
    });
  });

  group('DossierStatus — parcours', () {
    test('un dossier réceptionné peut avancer, être bloqué ou refusé', () {
      expect(
        DossierStatus.receptionne.nextChoices,
        contains(DossierStatus.enCours),
      );
      expect(
        DossierStatus.receptionne.nextChoices,
        contains(DossierStatus.rejete),
      );
    });

    test('on ne revient jamais en arrière', () {
      // Un dossier annoncé « terminé » puis remis « en cours » ferait se
      // déplacer quelqu'un pour rien.
      expect(DossierStatus.termine.nextChoices, equals([DossierStatus.retire]));
      expect(
        DossierStatus.enCours.nextChoices,
        isNot(contains(DossierStatus.receptionne)),
      );
    });

    test('un dossier clos n’a plus de suite', () {
      expect(DossierStatus.retire.nextChoices, isEmpty);
      expect(DossierStatus.rejete.nextChoices, isEmpty);
      expect(DossierStatus.retire.isClosed, isTrue);
      expect(DossierStatus.rejete.isClosed, isTrue);
      expect(DossierStatus.enCours.isClosed, isFalse);
    });

    test('un motif est exigé là où son absence laisserait sans réponse', () {
      expect(DossierStatus.complementRequis.requiresNote, isTrue);
      expect(DossierStatus.rejete.requiresNote, isTrue);
      expect(DossierStatus.enCours.requiresNote, isFalse);
      expect(DossierStatus.termine.requiresNote, isFalse);
    });

    test('les embranchements ne figurent pas dans la frise', () {
      expect(
        DossierStatus.timeline,
        isNot(contains(DossierStatus.complementRequis)),
      );
      expect(DossierStatus.timeline, isNot(contains(DossierStatus.rejete)));
      expect(DossierStatus.complementRequis.isBranch, isTrue);
      expect(DossierStatus.enCours.isBranch, isFalse);
    });

    test('chaque état dit à la personne ce qu’elle doit faire', () {
      for (final status in DossierStatus.values) {
        expect(status.label, isNotEmpty);
        expect(status.citizenHint, isNotEmpty);
      }
    });
  });

  group('Dossier — lecture', () {
    Dossier build({
      required DossierStatus status,
      List<DossierEvent> events = const [],
    }) => Dossier(
      id: 'd1',
      ownerUid: 'u1',
      ownerName: 'Amina N.',
      trackingCode: 'ABC2345',
      structureUid: 's1',
      structureName: 'Préfecture de Foumbot',
      title: 'Certification d’acte de naissance',
      status: status,
      createdAt: DateTime(2026, 9, 1),
      updatedAt: DateTime(2026, 9, 3),
      events: events,
    );

    test('la note affichée est celle de l’état courant', () {
      final dossier = build(
        status: DossierStatus.complementRequis,
        events: [
          DossierEvent(
            status: DossierStatus.receptionne,
            at: DateTime(2026, 9, 1),
          ),
          DossierEvent(
            status: DossierStatus.complementRequis,
            at: DateTime(2026, 9, 3),
            note: 'Il manque la copie de la CNI.',
          ),
        ],
      );

      expect(dossier.currentNote, 'Il manque la copie de la CNI.');
    });

    test('sans note sur l’état courant, rien n’est affiché', () {
      final dossier = build(
        status: DossierStatus.enCours,
        events: [
          DossierEvent(
            status: DossierStatus.complementRequis,
            at: DateTime(2026, 9, 2),
            note: 'Ancienne remarque',
          ),
          DossierEvent(status: DossierStatus.enCours, at: DateTime(2026, 9, 3)),
        ],
      );

      expect(dossier.currentNote, isNull);
    });

    test('la position dans la frise suit le parcours normal', () {
      expect(build(status: DossierStatus.receptionne).timelineIndex, 0);
      expect(build(status: DossierStatus.enCours).timelineIndex, 1);
      expect(build(status: DossierStatus.termine).timelineIndex, 2);
      expect(build(status: DossierStatus.retire).timelineIndex, 3);
    });

    test('un embranchement n’a pas de position dans la frise', () {
      expect(
        build(status: DossierStatus.complementRequis).timelineIndex,
        isNull,
      );
      expect(build(status: DossierStatus.rejete).timelineIndex, isNull);
    });
  });
}
