import 'package:flutter_test/flutter_test.dart';
import 'package:foumbotlik/models/call.dart';

void main() {
  group('CallMember.fromMap', () {
    test('lit une ligne écrite par inviteToCall', () {
      final m = CallMember.fromMap('carole', {
        'state': 'ringing',
        'name': ' Carole ',
        'invitedBy': 'awa',
      });
      expect(m.uid, 'carole');
      expect(m.state, CallMemberState.ringing);
      expect(m.name, 'Carole');
      expect(m.invitedBy, 'awa');
      expect(m.isActive, isTrue);
    });

    test('seuls « sonne » et « en communication » occupent une place', () {
      for (final state in CallMemberState.values) {
        final m = CallMember.fromMap('x', {'state': state.name});
        expect(
          m.isActive,
          state == CallMemberState.ringing || state == CallMemberState.joined,
          reason: state.name,
        );
      }
    });

    test('état inconnu ou nom vide : membre parti, « Habitant »', () {
      final m = CallMember.fromMap('x', {'state': '???', 'name': '  '});
      expect(m.state, CallMemberState.left);
      expect(m.isActive, isFalse);
      expect(m.name, 'Habitant');
    });
  });
}
