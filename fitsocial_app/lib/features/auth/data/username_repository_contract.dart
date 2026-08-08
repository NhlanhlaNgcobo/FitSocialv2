import '../domain/username.dart';

/// Read-only questions about the `usernames` collection.
///
/// Claiming is deliberately absent: a claim has to commit atomically with the
/// profile that carries the username, so it lives inside
/// [UserProfileRepository.saveProfile] instead. What is left here is the
/// advisory check the UI runs while someone types.
abstract class UsernameRepository {
  /// Whether [candidate] can be taken by the signed-in user.
  ///
  /// Advisory only. Two people can pass this check on the same name in the
  /// same second; the transaction behind the save is what actually decides,
  /// and it throws [UsernameTakenException] when it loses the race.
  Future<UsernameAvailability> checkAvailability(String candidate);
}
