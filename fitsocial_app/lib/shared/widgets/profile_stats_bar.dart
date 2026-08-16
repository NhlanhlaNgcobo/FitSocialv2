import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_palette.dart';
import '../../app/theme/app_spacing.dart';
import '../../features/main/application/content_providers.dart';
import '../../features/main/domain/app_models.dart';

/// Followers / Following for one profile, centred as a pair.
///
/// The columns are laid out from fixed labels rather than from whatever the
/// repository returns, so the row keeps its shape while the counts are still
/// loading or if the read fails. Each column gets the same fixed width, which
/// keeps the divider on the centre line however wide the numbers grow.
class ProfileStatsBar extends ConsumerWidget {
  const ProfileStatsBar({required this.userId, super.key});

  final String userId;

  static const _labels = ['Followers', 'Following'];

  /// Fixed per-column width, so the pair stays symmetric about the divider.
  static const double _columnWidth = 110;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(profileStatsProvider(userId));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < _labels.length; i++) ...[
            if (i > 0) const _StatDivider(),
            SizedBox(
              width: _columnWidth,
              child: _StatColumn(
                label: _labels[i],
                value: _value(stats, _labels[i]),
              ),
            ),
          ],
        ],
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
  const _StatColumn({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
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
          style: TextStyle(color: context.palette.muted, fontSize: 13),
        ),
      ],
    );
  }
}
