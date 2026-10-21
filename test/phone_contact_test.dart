import 'package:flutter_test/flutter_test.dart';
import 'package:foumbotlik/models/phone_contact.dart';

void main() {
  group('PhoneContact.normalize', () {
    test('reconnaît le même numéro sous toutes ses écritures', () {
      // C'est le cœur de la fonctionnalité : dans un répertoire, ces six
      // lignes désignent la même personne.
      const attendu = '+237690000000';
      for (final ecriture in [
        '690000000',
        '690 00 00 00',
        '690-00-00-00',
        '+237690000000',
        '+237 690 00 00 00',
        '00237690000000',
        '237690000000',
        '0690000000',
      ]) {
        expect(PhoneContact.normalize(ecriture), attendu, reason: ecriture);
      }
    });

    test('ignore les parenthèses et les points', () {
      expect(PhoneContact.normalize('+237 (690) 00.00.00'), '+237690000000');
    });

    test('refuse plutôt que de deviner', () {
      // Un numéro mal reconstitué rapprocherait deux inconnus.
      expect(PhoneContact.normalize(''), isNull);
      expect(PhoneContact.normalize('   '), isNull);
      expect(PhoneContact.normalize('12345'), isNull);
      expect(PhoneContact.normalize('appeler maman'), isNull);
      expect(PhoneContact.normalize('+2376900000000000000'), isNull);
    });

    test('respecte un indicatif déjà présent, même étranger', () {
      expect(PhoneContact.normalize('+33612345678'), '+33612345678');
      expect(PhoneContact.normalize('0033612345678'), '+33612345678');
    });

    test('l’indicatif par défaut est configurable', () {
      expect(
        PhoneContact.normalize('612345678', countryCode: '33'),
        '+33612345678',
      );
    });
  });

  group('PhoneContact.hashOf', () {
    test('deux écritures du même numéro donnent la même empreinte', () {
      final a = PhoneContact.hashOf(PhoneContact.normalize('690 00 00 00')!);
      final b = PhoneContact.hashOf(PhoneContact.normalize('+237690000000')!);
      expect(a, b);
    });

    test('deux numéros différents donnent des empreintes différentes', () {
      final a = PhoneContact.hashOf('+237690000000');
      final b = PhoneContact.hashOf('+237690000001');
      expect(a, isNot(b));
    });

    test('l’empreinte ne laisse rien voir du numéro', () {
      final hash = PhoneContact.hashOf('+237690000000');
      expect(hash.length, 64);
      expect(hash.contains('690'), isFalse);
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(hash), isTrue);
    });
  });

  group('PhoneContact.hashAll', () {
    test('dédoublonne un répertoire où le même numéro revient', () {
      final hashes = PhoneContact.hashAll([
        '690 00 00 00',
        '+237690000000',
        '00237690000000',
      ]);
      expect(hashes, hasLength(1));
    });

    test('écarte silencieusement ce qui n’est pas un numéro', () {
      final hashes = PhoneContact.hashAll([
        '690000000',
        'bureau',
        '',
        '123',
        '691000000',
      ]);
      expect(hashes, hasLength(2));
    });

    test('un répertoire vide ne produit aucune empreinte', () {
      expect(PhoneContact.hashAll(const []), isEmpty);
    });
  });
}
