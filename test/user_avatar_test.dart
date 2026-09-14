import 'package:flutter_test/flutter_test.dart';
import 'package:foumbotlik/widgets/user_avatar.dart';

void main() {
  group('UserAvatar.initials', () {
    test('returns ? for empty name', () {
      expect(UserAvatar.initials(''), '?');
      expect(UserAvatar.initials('   '), '?');
    });

    test('returns first letter for single word', () {
      expect(UserAvatar.initials('Alice'), 'A');
    });

    test('returns two letters for multi-word names', () {
      expect(UserAvatar.initials('Mairie Foumbot'), 'MF');
      expect(UserAvatar.initials('Jean Dupont'), 'JD');
    });
  });
}
