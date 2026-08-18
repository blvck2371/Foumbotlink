/// Type de compte choisi à l'inscription — détermine ce qu'un compte a
/// le droit de publier.
///
/// - `personal` : n'importe quel habitant, ne publie que des
///   publications simples.
/// - `structure` : mairie, préfecture, association, ONG, entreprise
///   locale… — nom libre saisi à l'inscription (pas de liste fixe), peut
///   publier des informations ou des annonces officielles.
enum AccountType {
  personal,
  structure;

  String get label => switch (this) {
        AccountType.personal => 'Compte personnel',
        AccountType.structure => 'Compte structure',
      };

  String get description => switch (this) {
        AccountType.personal => 'Vous publiez en votre nom, comme n’importe quel habitant.',
        AccountType.structure =>
          'Mairie, préfecture, association, ONG… vous pourrez publier des informations et des annonces officielles.',
      };

  /// Seuls les comptes structure peuvent choisir entre "Information" et
  /// "Annonce officielle" au moment de publier ; un compte personnel
  /// publie toujours une simple publication.
  bool get canPublishOfficialContent => this == AccountType.structure;
}
