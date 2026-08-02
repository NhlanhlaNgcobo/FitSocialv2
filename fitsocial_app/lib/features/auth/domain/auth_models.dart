class UserProfileDraft {
  const UserProfileDraft({
    required this.displayName,
    required this.handle,
    required this.bio,
    required this.location,
    this.avatarUrl,
  });

  final String displayName;
  final String handle;
  final String bio;
  final String location;
  final String? avatarUrl;
}
