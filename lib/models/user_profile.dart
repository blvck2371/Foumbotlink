import 'package:cloud_firestore/cloud_firestore.dart';

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
    this.lastSeenAt,
    this.photoUrl,
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

  /// Horodatage du dernier battement de présence (PresenceService), pas
  /// forcément "l'utilisateur a fait quelque chose" — juste "l'app était
  /// au premier plan à ce moment". Sert de base à [isOnline].
  final DateTime? lastSeenAt;

  /// URL publique de la photo de profil (Firebase Storage). `null` = pas
  /// de photo : l'UI affiche les initiales du [displayName].
  final String? photoUrl;

  /// Heuristique de présence : Firestore seul ne peut pas détecter un
  /// crash ou une perte réseau brutale, donc on considère "en ligne"
  /// seulement si un battement a été reçu récemment — au-delà, le statut
  /// retombe de lui-même à "hors ligne" sans action explicite nécessaire.
  static const onlineThreshold = Duration(seconds: 40);

  bool get isOnline =>
      lastSeenAt != null &&
      DateTime.now().difference(lastSeenAt!) < onlineThreshold;

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
    if (photoUrl != null) 'photoUrl': photoUrl,
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
      createdAt:
          DateTime.tryParse(map['createdAt'] as String? ?? '') ??
          DateTime.now(),
      verified: map['verified'] as bool? ?? false,
      followersCount: map['followersCount'] as int? ?? 0,
      followingCount: map['followingCount'] as int? ?? 0,
      lastSeenAt: (map['lastSeenAt'] as Timestamp?)?.toDate(),
      photoUrl: map['photoUrl'] as String?,
    );
  }

  UserProfile copyWith({
    String? displayName,
    String? photoUrl,
    bool clearPhotoUrl = false,
  }) =>
      UserProfile(
        uid: uid,
        accountType: accountType,
        displayName: displayName ?? this.displayName,
        email: email,
        phoneNumber: phoneNumber,
        createdAt: createdAt,
        verified: verified,
        followersCount: followersCount,
        followingCount: followingCount,
        lastSeenAt: lastSeenAt,
        photoUrl: clearPhotoUrl ? null : (photoUrl ?? this.photoUrl),
      );
}
