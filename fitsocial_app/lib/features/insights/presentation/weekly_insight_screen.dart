import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/time/period_keys.dart';
import '../../../shared/widgets/dark_card.dart';
import '../../../shared/widgets/glass.dart';
import '../../../shared/widgets/staggered_fade_in.dart';
import '../application/insight_providers.dart';
import '../data/insight_repository.dart';
import '../domain/weekly_insight.dart';
import 'weekly_insight_card.dart' show AiGeneratedLabel, WellbeingNote;

/// Last week's insight in full: a hero with the headline and summary, then
/// wins, trends against the week before and one thing to focus on, each its
/// own glass card, and last the feedback and the way to turn it off.
class WeeklyInsightScreen extends ConsumerStatefulWidget {
  const WeeklyInsightScreen({super.key});

  @override
  ConsumerState<WeeklyInsightScreen> createState() =>
      _WeeklyInsightScreenState();
}

class _WeeklyInsightScreenState extends ConsumerState<WeeklyInsightScreen>
    with SingleTickerProviderStateMixin {
  bool _refreshing = false;

  /// The sections arrive one after another, top to bottom, once.
  late final AnimationController _entrance;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(insightActionsProvider).logViewed();
    });
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
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
      final status =
          await ref.read(insightActionsProvider).request(regenerate: true);
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

    if (insight == null || !insight.hasContent) {
      return Scaffold(
        appBar: AppBar(title: const Text('WEEKLY INSIGHTS')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Text(
              'No insight for last week yet.',
              style: TextStyle(color: palette.muted),
            ),
          ),
        ),
      );
    }

    final sections = <Widget>[
      _Hero(insight: insight),
      if (insight.wellbeingNote) const WellbeingNote(),
      if (insight.wins.isNotEmpty) _WinsCard(wins: insight.wins),
      if (insight.trends.isNotEmpty) _TrendsCard(trends: insight.trends),
      if (insight.suggestion.isNotEmpty)
        _FocusCard(suggestion: insight.suggestion),
      _FeedbackCard(rating: rating, onRate: _rate),
      _ActionsCard(
        refreshing: _refreshing,
        onRefresh: _refresh,
        onHide: _hide,
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('WEEKLY INSIGHTS')),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.xl,
        ),
        itemCount: sections.length,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
        itemBuilder: (context, index) => StaggeredFadeIn(
          controller: _entrance,
          index: index,
          itemCount: sections.length + 2,
          child: sections[index],
        ),
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

/// The small-caps label every card here opens with, the same voice as the
/// "WEEKLY INSIGHTS" line on the home card.
class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.text, {this.icon, this.color});

  final String text;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tone = color ?? context.palette.muted;
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 15, color: tone),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            text,
            style: TextStyle(
              color: tone,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
        ),
      ],
    );
  }
}

/// A round badge holding an icon, tinted by what it means.
class _Badge extends StatelessWidget {
  const _Badge({
    required this.icon,
    required this.color,
    required this.fill,
    this.size = 32,
  });

  final IconData icon;
  final Color color;
  final Color fill;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
      child: Icon(icon, size: size * 0.55, color: color),
    );
  }
}

/// The week, the headline and the summary, over a wash of the brand orange.
class _Hero extends StatelessWidget {
  const _Hero({required this.insight});

  final WeeklyInsight insight;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return DarkCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(AppSpacing.lg - 4),
      backdrop: GlassBloom(colors: [palette.brand]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: palette.brandSoft,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: palette.brandSoftStroke),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.auto_awesome_rounded,
                  size: 13,
                  color: palette.brandText,
                ),
                const SizedBox(width: 5),
                Text(
                  _weekLabel(insight.weekId),
                  style: TextStyle(
                    color: palette.brandText,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            insight.headline,
            style: TextStyle(
              color: palette.text,
              fontSize: 26,
              height: 1.15,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.sm + 2),
          Text(
            insight.summary,
            style: TextStyle(color: palette.text, fontSize: 15.5, height: 1.45),
          ),
          if (insight.partialWeek) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Based on part of the week. Some days had nothing logged.',
              style: TextStyle(color: palette.muted, fontSize: 12.5),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          const AiGeneratedLabel(),
        ],
      ),
    );
  }
}

class _WinsCard extends StatelessWidget {
  const _WinsCard({required this.wins});

