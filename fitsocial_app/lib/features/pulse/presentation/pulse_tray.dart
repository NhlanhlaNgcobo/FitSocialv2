import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../auth/application/app_session.dart';
import '../../notes/application/note_providers.dart';
import '../../notes/domain/note_models.dart';
import '../../notes/presentation/note_bubble.dart';
import '../../notes/presentation/note_sheets.dart';
import '../application/pulse_providers.dart';
import '../domain/pulse_models.dart';
import 'pulse_ring.dart';
import '../../../shared/widgets/liquid_glass.dart';

/// The horizontal rail of Pulse rings at the top of the feed, with Notes
/// riding over the avatars.
///
/// The signed-in user's tile is always first and always present, even with
/// nothing posted — it doubles as the entry point to the composer, which is
/// the only place a Pulse can be created from the feed. Over it sits today's
/// question, for them alone, until they answer it; then their answer.
///
/// Everyone else appears if they have a Pulse, a Note, or both.
class PulseTray extends ConsumerWidget {
  const PulseTray({super.key});

  /// Room for a two-line bubble over a 72 px ring and its label.
  static const double height = 136;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pulses = ref.watch(pulseTrayProvider);
    final tiles = ref.watch(trayTilesProvider);
    final profile = ref.watch(appSessionProvider).profile;
    // buildPulseTray already sorts the user's own ring to the front when they
    // have one; when they don't, a placeholder tile stands in for it.
    final entries = pulses.valueOrNull ?? const <PulseTrayEntry>[];
    final ownEntry =
        entries.isNotEmpty && entries.first.isOwn ? entries.first : null;

    return SizedBox(
      height: height,
      child: tiles.when(
        data: (others) => _Rail(
          ownEntry: ownEntry,
          others: others,
          profileName: profile?.displayName,
          profileAvatarUrl: profile?.avatarUrl,
        ),
        loading: () => _Rail(
          ownEntry: null,
          others: const [],
          profileName: profile?.displayName,
          profileAvatarUrl: profile?.avatarUrl,
        ),
        error: (_, __) => const _TrayMessage(label: 'Pulse unavailable'),
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({
    required this.ownEntry,
    required this.others,
    this.profileName,
    this.profileAvatarUrl,
  });

  final PulseTrayEntry? ownEntry;
  final List<TrayTile> others;
  final String? profileName;
  final String? profileAvatarUrl;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.zero,
      itemCount: others.length + 1,
      separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
      itemBuilder: (context, index) {
        if (index == 0) {
          return _OwnTile(
            entry: ownEntry,
            name: profileName,
            avatarUrl: profileAvatarUrl,
          );
        }
        final tile = others[index - 1];
        final pulse = tile.pulse;
        final note = tile.note;
        return _PulseTile(
          label: tile.displayLabel,
          initials: pulseInitials(tile.authorName),
          avatarUrl: tile.authorAvatarUrl,
          hasUnseen: pulse?.hasUnseen ?? false,
          isLive: pulse != null,
          bubble: note == null
              ? null
              : NoteBubble(
                  text: note.text,
                  onTap: () => showNoteSheet(context, note),
                ),
          // The avatar plays the Pulse when there is one; with only a Note,
          // the Note is all there is to open.
          onTap: pulse != null
              ? () => context.push('/pulse/${tile.authorId}')
              : () => showNoteSheet(context, note!),
        );
      },
    );
  }
}

class _OwnTile extends ConsumerWidget {
  const _OwnTile({required this.entry, this.name, this.avatarUrl});

  final PulseTrayEntry? entry;
  final String? name;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = entry;
    final resolvedName = live?.authorName ?? name ?? 'You';
    final question = todaysQuestion(DateTime.now());
    final myNote = ref.watch(myNoteProvider);
    // Today's answer once there is one. Until then the question — even over
    // an answer to yesterday's that is still up for everyone else.
    final answered = myNote != null && myNote.answers(question.id);

    return _PulseTile(
      label: 'Pulse',
      initials: pulseInitials(resolvedName),
      avatarUrl: live?.authorAvatarUrl ?? avatarUrl,
      hasUnseen: live?.hasUnseen ?? false,
      isLive: live != null,
      showAddBadge: true,
      bubble: NoteBubble(
        text: answered ? myNote.text : question.text,
        isQuestion: !answered,
        onTap: () => showMyNoteSheet(context),
      ),
      // With a live Pulse the tile plays it and the badge composes another;
      // with nothing posted both do the same thing, so the whole tile is a
      // single obvious target.
      onTap: () => live == null
          ? context.push('/pulse-compose')
          : context.push('/pulse/${live.authorId}'),
      onAddPressed: () => context.push('/pulse-compose'),
    );
  }
}

class _PulseTile extends StatelessWidget {
  const _PulseTile({
    required this.label,
    required this.initials,
    required this.hasUnseen,
    required this.onTap,
    this.avatarUrl,
    this.isLive = true,
    this.showAddBadge = false,
    this.onAddPressed,
    this.bubble,
  });

  final String label;
  final String initials;
  final bool hasUnseen;
  final VoidCallback onTap;
  final String? avatarUrl;
  final bool isLive;
  final bool showAddBadge;
  final VoidCallback? onAddPressed;

  /// The Note over the avatar, when there is one.
  final Widget? bubble;

  /// How far down the ring starts, leaving the top for the bubble. The bubble
  /// overlaps the ring's top edge a little, as Instagram's does.
  static const double _ringTop = 34;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SizedBox(
      width: NoteBubble.maxWidth,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: _ringTop),
            child: GestureDetector(
              onTap: onTap,
              behavior: HitTestBehavior.opaque,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PulseRing(
                    initials: initials,
                    avatarUrl: avatarUrl,
                    hasUnseen: hasUnseen,
                    isLive: isLive,
                    showAddBadge: showAddBadge,
                    onAddPressed: onAddPressed,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      // A watched ring's label recedes with it.
                      color:
                          hasUnseen || !isLive ? palette.text : palette.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Last, so it paints over the ring and takes the tap where the two
          // overlap.
          if (bubble case final bubble?) Positioned(top: 0, child: bubble),
        ],
      ),
    );
  }
}

class _TrayMessage extends StatelessWidget {
  const _TrayMessage({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return LiquidGlass(
      // Painted by the lens rather than by a fill of its own: a pane
      // over the app backdrop, like every other card.
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: double.infinity,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: palette.stroke),
        ),
        child: Text(label, style: TextStyle(color: palette.muted)),
      ),
    );
  }
}
