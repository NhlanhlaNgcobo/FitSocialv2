import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/activity_grid.dart';
import '../../../shared/widgets/bottom_nav.dart';
import '../../../shared/widgets/brand_image_tile.dart';
import '../../../shared/widgets/stat_tile.dart';
import '../../music/application/music_providers.dart';
import '../../music/presentation/connect_music_action.dart';
import '../../music/presentation/music_player_card.dart';
import '../application/content_providers.dart';
import '../application/music_integration_controller.dart';
import '../domain/app_models.dart';

class ActivityScreen extends ConsumerWidget {
  const ActivityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final musicState = ref.watch(musicIntegrationControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(musicState.selectedSection == ActivitySection.progress
            ? 'Progress'
            : musicState.selectedSection.label),
        actions: [
          IconButton(
            onPressed: () => context.push('/achievements'),
            icon: const Icon(Icons.local_fire_department_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md + FitSocialBottomNav.clearance(context),
        ),
        children: [
          _ActivitySectionPicker(
            selectedSection: musicState.selectedSection,
            onSelected: (section) => ref
                .read(musicIntegrationControllerProvider.notifier)
                .selectSection(section),
          ),
          const SizedBox(height: AppSpacing.md),
          switch (musicState.selectedSection) {
            ActivitySection.progress => const _ProgressSection(),
            ActivitySection.music => const _MusicSection(),
          },
        ],
      ),
    );
  }
}

class _ProgressSection extends ConsumerWidget {
  const _ProgressSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = ref.watch(progressMetricsProvider);

    return Column(
      children: [
        // No fixed range: this is the card you switch between 7D, 30D and 1Y.
        const ActivityGridCard(),
        const SizedBox(height: AppSpacing.md),
        metrics.when(
          data: (data) => data.isEmpty
              ? const _EmptyState(
                  icon: Icons.insights_rounded,
                  title: 'No progress yet',
                  message:
                      'Log a workout, run, or meal and your stats will start '
                      'showing up here.',
                  ctaLabel: 'Log an activity',
                  ctaRoute: '/create',
                )
              : Column(children: _buildMetricTiles(data)),
          loading: () => const _ProgressPlaceholder(label: 'Loading progress...'),
          error: (_, __) => const _ProgressPlaceholder(label: 'Progress unavailable'),
        ),
      ],
    );
  }

  List<Widget> _buildMetricTiles(List<ProgressMetric> metrics) {
    final items = <Widget>[];
    for (var i = 0; i < metrics.length; i++) {
      final metric = metrics[i];
      items.add(
        StatTile(
          label: metric.label,
          value: metric.value,
          delta: metric.delta,
          chartBars: metric.chartBars,
        ),
      );
      if (i != metrics.length - 1) {
        items.add(const SizedBox(height: AppSpacing.md));
      }
    }
    return items;
  }
}

class _MusicSection extends ConsumerWidget {
  const _MusicSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connections = ref.watch(musicConnectionsProvider);

    return Column(
      children: [
        // The hero card is the pitch for connecting an account. Once one is
        // linked it has made its case, so the player replaces it rather than
        // stacking underneath and pushing the controls down the page.
        if (connections.hasAnyConnection)
          const MusicPlayerCard()
        else
          const _MusicHeroCard(),
        const SizedBox(height: AppSpacing.md),
        const ConnectMusicAction(),
      ],
    );
  }
}

class _ActivitySectionPicker extends StatelessWidget {
  const _ActivitySectionPicker({
    required this.selectedSection,
    required this.onSelected,
  });

  final ActivitySection selectedSection;
  final ValueChanged<ActivitySection> onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.stroke),
      ),
      child: Row(
        children: ActivitySection.values
            .map(
              (section) => Expanded(
                child: GestureDetector(
                  onTap: () => onSelected(section),
                  child: Container(
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selectedSection == section
                          ? AppColors.orangeBright.withValues(alpha: 0.18)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      section.label,
                      style: TextStyle(
                        color: selectedSection == section
                            ? AppColors.orangeBright
                            : palette.muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _MusicHeroCard extends StatelessWidget {
  const _MusicHeroCard();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    // The photo stays in both themes, but the wash over it does not. On dark
    // it is a heavy black scrim; on light it is an equally heavy white one,
    // which leaves the gym shot as a faint ghost and lets the card sit as a
    // light card among the light cards around it. Washing rather than dropping
    // the image keeps the hero feeling like a hero.
    final wash =
        palette.isDark ? const Color(0x7A050505) : const Color(0xE0FFFFFF);

    // Deepens toward the bottom, where the copy sits, so the text always has
    // its strongest backing — dark-on-dark, light-on-light.
    final scrim = palette.isDark
        ? const [Color(0x22050505), Color(0xC8050505)]
        : const [Color(0x00FFFFFF), Color(0xF0FFFFFF)];

    return SizedBox(
      height: 184,
      child: Stack(
        children: [
          Positioned.fill(
            child: BrandImageTile(
              tile: AppVisualTile.groupTraining,
              borderRadius: const BorderRadius.all(Radius.circular(24)),
              overlay: wash,
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: palette.stroke),
                gradient: LinearGradient(
                  colors: scrim,
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _MusicBadge(),
                const Spacer(),
                // Back on the palette: the backdrop under this text now flips
                // with the theme, so the text has to follow it.
                Text(
                  'Music That Fits the Session',
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                // maxLines guards the fixed-height card against overflow at
                // larger system font scales.
                Text(
                  'Preview provider-aware playlists, create your own gym mixes, and keep users inside the flow without mid-set app switching.',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: palette.muted, height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MusicBadge extends StatelessWidget {
  const _MusicBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.orangeBright.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.orangeBright.withValues(alpha: 0.4)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.headphones_rounded, size: 16, color: AppColors.orangeBright),
          SizedBox(width: 6),
          Text(
            'Music Preview',
            style: TextStyle(
              color: AppColors.orangeBright,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressPlaceholder extends StatelessWidget {
  const _ProgressPlaceholder({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: palette.stroke),
      ),
      child: Text(
        label,
        style: TextStyle(color: palette.muted),
      ),
    );
  }
}

/// A friendly empty-state card: icon, title, message, and an optional CTA
/// that routes somewhere useful. Used where a list can legitimately be empty.
class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.ctaLabel,
    this.ctaRoute,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? ctaLabel;
  final String? ctaRoute;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xl,
      ),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: palette.stroke),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.orangeBright.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.orangeBright, size: 30),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: palette.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.muted, fontSize: 14),
          ),
          if (ctaLabel != null && ctaRoute != null) ...[
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.orangeBright,
                side: const BorderSide(color: AppColors.orangeBright),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () => context.go(ctaRoute!),
              child: Text(ctaLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

