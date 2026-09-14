import 'package:flutter_test/flutter_test.dart';
import 'package:foumbotlik/models/account_type.dart';
import 'package:foumbotlik/models/user_profile.dart';

UserProfile _profile({DateTime? lastSeenAt}) => UserProfile(
  uid: 'u1',
  accountType: AccountType.personal,
  displayName: 'Alice',
  createdAt: DateTime(2026, 1, 1),
  lastSeenAt: lastSeenAt,
);

void main() {
  group('UserProfile.isOnline', () {
    test('false when lastSeenAt is null (never seen / explicitly offline)', () {
      expect(_profile(lastSeenAt: null).isOnline, false);
    });

    test('true just under the online threshold', () {
      final recent = DateTime.now().subtract(
        UserProfile.onlineThreshold - const Duration(seconds: 5),
      );
      expect(_profile(lastSeenAt: recent).isOnline, true);
    });

    test('false once past the online threshold (stale heartbeat)', () {
      final stale = DateTime.now().subtract(
        UserProfile.onlineThreshold + const Duration(seconds: 5),
      );
      expect(_profile(lastSeenAt: stale).isOnline, false);
    });
  });
}
