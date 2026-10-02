import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/time/period_keys.dart';
import '../application/insight_providers.dart';
import '../data/insight_repository.dart';
import '../domain/weekly_insight.dart';
import 'weekly_insight_card.dart' show AiGeneratedLabel, WellbeingNote;

/// Last week's insight in full: summary, wins, trends against the week before,
/// one suggestion, then the feedback buttons and the way to turn it off.
class WeeklyInsightScreen extends ConsumerStatefulWidget {
  const WeeklyInsightScreen({super.key});

  @override
  ConsumerState<WeeklyInsightScreen> createState() =>
      _WeeklyInsightScreenState();
}

class _WeeklyInsightScreenState extends ConsumerState<WeeklyInsightScreen> {
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(insightActionsProvider).logViewed();
    });
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    try {
      final status = await ref
          .read(insightActionsProvider)
          .request(regenerate: true);
      if (status == InsightStatus.failed) {
        _say("We couldn't write a new insight just now. Try again later.");
      }
    } on InsightRefused catch (refused) {
      _say(refused.message);
    } catch (_) {
      _say('That did not work. Check your connection.');
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _rate(InsightRating rating) async {
    try {
      await ref.read(insightActionsProvider).rate(rating);
      _say(
        rating == InsightRating.offensive
            ? "Thanks for telling us. We'll look into it."
            : 'Thanks for the feedback.',
      );
    } catch (_) {
      _say('That did not save. Check your connection.');
    }
  }

  Future<void> _hide() async {
    try {
      await ref.read(insightActionsProvider).setHidden(true);
      _say('Weekly Insights are off. Turn them back on in Settings.');
      if (mounted) Navigator.of(context).maybePop();
    } catch (_) {
      _say('That did not save. Check your connection.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final insight = ref.watch(weeklyInsightProvider).valueOrNull;
    final rating = ref.watch(insightRatingProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('WEEKLY INSIGHTS')),
      body: insight == null || !insight.hasContent
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Text(
                  'No insight for last week yet.',
                  style: TextStyle(color: palette.muted),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                Text(
                  _weekLabel(insight.weekId),
                  style: TextStyle(
                    color: palette.brandText,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  insight.headline,
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  insight.summary,
                  style: TextStyle(color: palette.text, fontSize: 15.5),
                ),
                if (insight.partialWeek) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Based on part of the week -- some days had nothing logged.',
                    style: TextStyle(color: palette.muted, fontSize: 12.5),
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                const AiGeneratedLabel(),
                if (insight.wellbeingNote) ...[
                  const SizedBox(height: AppSpacing.md),
                  const WellbeingNote(),
                ],
                if (insight.wins.isNotEmpty) ...[
                  const _SectionTitle('Wins'),
                  for (final win in insight.wins)
                    _Line(
                      icon: Icons.check_circle_outline_rounded,
                      color: palette.success,
                      text: win,
                    ),
                ],
                if (insight.trends.isNotEmpty) ...[
                  const _SectionTitle('Compared with the week before'),
                  for (final trend in insight.trends)
                    _Line(
                      icon: switch (trend.direction) {
                        TrendDirection.up => Icons.trending_up_rounded,
                        TrendDirection.down => Icons.trending_down_rounded,
                        TrendDirection.flat => Icons.trending_flat_rounded,
                      },
                      color: palette.brand,
                      text: '${trend.metricLabel}: ${trend.note}',
                    ),
                ],
                if (insight.suggestion.isNotEmpty) ...[
                  const _SectionTitle('For this week'),
                  _Line(
                    icon: Icons.flag_outlined,
                    color: palette.brand,
                    text: insight.suggestion,
                  ),
                ],
                const _SectionTitle('Was this helpful?'),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final option in const [
                      InsightRating.veryHelpful,
                      InsightRating.somewhatHelpful,
                      InsightRating.unhelpful,
                    ])
                      ChoiceChip(
                        label: Text(option.label),
                        selected: rating == option,
                        onSelected: (_) => _rate(option),
                      ),
                  ],
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: rating == InsightRating.offensive
                        ? null
                        : () => _rate(InsightRating.offensive),
                    icon: const Icon(Icons.flag_rounded, size: 18),
                    label: Text(
                      rating == InsightRating.offensive
                          ? 'Reported'
                          : 'Report as offensive',
                    ),
                  ),
                ),
                const Divider(height: AppSpacing.lg),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: _refreshing
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                  title: const Text('Write a new one'),
                  subtitle: const Text('A couple of times a day at most'),
                  onTap: _refreshing ? null : _refresh,
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.visibility_off_outlined),
                  title: const Text('Hide Weekly Insights'),
                  subtitle: const Text('You can turn them back on in Settings'),
                  onTap: _hide,
                ),
              ],
            ),
    );
  }
}

const _months = [
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

/// "WEEK OF 21 SEP" from an ISO week id.
String _weekLabel(String weekId) {
  final start = weekStartDayKey(weekId);
  final month = int.parse(start.substring(5, 7));
  final day = int.parse(start.substring(8, 10));
  return 'WEEK OF $day ${_months[month - 1].toUpperCase()}';
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: AppSpacing.sm),
      child: Text(
        text,
        style: TextStyle(
          color: context.palette.text,
          fontSize: 15,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: context.palette.text, fontSize: 14.5),
            ),
          ),
        ],
      ),
    );
  }
}
