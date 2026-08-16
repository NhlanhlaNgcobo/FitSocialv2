import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/user_profile_repository.dart';
import '../domain/body_metrics.dart';
import 'app_session.dart';

/// The signed-in user's height and weight.
///
/// Kept out of `user_profile_repository.dart` on purpose: [appSessionProvider]
/// is built from the profile repository, so a provider there that watched the
/// session would close the loop.
///
/// Failing to read is not the same as having nothing on file, so no `orElse`
/// swallows the error — the BMI card shows a retry rather than an empty state
/// that invites the user to type their height in again.
final bodyMetricsProvider = FutureProvider<BodyMetrics>((ref) async {
  // A sign-out/sign-in swaps whose body this is.
  ref.watch(appSessionProvider);
  return ref.watch(userProfileRepositoryProvider).loadBodyMetrics();
});
