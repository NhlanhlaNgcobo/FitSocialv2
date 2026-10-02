import 'package:flutter/material.dart';

import '../../../app/theme/app_palette.dart';
import '../domain/challenge_badges.dart';
import '../../../shared/widgets/liquid_glass.dart';

/// The badges somebody holds, as a row above their post grid.
///
/// Shown on every profile, not only your own. Public badges are most of the
/// social value of the whole system: a badge nobody else can see is a private
/// note, and nobody works 75 days for a private note.
class BadgeShelf extends StatelessWidget {
  const BadgeShelf({
    required this.badges,
    this.onTap,
    super.key,
  });

  final List<UserBadge> badges;
  final ValueChanged<UserBadge>? onTap;

  /// The parts of a tile that do not care what size the reader's text is: the
  /// 54pt disc, and the 6pt gap under it.
  static const double _tileFixed = 54 + 6;

  /// The label's own box at text scale 1 — two lines of 10pt at 1.2 line
  /// height — plus a little slack so a descender never sits on the edge.
  static const double _tileLabel = 10 * 1.2 * 2;
  static const double _tileSlack = 8;

  /// How tall the strip has to be for the tallest tile to fit.
  ///
  /// Only the label is scaled. Scaling the whole 92 would grow the disc too and
  /// leave a strip half full of empty space; pinning it, which is what this did
  /// before, overflowed the moment anyone turned their font size up — 4 pixels
  /// at 1.5x, 16 at 2x.
  static double heightFor(BuildContext context) =>
      _tileFixed +
      MediaQuery.textScalerOf(context).scale(_tileLabel) +
      _tileSlack;

  @override
  Widget build(BuildContext context) {
    if (badges.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: heightFor(context),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: badges.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final badge = badges[index];
          return BadgeTile(
            badge: badge,
            onTap: onTap == null ? null : () => onTap!(badge),
          );
        },
      ),
    );
  }
}

/// One badge: its mark, its name, and the count if it has been earned twice.
class BadgeTile extends StatelessWidget {
  const BadgeTile({required this.badge, this.onTap, super.key});

  final UserBadge badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 76,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: palette.brandSoft,
                    shape: BoxShape.circle,
                    border: Border.all(color: palette.brandSoftStroke),
                  ),
                  child: Icon(
                    _iconFor(badge.badge),
                    size: 26,
                    color: palette.brandText,
                  ),
                ),
                if (badge.count > 1)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: palette.brand,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: palette.background, width: 2),
                      ),
                      child: Text(
                        badge.countLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              badge.badge.label,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.muted,
                fontSize: 10,
                height: 1.2,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The sheet a tapped badge opens: what it was for, and when it was earned.
/// [onShare], when given, adds a "Share" button under the badge -- Recap
/// Cards pass it while they are switched on.
Future<void> showBadgeSheet(
  BuildContext context,
  UserBadge badge, {
  VoidCallback? onShare,
}) {
  final palette = Theme.of(context).extension<AppPalette>() ?? AppPalette.dark;

  return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => LiquidGlass(
            // A sheet always has a page behind it, which makes it the one
            // surface in the app guaranteed something worth bending.
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: palette.brandSoft,
                        shape: BoxShape.circle,
                        border: Border.all(color: palette.brandSoftStroke),
                      ),
                      child: Icon(
                        _iconFor(badge.badge),
                        size: 34,
                        color: palette.brandText,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      badge.badge.label.toUpperCase(),
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      badge.badge.description,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: palette.muted, fontSize: 14, height: 1.4),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      badge.count > 1
                          ? 'Earned ${badge.count} times. Most recently '
                              '${_dateLabel(badge.awardedAt)}.'
                          : 'Earned ${_dateLabel(badge.awardedAt)}.',
                      style: TextStyle(color: palette.muted, fontSize: 12),
                    ),
                    if (onShare != null) ...[
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          onShare();
                        },
                        icon: const Icon(Icons.ios_share_rounded),
                        label: const Text('Share'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ));
}

String _dateLabel(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}

/// The mark for a badge.
///
/// Icons rather than commissioned art, and that is a deliberate placeholder:
/// the award logic, the storage and the shelf are the parts that have to be
/// right before anything is drawn. Swapping these for real badge art later
/// touches this one function.
IconData _iconFor(ChallengeBadge badge) => switch (badge) {
      ChallengeBadge.dayOne => Icons.flag_rounded,
      ChallengeBadge.firstWeek => Icons.calendar_view_week_rounded,
      ChallengeBadge.lockedIn => Icons.lock_rounded,
      ChallengeBadge.ironMonth => Icons.fitness_center_rounded,
      ChallengeBadge.halfway => Icons.timeline_rounded,
      ChallengeBadge.theGrind => Icons.trending_up_rounded,
      ChallengeBadge.comeback => Icons.replay_rounded,
      ChallengeBadge.finisher => Icons.emoji_events_rounded,
      ChallengeBadge.flawless => Icons.auto_awesome_rounded,
      ChallengeBadge.earlyWorm => Icons.wb_twilight_rounded,
      ChallengeBadge.dawnPatrol => Icons.brightness_5_rounded,
      ChallengeBadge.sunriseSociety => Icons.wb_sunny_rounded,
      ChallengeBadge.fourAmClub => Icons.nightlight_round,
      ChallengeBadge.firstPulse => Icons.bolt_rounded,
      ChallengeBadge.century => Icons.looks_one_rounded,
      ChallengeBadge.pointMachine => Icons.stars_rounded,
      ChallengeBadge.supporter => Icons.favorite_rounded,
      ChallengeBadge.goalGetter => Icons.track_changes_rounded,
      ChallengeBadge.onTarget => Icons.gps_fixed_rounded,
      ChallengeBadge.relentless => Icons.local_fire_department_rounded,
      ChallengeBadge.challengeFinisher => Icons.sports_score_rounded,
      ChallengeBadge.podium => Icons.leaderboard_rounded,
      ChallengeBadge.champion => Icons.workspace_premium_rounded,
    };
