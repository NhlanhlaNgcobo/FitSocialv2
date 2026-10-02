import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/liquid_glass.dart';
import '../application/insight_providers.dart';
import '../domain/weekly_insight.dart';

/// Last week's insight on the home feed: the headline and summary, labelled as
/// AI-written, and a way in to the rest.
///
/// Draws nothing at all -- not even its spacing -- while the feature is off or
/// hidden, while it loads, and for an insight that failed: a card that might
/// be wrong is worse than no card.
class WeeklyInsightCard extends ConsumerWidget {
  const WeeklyInsightCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(weeklyInsightsEnabledProvider)) {
      return const SizedBox.shrink();
    }
    ref.watch(insightAutoRequestProvider);

    final insight = ref.watch(weeklyInsightProvider).valueOrNull;
    if (insight == null) return const SizedBox.shrink();
    final insufficient = insight.status == InsightStatus.insufficient;
    if (!insight.hasContent && !insufficient) return const SizedBox.shrink();

    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: LiquidGlass(
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: insufficient ? null : () => context.push('/insights'),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: palette.stroke),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.auto_awesome_rounded,
                      size: 16,
                      color: palette.brand,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'WEEKLY INSIGHTS',
                      style: TextStyle(
                        color: palette.brandText,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const Spacer(),
                    if (!insufficient)
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: palette.muted,
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                if (insufficient)
                  Text(
                    'Not enough data from last week for an insight yet. '
                    'Log a few days this week and check back on Monday.',
                    style: TextStyle(color: palette.text, fontSize: 15),
                  )
                else ...[
                  Text(
                    insight.headline,
                    style: TextStyle(
                      color: palette.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    insight.summary,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: palette.text, fontSize: 14),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const AiGeneratedLabel(),
                ],
                if (insight.wellbeingNote) ...[
                  const SizedBox(height: AppSpacing.sm),
                  const WellbeingNote(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Written by AI from your logged data" -- on every surface an insight shows.
class AiGeneratedLabel extends StatelessWidget {
  const AiGeneratedLabel({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      children: [
        Icon(Icons.info_outline_rounded, size: 13, color: palette.muted),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            'Written by AI from your logged data',
            style: TextStyle(color: palette.muted, fontSize: 11.5),
          ),
        ),
      ],
    );
  }
}

/// The gentle note shown when the server flagged the week's meal logging.
class WellbeingNote extends StatelessWidget {
  const WellbeingNote({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: palette.brandSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.brandSoftStroke),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.favorite_outline_rounded, size: 16, color: palette.brand),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              kWellbeingNote,
              style: TextStyle(color: palette.text, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
