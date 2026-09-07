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

    // Where everyone already stands on this challenge, so a row can offer the
    // action that will actually work. Without it the sheet showed one Invite
    // button per person whatever their state, and tapping it for somebody who
    // had already joined came back as "that invitation could not be sent".
    final standings = {
      for (final p
          in ref.watch(challengeParticipantsProvider(challenge.id)).valueOrNull ??
              const <ChallengeParticipant>[])
        p.userId: p.status,
    };

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
                      _InviteRow(
                        challenge: challenge,
                        userId: userId,
                        standing: standings[userId],
                      ),
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
  const _InviteRow({
    required this.challenge,
    required this.userId,
    this.standing,
  });

  final RunningChallenge challenge;
  final String userId;

  /// Where this person already stands, or null when they have nothing to do
  /// with the challenge yet — which is the only state a first invitation makes
  /// sense in.
  final ParticipantStatus? standing;

  @override
  ConsumerState<_InviteRow> createState() => _InviteRowState();
}

class _InviteRowState extends ConsumerState<_InviteRow> {
  /// That this tap worked, which the standing alone cannot say: a resend
  /// leaves somebody exactly where they were, so the row would flip straight
  /// back to "Resend" with nothing to show the ask had gone out.
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
          _action(palette),
        ],
      ),
    );
  }

  /// What this row offers, given where the person already stands.
  Widget _action(AppPalette palette) {
    if (_sent) {
      return Text(
        'Invited',
        style: TextStyle(color: palette.muted, fontSize: 13),
      );
    }

    switch (widget.standing) {
      // Nothing yet, or a state that can be asked out of.
      case null:
        return _button('Invite');
      case ParticipantStatus.invited:
        // Still deciding. Asking again is the one thing the creator could not
        // do before, and it is what a tester asked for by name.
        return _button('Resend');
      case ParticipantStatus.active:
      case ParticipantStatus.completed:
        return _standingLabel(palette, 'On the challenge');
      case ParticipantStatus.declined:
        return _standingLabel(palette, 'Declined');
      case ParticipantStatus.left:
        return _standingLabel(palette, 'Left');
    }
  }

  Widget _button(String label) {
    return TextButton(
      onPressed: _sending ? null : _invite,
      child: Text(label),
    );
  }

  /// Said rather than offered: these are the states no invitation can move
  /// somebody out of, and a button that always fails is worse than no button.
  Widget _standingLabel(AppPalette palette, String label) {
    return Text(
      label,
      style: TextStyle(color: palette.muted, fontSize: 13),
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
