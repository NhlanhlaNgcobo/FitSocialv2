class UserProfileDraft {
  const UserProfileDraft({
    required this.displayName,
    required this.handle,
    required this.bio,
    required this.location,
    this.avatarUrl,
    this.pronouns = '',
    this.links = '',
    this.handleChangedAt,
  });

  final String displayName;

  /// The account's username, normalized. Unique across all accounts, and the
  /// document id of its reservation in the `usernames` collection.
  final String handle;
  final String bio;
  final String location;
  final String? avatarUrl;

  /// How the user asks to be referred to. Empty until they fill it in.
  final String pronouns;

  /// A link the user wants on their profile. Empty until they add one.
  final String links;

  /// When the username was last *changed*, or null for an account that has
  /// never renamed.
  ///
  /// Null on a brand-new profile as well as an old one, on purpose: claiming a
  /// username for the first time is not a change, and starting the clock there
  /// would strand a new user with a typo for a fortnight.
  final DateTime? handleChangedAt;
}
