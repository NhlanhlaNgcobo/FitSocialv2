import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_palette.dart';
import '../../app/theme/app_spacing.dart';
import '../../features/main/application/content_providers.dart';
import '../../features/main/domain/app_models.dart';
import 'dark_card.dart';

/// Followers / Following for one profile, centred as a pair.
///
/// The columns are laid out from fixed labels rather than from whatever the
/// repository returns, so the row keeps its shape while the counts are still
/// loading or if the read fails. Each column gets the same fixed width, which
/// keeps the divider on the centre line however wide the numbers grow.
///
/// On your own profile each column is a way in to the list behind it. On
/// anyone else's it is a number and nothing more: who follows whom in detail
/// is the account owner's to look at, so the tap target simply is not there —
/// there is no route that would open somebody else's list to refuse.
class ProfileStatsBar extends ConsumerWidget {
  const ProfileStatsBar({required this.userId, super.key});

  final String userId;

  /// The labels, in the order they are drawn. Each column's direction is what
  /// its tap opens, so the two lists are addressed by the same value the
  /// repository labels the counts with.
  static const _kinds = FollowListKind.values;

  /// Fixed per-column width, so the pair stays symmetric about the divider.
  static const double _columnWidth = 110;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(profileStatsProvider(userId));
    final currentUserId = ref.watch(currentUserIdProvider);
    // An empty id is the header drawn before the uid resolves, not a match.
    final isOwnProfile = userId.isNotEmpty && userId == currentUserId;

    // A pane, like the summary blocks on the home page. This is the profile's
    // headline figure and it was the one piece of it with no surface under it
    // at all -- bare numbers between an avatar and a photo grid, which read as
    // a gap rather than as a block.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: DarkCard(
        // Tight, and with no margin of its own. The profile stacks this into a
        // fixed column that also has to fit a grid, so every pixel the pane
        // adds comes straight off the photos -- and past a certain text size,
        // off the bottom of the screen.
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < _kinds.length; i++) ...[
              if (i > 0) const _StatDivider(),
              SizedBox(
                width: _columnWidth,
                child: _StatColumn(
                  label: _kinds[i].label,
                  value: _value(stats, _kinds[i].label),
                  onTap: isOwnProfile
                      ? () => context.push(
                            '/connections?tab=${_kinds[i].routeTab}',
                          )
                      : null,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _value(AsyncValue<List<ProfileStat>> stats, String label) {
    return stats.maybeWhen(
      data: (list) {
        for (final stat in list) {
          if (stat.label == label) return stat.value;
        }
        return '--';
      },
      orElse: () => '--',
    );
  }
}

class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 30,
      color: context.palette.stroke,
    );
  }
}

class _StatColumn extends StatelessWidget {
  const _StatColumn({
    required this.label,
    required this.value,
    this.onTap,
  });

  final String label;
  final String value;

  /// Null on someone else's profile, which is what makes the column inert
  /// there rather than merely unresponsive.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final column = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 19,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: TextStyle(color: palette.muted, fontSize: 13),
        ),
      ],
    );

    if (onTap == null) return column;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.nested),
      // Padded rather than sized: the pane is deliberately tight, and a
      // minimum height here would grow it. The vertical padding plus the two
      // lines of text already clear a comfortable target.
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: column,
      ),
    );
  }
}
