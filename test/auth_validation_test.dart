import 'package:flutter_test/flutter_test.dart';
import 'package:foumbotlik/controllers/auth_controller.dart';
import 'package:foumbotlik/models/account_type.dart';

void main() {
  group('AuthController.validateEmail', () {
    test('accepte une adresse ordinaire', () {
      expect(AuthController.validateEmail('amina@exemple.com'), isNull);
      expect(AuthController.validateEmail('  amina@exemple.cm  '), isNull);
    });

    test('refuse le vide', () {
      expect(AuthController.validateEmail(''), isNotNull);
      expect(AuthController.validateEmail('   '), isNotNull);
    });

    test('refuse une adresse sans arobase ni domaine', () {
      expect(AuthController.validateEmail('amina'), isNotNull);
      expect(AuthController.validateEmail('amina@'), isNotNull);
      expect(AuthController.validateEmail('amina@exemple'), isNotNull);
      expect(AuthController.validateEmail('@exemple.com'), isNotNull);
      expect(AuthController.validateEmail('amina@exemple.'), isNotNull);
    });

    test('refuse une adresse contenant une espace', () {
      expect(AuthController.validateEmail('amina n@exemple.com'), isNotNull);
    });
  });

  group('AuthController.validatePassword', () {
    test('à l’inscription, six caractères sont exigés', () {
      expect(
        AuthController.validatePassword('12345', isSignUp: true),
        isNotNull,
      );
      expect(AuthController.validatePassword('123456', isSignUp: true), isNull);
    });

    test('à la connexion, la longueur d’un mot de passe existant '
        'n’est pas jugée', () {
      // Un ancien compte peut avoir un mot de passe plus court : le
      // refuser localement enfermerait son propriétaire hors de l'app.
      expect(AuthController.validatePassword('abc', isSignUp: false), isNull);
    });

    test('le vide est refusé dans les deux modes', () {
      expect(AuthController.validatePassword('', isSignUp: true), isNotNull);
      expect(AuthController.validatePassword('', isSignUp: false), isNotNull);
    });
  });

  group('AuthController.validatePhone', () {
    test('accepte un numéro international, espaces compris', () {
      expect(AuthController.validatePhone('+237690000000'), isNull);
      expect(AuthController.validatePhone('+237 690 000 000'), isNull);
    });

    test('exige l’indicatif', () {
      expect(AuthController.validatePhone('690000000'), isNotNull);
    });

    test('refuse un numéro trop court, trop long ou non numérique', () {
      expect(AuthController.validatePhone('+2376'), isNotNull);
      expect(AuthController.validatePhone('+2376900000000000'), isNotNull);
      expect(AuthController.validatePhone('+237ABCDEFGH'), isNotNull);
    });
  });

  group('AuthController.validateOtp', () {
    test('accepte six chiffres', () {
      expect(AuthController.validateOtp('123456'), isNull);
    });

    test('refuse une longueur différente ou des lettres', () {
      expect(AuthController.validateOtp('12345'), isNotNull);
      expect(AuthController.validateOtp('1234567'), isNotNull);
      expect(AuthController.validateOtp('12345A'), isNotNull);
      expect(AuthController.validateOtp(''), isNotNull);
    });
  });

  group('AuthController.validateName', () {
    test('accepte un nom ordinaire', () {
      expect(
        AuthController.validateName('Amina N.', AccountType.personal),
        isNull,
      );
    });

    test('le message s’adapte au type de compte', () {
      expect(
        AuthController.validateName('', AccountType.structure),
        contains('structure'),
      );
      expect(
        AuthController.validateName('', AccountType.personal),
        contains('votre nom'),
      );
    });

    test('refuse un nom d’une seule lettre', () {
      expect(AuthController.validateName('A', AccountType.personal), isNotNull);
    });
  });
}
