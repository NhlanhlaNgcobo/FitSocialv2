import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/main/application/content_providers.dart';

/// Makes [child] the way through to [userId]'s profile.
///
/// One place for the rule so an author's name behaves the same wherever it is
/// drawn — on a feed card, over a caption, beside a comment. The route is
/// pushed rather than gone to, so a profile opened from a sheet leaves the
/// sheet underneath to come back to.
///
/// Your own name is left inert: `/user/<own uid>` is the read-only view of a
/// stranger's profile, with no way to edit and nothing to follow, so it is a
/// worse answer than staying put. The same call the post detail page makes.
class ProfileLink extends ConsumerWidget {
  const ProfileLink({required this.userId, required this.child, super.key});

  /// Whose profile to open. An empty string — a post written before authors
  /// carried uids — is treated as unknown and left untappable.
  final String userId;

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (userId.isEmpty || ref.watch(currentUserIdProvider) == userId) {
      return child;
    }

    return GestureDetector(
      // Opaque so the gaps around the name — the padding of a header row, the
      // space beside a short name — are part of the target rather than holes
      // in it.
      behavior: HitTestBehavior.opaque,
      onTap: () => GoRouter.of(context).push('/user/$userId'),
      child: child,
    );
  }
}