  final List<String> wins;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return DarkCard(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Eyebrow(
            'WINS',
            icon: Icons.emoji_events_rounded,
            color: palette.success,
          ),
          const SizedBox(height: AppSpacing.md),
          for (final (index, win) in wins.indexed) ...[
            if (index > 0) const SizedBox(height: AppSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Badge(
                  icon: Icons.check_rounded,
                  color: palette.success,
                  fill: palette.success.withValues(alpha: 0.14),
                  size: 28,
                ),
                const SizedBox(width: AppSpacing.md - 4),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      win,
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 15,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TrendsCard extends StatelessWidget {
  const _TrendsCard({required this.trends});

  final List<InsightTrend> trends;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return DarkCard(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Eyebrow('AGAINST THE WEEK BEFORE',
              icon: Icons.insights_rounded),
          const SizedBox(height: AppSpacing.xs),
          for (final (index, trend) in trends.indexed) ...[
            if (index > 0) Divider(height: 1, color: palette.stroke),
            _TrendRow(trend: trend),
          ],
        ],
      ),
    );
  }
}

class _TrendRow extends StatelessWidget {
  const _TrendRow({required this.trend});

  final InsightTrend trend;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    // Up is the one direction worth colour, as on Compare. Down is not a
    // failure to paint red, and flat is just flat.
    final (icon, tone) = switch (trend.direction) {
      TrendDirection.up => (Icons.north_east_rounded, palette.success),
      TrendDirection.down => (Icons.south_east_rounded, palette.muted),
      TrendDirection.flat => (Icons.east_rounded, palette.muted),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm + 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Badge(
            icon: icon,
            color: tone,
            fill: tone.withValues(alpha: 0.14),
            size: 36,
          ),
          const SizedBox(width: AppSpacing.md - 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  trend.metricLabel,
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  trend.note,
                  style: TextStyle(
                    color: palette.muted,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The one suggestion, set apart as the thing to carry into this week.
class _FocusCard extends StatelessWidget {
  const _FocusCard({required this.suggestion});

  final String suggestion;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return DarkCard(
      margin: EdgeInsets.zero,
      backdrop: GlassBloom(colors: [palette.brand], intensity: 0.55),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Badge(
            icon: Icons.flag_rounded,
            color: AppColors.onBrand,
            fill: palette.brand,
            size: 40,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Eyebrow('YOUR FOCUS THIS WEEK', color: palette.brandText),
                const SizedBox(height: 6),
                Text(
                  suggestion,
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 16,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedbackCard extends StatelessWidget {
  const _FeedbackCard({required this.rating, required this.onRate});

  final InsightRating? rating;
  final ValueChanged<InsightRating> onRate;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final reported = rating == InsightRating.offensive;
    return DarkCard(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Eyebrow('WAS THIS HELPFUL?'),
          const SizedBox(height: AppSpacing.sm + 4),
          // One track, the chosen answer in the brand's soft orange: the same
          // picker as Day / Week / Month on Progress.
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: palette.stroke),
            ),
            child: Row(
              children: [
                for (final option in const [
                  InsightRating.veryHelpful,
                  InsightRating.somewhatHelpful,
                  InsightRating.unhelpful,
                ])
                  Expanded(
                    child: Semantics(
                      button: true,
                      selected: rating == option,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onRate(option),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          height: 38,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: rating == option
                                ? palette.brandSoft
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            option.label,
                            style: TextStyle(
                              color: rating == option
                                  ? palette.brandText
                                  : palette.muted,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: palette.muted,
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
            onPressed: reported ? null : () => onRate(InsightRating.offensive),
            icon: const Icon(Icons.outlined_flag_rounded, size: 16),
            label: Text(
              reported ? 'Reported' : 'Report as offensive',
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionsCard extends StatelessWidget {
  const _ActionsCard({
    required this.refreshing,
    required this.onRefresh,
    required this.onHide,
  });

  final bool refreshing;
  final VoidCallback onRefresh;
  final VoidCallback onHide;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return DarkCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Column(
        children: [
          _ActionRow(
            leading: refreshing
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: palette.brand,
                    ),
                  )
                : Icon(Icons.refresh_rounded, size: 19, color: palette.text),
            title: 'Write a new one',
            subtitle: 'A couple of times a day at most',
            onTap: refreshing ? null : onRefresh,
          ),
          Divider(
            height: 1,
            indent: AppSpacing.md,
            endIndent: AppSpacing.md,
            color: palette.stroke,
          ),
          _ActionRow(
            leading: Icon(
              Icons.visibility_off_outlined,
              size: 19,
              color: palette.text,
            ),
            title: 'Hide Weekly Insights',
            subtitle: 'You can turn them back on in Settings',
            onTap: onHide,
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm + 4,
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: palette.surfaceHigh,
                shape: BoxShape.circle,
              ),
              child: leading,
            ),
            const SizedBox(width: AppSpacing.md - 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: palette.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(color: palette.muted, fontSize: 12.5),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: palette.muted, size: 20),
          ],
        ),
      ),
    );
  }
}
