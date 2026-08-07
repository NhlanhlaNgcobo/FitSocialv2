class UserProfileDraft {
  const UserProfileDraft({
    required this.displayName,
    required this.handle,
    required this.bio,
    required this.location,
    this.avatarUrl,
    this.pronouns = '',
    this.links = '',
  });

  final String displayName;
  final String handle;
  final String bio;
  final String location;
  final String? avatarUrl;

  /// How the user asks to be referred to. Empty until they fill it in.
  final String pronouns;

  /// A link the user wants on their profile. Empty until they add one.
  final String links;
}
