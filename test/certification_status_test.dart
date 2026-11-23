import 'package:flutter_test/flutter_test.dart';
import 'package:foumbotlik/controllers/edit_profile_controller.dart';

void main() {
  group('CertificationStatus.fromMap', () {
    test('lit la réponse de certificationStatus', () {
      final s = CertificationStatus.fromMap({
        'accountType': 'personal',
        'verified': false,
        'enabled': true,
        'minFollowers': 500,
        'minLikes': 1000,
        'followers': 620,
        'likes': 1100,
        'eligible': true,
        'request': {'status': 'pending'},
      });
      expect(s.isStructure, isFalse);
      expect(s.enabled, isTrue);
      expect(s.minFollowers, 500);
      expect(s.minLikes, 1000);
      expect(s.followers, 620);
      expect(s.likes, 1100);
      expect(s.eligible, isTrue);
      expect(s.pending, isTrue);
    });

    test('structure, pas encore ouverte, sans demande', () {
      final s = CertificationStatus.fromMap({
        'accountType': 'structure',
        'enabled': false,
        'request': null,
      });
      expect(s.isStructure, isTrue);
      expect(s.enabled, isFalse);
      expect(s.requestStatus, isNull);
      expect(s.minLikes, 0);
    });
  });
}
