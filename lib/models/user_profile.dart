import 'account_type.dart';

/// Profil stocké dans Firestore (`users/{uid}`), en complément du compte
/// Firebase Auth (qui ne connaît que l'email/téléphone). Porte l'identité
/// affichée sur les publications et le type de compte.
class UserProfile {
  const UserProfile({
    required this.uid,
    required this.accountType,
    required this.displayName,
    this.email,
    this.phoneNumber,
    required this.createdAt,
    this.verified = false,
    this.followersCount = 0,
    this.followingCount = 0,
  });

  final String uid;
  final AccountType accountType;
  final String displayName;
  final String? email;
  final String? phoneNumber;
  final DateTime createdAt;
  final bool verified;
  final int followersCount;
  final int followingCount;

  /// Sous-titre affiché sous le nom sur une publication, ex. "Habitant·e
  /// de Foumbot" ou "Structure locale".
  String get authorSubtitle => switch (accountType) {
        AccountType.personal => 'Habitant·e de Foumbot',
        AccountType.structure => 'Structure locale',
      };

  /// Une structure ne peut publier des infos/annonces officielles
  /// qu'une fois validée par l'admin. Un compte personnel n'a pas
  /// besoin de validation.
  bool get canPublish => accountType == AccountType.personal || verified;

  Map<String, dynamic> toMap() => {
        'accountType': accountType.name,
        'displayName': displayName,
        'email': email,
        'phoneNumber': phoneNumber,
        'createdAt': createdAt.toIso8601String(),
        'verified': verified,
        'followersCount': followersCount,
        'followingCount': followingCount,
      };

  factory UserProfile.fromMap(String uid, Map<String, dynamic> map) {
    return UserProfile(
      uid: uid,
      accountType: AccountType.values.firstWhere(
        (t) => t.name == map['accountType'],
        orElse: () => AccountType.personal,
      ),
      displayName: map['displayName'] as String? ?? '',
      email: map['email'] as String?,
      phoneNumber: map['phoneNumber'] as String?,
      createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ??
          DateTime.now(),
      verified: map['verified'] as bool? ?? false,
      followersCount: map['followersCount'] as int? ?? 0,
      followingCount: map['followingCount'] as int? ?? 0,
    );
  }
}
