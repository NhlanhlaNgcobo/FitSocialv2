import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../auth/application/app_session.dart';
import '../application/pulse_providers.dart';
import '../domain/pulse_models.dart';
import 'pulse_ring.dart';

/// The horizontal rail of Pulse rings at the top of the feed.
///
/// The signed-in user's tile is always first and always present, even with
/// nothing posted — it doubles as the entry point to the composer, which is
/// the only place a Pulse can be created from the feed.
class PulseTray extends ConsumerWidget {
  const PulseTray({super.key});

  static const double height = 108;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tray = ref.watch(pulseTrayProvider);
    final profile = ref.watch(appSessionProvider).profile;

    return SizedBox(
      height: height,
      child: tray.when(
        data: (entries) => _Rail(entries: entries, profileName: profile?.displayName, profileAvatarUrl: profile?.avatarUrl),
        loading: () => _Rail(
          entries: const [],
          profileName: profile?.displayName,
          profileAvatarUrl: profile?.avatarUrl,
        ),
        error: (_, __) => const _TrayMessage(label: 'Pulse unavailable'),
      ),
    );
  }
}

class _Rail extends ConsumerWidget {
  const _Rail({
    required this.entries,
    this.profileName,
    this.profileAvatarUrl,
  });

  final List<PulseTrayEntry> entries;
  final String? profileName;
  final String? profileAvatarUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // buildPulseTray already sorts the user's own ring to the front when they
    // have one; when they don't, a placeholder tile stands in for it.
    final ownEntry = entries.isNotEmpty && entries.first.isOwn
        ? entries.first
        : null;
    final others = ownEntry == null ? entries : entries.skip(1).toList();

    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.zero,
      itemCount: others.length + 1,
      separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.md),
      itemBuilder: (context, index) {
        if (index == 0) {
          return _OwnTile(
            entry: ownEntry,
            name: profileName,
            avatarUrl: profileAvatarUrl,
          );
        }
        final entry = others[index - 1];
        return _PulseTile(
          label: entry.displayLabel,
          initials: pulseInitials(entry.authorName),
          avatarUrl: entry.authorAvatarUrl,
          hasUnseen: entry.hasUnseen,
          onTap: () => context.push('/pulse/${entry.authorId}'),
        );
      },
    );
  }
}

class _OwnTile extends StatelessWidget {
  const _OwnTile({required this.entry, this.name, this.avatarUrl});

  final PulseTrayEntry? entry;
  final String? name;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final live = entry;
    final resolvedName = live?.authorName ?? name ?? 'You';

    return _PulseTile(
      label: 'Pulse',
      initials: pulseInitials(resolvedName),
      avatarUrl: live?.authorAvatarUrl ?? avatarUrl,
      hasUnseen: live?.hasUnseen ?? false,
      isLive: live != null,
      showAddBadge: true,
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
  });

  final String label;
  final String initials;
  final bool hasUnseen;
  final VoidCallback onTap;
  final String? avatarUrl;
  final bool isLive;
  final bool showAddBadge;
  final VoidCallback? onAddPressed;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 76,
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
                color: hasUnseen || !isLive ? palette.text : palette.muted,
                fontSize: 12,
              ),
            ),
          ],
        ),
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
    return Container(
      width: double.infinity,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: palette.stroke),
      ),
      child: Text(label, style: TextStyle(color: palette.muted)),
    );
  }
}
