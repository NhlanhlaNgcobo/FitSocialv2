import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/avatar.dart';
import '../../main/application/content_providers.dart'
    show followingIdsProvider, userProfileProvider;
import '../application/running_challenge_providers.dart';
import '../domain/running_challenge.dart';

/// Invite somebody to a challenge.
///
/// Drawn from the people the user already follows rather than from a search
/// over every account. Invitations are the only way onto a private challenge,
/// so the list of who can be invited is worth keeping to people there is
/// already a relationship with — an invite box that reaches strangers is a
/// spam channel.
Future<void> showChallengeInviteSheet(
  BuildContext context,
  RunningChallenge challenge,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _InviteSheet(challenge: challenge),
  );
}

class _InviteSheet extends ConsumerWidget {
  const _InviteSheet({required this.challenge});

  final RunningChallenge challenge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final following = ref.watch(followingIdsProvider).valueOrNull;

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(AppSpacing.sm),
        padding: const EdgeInsets.all(AppSpacing.md),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        decoration: BoxDecoration(
          color: palette.surfaceHigh,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: palette.stroke),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Invite to ${challenge.title}',
              style: TextStyle(
                color: palette.text,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'People you follow.',
              style: TextStyle(color: palette.muted, fontSize: 13),
            ),
            const SizedBox(height: AppSpacing.md),
            if (following == null)
              const Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (following.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Text(
                  'You are not following anybody yet. Follow someone and they '
                  'can be invited here.',
                  style: TextStyle(color: palette.muted),
                ),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final userId in following)
                      _InviteRow(challenge: challenge, userId: userId),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _InviteRow extends ConsumerStatefulWidget {
  const _InviteRow({required this.challenge, required this.userId});

  final RunningChallenge challenge;
  final String userId;

  @override
  ConsumerState<_InviteRow> createState() => _InviteRowState();
}

class _InviteRowState extends ConsumerState<_InviteRow> {
  /// Latched rather than derived from the participant document.
  ///
  /// Watching the invitee's participant record would mean a live query per row,
  /// and the row only has to say "sent" until the sheet closes. The write itself
  /// is idempotent — the document id is the invitee's uid — so a second tap
  /// costs nothing even if this state were lost.
  bool _sent = false;
  bool _sending = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final profile = ref.watch(userProfileProvider(widget.userId));
    final name = profile.valueOrNull?.displayName ?? 'Runner';
    final handle = profile.valueOrNull?.handle ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Avatar(
            initials: profile.valueOrNull?.initials ?? '',
            imageUrl: profile.valueOrNull?.avatarUrl,
            size: 36,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (handle.isNotEmpty)
                  Text(
                    handle,
                    style: TextStyle(color: palette.muted, fontSize: 12),
                  ),
              ],
            ),
          ),
          if (_sent)
            Text(
              'Invited',
              style: TextStyle(color: palette.muted, fontSize: 13),
            )
          else
            TextButton(
              onPressed: _sending ? null : _invite,
              child: const Text('Invite'),
            ),
        ],
      ),
    );
  }

  Future<void> _invite() async {
    setState(() => _sending = true);
    try {
      await ref
          .read(runningChallengeActionsProvider)
          .invite(widget.challenge, widget.userId);
      if (mounted) setState(() => _sent = true);
    } catch (_) {
      // Surfaced rather than swallowed: an invitation that silently failed
      // leaves the creator believing somebody was asked when they were not.
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('That invitation could not be sent.')),
        );
      }
    }
  }
}
