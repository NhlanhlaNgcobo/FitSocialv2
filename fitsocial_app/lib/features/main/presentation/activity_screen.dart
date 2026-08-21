import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/bottom_nav.dart';
import '../../../shared/widgets/brand_image_tile.dart';
import '../../music/application/music_providers.dart';
import '../../music/presentation/connect_music_action.dart';
import '../../music/presentation/music_player_card.dart';
import '../application/music_integration_controller.dart';
import '../domain/app_models.dart';
import 'progress_section.dart';
import '../../music/presentation/music_island_action.dart';
import '../../../shared/widgets/liquid_glass.dart';

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
          const MusicIslandAction(),
          // All three belong to Progress rather than to Music, so they go when
          // the other section is showing — a meal summary reached from a
          // playlist screen is a button in the wrong place.
          if (musicState.selectedSection == ActivitySection.progress) ...[
            IconButton(
              onPressed: () => context.push('/bmi'),
              tooltip: 'BMI',
              icon: const Icon(Icons.monitor_heart_outlined),
            ),
            IconButton(
              onPressed: () => context.push('/meal-tracking'),
              tooltip: 'Meal tracking',
              icon: const Icon(Icons.restaurant_outlined),
            ),
            IconButton(
              onPressed: () => context.push('/achievements'),
              tooltip: 'Achievements',
              icon: const Icon(Icons.local_fire_department_outlined),
            ),
          ],
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
            ActivitySection.progress => const ProgressSection(),
            ActivitySection.music => const _MusicSection(),
          },
        ],
      ),
    );
  }
}

class _MusicSection extends ConsumerWidget {
  const _MusicSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Any music source at all, not just a linked account: notification access
    // alone is enough to drive the player, and it is the route most users take.
    final hasMusicSource = ref.watch(hasMusicSourceProvider);
    final accountsEnabled = ref.watch(musicAccountsEnabledProvider);

    // With accounts off, the phone's own session is the only source there is —
    // so once it is granted there is nothing left to set up. Leaving the call
    // to action there put a bright "Set up music" button directly under a
    // player that was visibly playing, which reads as the feature being broken
    // rather than as an offer. With accounts on it stays: there is always
    // another service to add.
    final offersSetup = accountsEnabled || !hasMusicSource;

    return Column(
      children: [
        // The hero card is the pitch for setting music up. Once there is a way
        // in — an account, or access to the phone's own session — it has made
        // its case, so the player replaces it rather than stacking underneath
        // and pushing the controls down the page.
        if (hasMusicSource)
          const MusicPlayerCard()
        else
          const _MusicHeroCard(),
        if (offersSetup) ...[
          const SizedBox(height: AppSpacing.md),
          const ConnectMusicAction(),
        ],
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
    return LiquidGlass(
      // Painted by the lens rather than by a fill of its own: a pane
      // over the app backdrop, like every other card.
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
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
                            ? palette.brandSoft
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        section.label,
                        style: TextStyle(
                          color: selectedSection == section
                              ? palette.brandText
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
                  'Play from any music app and control it right here — see the '
                  'track, skip it, scrub it, without leaving your workout.',
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
    final palette = context.palette;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: palette.brandSoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.brandSoftStroke),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.headphones_rounded, size: 16, color: palette.brand),
          const SizedBox(width: 6),
          Text(
            'Music Preview',
            style: TextStyle(
              color: palette.brandText,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
