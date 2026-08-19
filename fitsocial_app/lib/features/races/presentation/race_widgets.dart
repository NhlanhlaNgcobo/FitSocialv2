import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../domain/race_formatting.dart';
import '../domain/race_models.dart';
import 'race_artwork.dart';

/// A small caps section heading, matching the challenge screens.
class RaceLabel extends StatelessWidget {
  const RaceLabel(this.text, {this.colour, super.key});

  final String text;
  final Color? colour;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: colour ?? context.palette.muted,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.6,
      ),
    );
  }
}

/// A selectable pill, as used across the filter rows.
class RaceChip extends StatelessWidget {
  const RaceChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.icon,
    super.key,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final chipIcon = icon;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? palette.brand : palette.surface,
          borderRadius: BorderRadius.circular(999),
          border:
              Border.all(color: isSelected ? palette.brand : palette.stroke),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (chipIcon != null) ...[
              Icon(
                chipIcon,
                size: 15,
                // The selected pill is brand orange in both themes, so its
                // contents are pinned dark rather than themed — see the same
                // reasoning on the explore filter row.
                color: isSelected ? AppColors.onBrandInk : palette.muted,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isSelected ? AppColors.onBrandInk : palette.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A read-only tag, for the badges on a listing.
class RaceBadge extends StatelessWidget {
  const RaceBadge({
    required this.label,
    this.icon,
    this.tone,
    super.key,
  });

  /// Builds the badge for a tag, if that tag is one worth surfacing on a row.
  ///
  /// Returns null for the tags that are true of nearly everything. "Road" on a
  /// road-running calendar is not information, and a row wearing it alongside
  /// the useful badges dilutes them.
  static RaceBadge? forTag(RaceTag tag) => switch (tag) {
        RaceTag.road => null,
        RaceTag.trail =>
          const RaceBadge(label: 'Trail', icon: Icons.terrain_rounded),
        RaceTag.crossCountry =>
          const RaceBadge(label: 'XC', icon: Icons.grass_rounded),
        RaceTag.comradesQualifier => const RaceBadge(
            label: 'Comrades qualifier',
            icon: Icons.verified_rounded,
          ),
        RaceTag.twoOceansQualifier => const RaceBadge(
            label: 'Two Oceans qualifier',
            icon: Icons.verified_rounded,
          ),
        RaceTag.nightRace =>
          const RaceBadge(label: 'Night', icon: Icons.nightlight_round),
        RaceTag.womensRace =>
          const RaceBadge(label: "Women's", icon: Icons.female_rounded),
        RaceTag.charity =>
          const RaceBadge(label: 'Charity', icon: Icons.favorite_rounded),
        RaceTag.stageRace =>
          const RaceBadge(label: 'Stage race', icon: Icons.route_rounded),
        RaceTag.virtual =>
          const RaceBadge(label: 'Virtual', icon: Icons.smartphone_rounded),
      };

  final String label;
  final IconData? icon;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final colour = tone ?? palette.brand;
    final badgeIcon = icon;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colour.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (badgeIcon != null) ...[
            Icon(badgeIcon, size: 11, color: colour),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
              color: colour,
            ),
          ),
        ],
      ),
    );
  }
}

/// One race, as a row in the calendar.
class RaceCard extends StatelessWidget {
  const RaceCard({
    required this.event,
    required this.now,
    required this.isSaved,
    required this.onTap,
    required this.onToggleSaved,
    super.key,
  });

  final RaceEvent event;
  final DateTime now;
  final bool isSaved;
  final VoidCallback onTap;

  /// Null when nobody is signed in, which hides the save control rather than
  /// offering one that cannot work.
  final VoidCallback? onToggleSaved;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final price = event.priceFromLabel;
    final badges = event.tags
        .map(RaceBadge.forTag)
        .whereType<RaceBadge>()
        .toList(growable: false);
    final toggle = onToggleSaved;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: palette.stroke),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // A wide, short band rather than a square hero. This list is read by
            // somebody scanning for a free Saturday, so the cover has to add
            // identity without pushing the next race off the screen.
            AspectRatio(
              aspectRatio: 3.4,
              child: RaceCover(event: event),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _DateBlock(event: event),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              event.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                height: 1.25,
                                color: palette.text,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  Icons.place_outlined,
                                  size: 13,
                                  color: palette.muted,
                                ),
                                const SizedBox(width: 3),
                                Expanded(
                                  child: Text(
                                    event.venue.shortLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: palette.muted,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (toggle != null)
                        IconButton(
                          onPressed: toggle,
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                          tooltip:
                              isSaved ? 'Remove from my races' : 'Save race',
                          icon: Icon(
                            isSaved
                                ? Icons.bookmark_rounded
                                : Icons.bookmark_border_rounded,
                            size: 20,
                            color: isSaved ? palette.brand : palette.muted,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    RaceFormat.distanceSummary(event),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: palette.text,
                    ),
                  ),
                  if (badges.isNotEmpty || price != null) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: badges,
                          ),
                        ),
                        if (price != null) ...[
                          const SizedBox(width: AppSpacing.sm),
                          Text(
                            price,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: palette.muted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                  if (event.status.needsNotice) ...[
                    const SizedBox(height: 10),
                    _StatusNotice(status: event.status),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The date, as a block on the left of a row.
///
/// A calendar-page shape rather than a line of text: scanning a list for a free
/// Saturday is the main thing anybody does here, and a column of aligned
/// day numbers is what makes that possible at a glance.
class _DateBlock extends StatelessWidget {
  const _DateBlock({required this.event});

  final RaceEvent event;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final start = event.startAt;

    return Container(
      width: 52,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: palette.brandSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.brandSoftStroke),
      ),
      child: Column(
        children: [
          Text(
            RaceFormat.dayAndDate(start).split(' ').first.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: palette.brand,
            ),
          ),
          Text(
            start.day.toString(),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              height: 1.15,
              color: palette.text,
            ),
          ),
          Text(
            // A multi-day event says so here rather than in the title, which is
            // where the reader is already looking for the date.
            event.isMultiDay
                ? '+${event.endAt!.difference(start).inDays}d'
                : '',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: palette.muted,
            ),
          ),
        ],
      ),
    );
  }
}

/// The banner on a postponed, cancelled or closed event.
class _StatusNotice extends StatelessWidget {
  const _StatusNotice({required this.status});

  final RaceStatus status;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    // Cancelled and postponed are the ones that waste somebody's Saturday, so
    // they get the danger colour. Closed entries are merely disappointing.
    final isHard =
        status == RaceStatus.cancelled || status == RaceStatus.postponed;
    final colour = isHard ? palette.danger : palette.muted;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 13, color: colour),
          const SizedBox(width: 6),
          Text(
            status.label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: colour,
            ),
          ),
        ],
      ),
    );
  }
}

/// The empty and error states for the calendar.
class RaceMessage extends StatelessWidget {
  const RaceMessage({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final actionWidget = action;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
        children: [
          Icon(icon, size: 34, color: palette.muted),
          const SizedBox(height: AppSpacing.md),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: palette.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, height: 1.4, color: palette.muted),
          ),
          if (actionWidget != null) ...[
            const SizedBox(height: AppSpacing.md),
            actionWidget,
          ],
        ],
      ),
    );
  }
}
