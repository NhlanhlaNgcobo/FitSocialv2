import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/bootstrap/bootstrap_status.dart';
import '../domain/username.dart';
import 'firebase_username_repository.dart';
import 'username_repository_contract.dart';

/// Stands in when Firebase is not configured.
///
/// Reports every name as available rather than throwing: this backs a live
/// hint under a text field, and a red error on every keystroke would be a
/// worse answer than no hint at all. The save still fails loudly if it is ever
/// reached without Firebase.
class UnconfiguredUsernameRepository implements UsernameRepository {
  const UnconfiguredUsernameRepository();

  @override
  Future<UsernameAvailability> checkAvailability(String candidate) async {
    final formatError = validateUsernameFormat(candidate);
    if (formatError != null) {
      return UsernameAvailability.malformed(formatError);
    }
    return const UsernameAvailability(status: UsernameStatus.available);
  }
}

final usernameRepositoryProvider = Provider<UsernameRepository>((ref) {
  final status = ref.watch(bootstrapStatusProvider);
  if (status.canUseFirebase) {
    return FirebaseUsernameRepository();
  }
  return const UnconfiguredUsernameRepository();
});
