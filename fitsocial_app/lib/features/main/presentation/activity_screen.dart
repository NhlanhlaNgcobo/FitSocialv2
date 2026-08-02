import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/brand_image_tile.dart';
import '../../../shared/widgets/dark_card.dart';
import '../../../shared/widgets/stat_tile.dart';
import '../../music/application/spotify_providers.dart';
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
        padding: const EdgeInsets.all(AppSpacing.md),
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
            ActivitySection.podcasts => const _PodcastSection(),
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
        const _RangeTabs(),
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
    final musicState = ref.watch(musicIntegrationControllerProvider);
    final playlists =
        ref.watch(workoutPlaylistsProvider(musicState.selectedWorkoutType));

    return Column(
      children: [
        const _MusicHeroCard(),
        const SizedBox(height: AppSpacing.md),
        _MusicProviderConnections(state: musicState),
        const SizedBox(height: AppSpacing.md),
        _CreatePlaylistCard(state: musicState),
        const SizedBox(height: AppSpacing.md),
        _WorkoutTypePicker(
          selectedType: musicState.selectedWorkoutType,
          onSelected: (type) => ref
              .read(musicIntegrationControllerProvider.notifier)
              .selectWorkoutType(type),
        ),
        const SizedBox(height: AppSpacing.md),
        playlists.when(
          data: (items) => _PlaylistList(
            playlists: items,
            state: musicState,
          ),
          loading: () =>
              const _ProgressPlaceholder(label: 'Loading playlist matches...'),
          error: (_, __) => const _ProgressPlaceholder(
            label: 'Playlist recommendations unavailable',
          ),
        ),
      ],
    );
  }
}

class _PodcastSection extends ConsumerWidget {
  const _PodcastSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final musicState = ref.watch(musicIntegrationControllerProvider);
    final podcasts = ref.watch(podcastRecommendationsProvider);

    return Column(
      children: [
        const _PodcastHeroCard(),
        const SizedBox(height: AppSpacing.md),
        _PodcastCategoryPicker(
          selectedCategory: musicState.selectedPodcastCategory,
          onSelected: (category) => ref
              .read(musicIntegrationControllerProvider.notifier)
              .selectPodcastCategory(category),
        ),
        const SizedBox(height: AppSpacing.md),
        podcasts.when(
          data: (items) {
            final filtered = items
                .where((item) => item.category == musicState.selectedPodcastCategory)
                .toList();
            if (filtered.isEmpty) {
              return const _ProgressPlaceholder(
                label: 'No podcast recommendations available for this topic yet.',
              );
            }
            return Column(
              children: [
                for (var i = 0; i < filtered.length; i++) ...[
                  _PodcastCard(
                    recommendation: filtered[i],
                    connected: musicState.isConnected(filtered[i].provider),
                  ),
                  if (i != filtered.length - 1)
                    const SizedBox(height: AppSpacing.md),
                ],
              ],
            );
          },
          loading: () =>
              const _ProgressPlaceholder(label: 'Loading self-improvement podcasts...'),
          error: (_, __) => const _ProgressPlaceholder(
            label: 'Podcast recommendations unavailable',
          ),
        ),
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
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.stroke),
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
                            : AppColors.muted,
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
    return SizedBox(
      height: 184,
      child: Stack(
        children: [
          const Positioned.fill(
            child: BrandImageTile(
              tile: AppVisualTile.groupTraining,
              borderRadius: BorderRadius.all(Radius.circular(24)),
              overlay: Color(0x7A050505),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.stroke),
                gradient: const LinearGradient(
                  colors: [Color(0x22050505), Color(0xC8050505)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _MusicBadge(),
                Spacer(),
                Text(
                  'Music That Fits the Session',
                  style: TextStyle(
                    color: AppColors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 8),
                // maxLines guards the fixed-height card against overflow at
                // larger system font scales.
                Text(
                  'Preview provider-aware playlists, create your own gym mixes, and keep users inside the flow without mid-set app switching.',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.muted, height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PodcastHeroCard extends StatelessWidget {
  const _PodcastHeroCard();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 160,
      child: Stack(
        children: [
          const Positioned.fill(
            child: BrandImageTile(
              tile: AppVisualTile.heroPortrait,
              borderRadius: BorderRadius.all(Radius.circular(24)),
              overlay: Color(0x7A050505),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.stroke),
                gradient: const LinearGradient(
                  colors: [Color(0x22050505), Color(0xCE050505)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PodcastBadge(),
                Spacer(),
                Text(
                  'Self-Improvement Audio',
                  style: TextStyle(
                    color: AppColors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Recommend podcasts that support discipline, mindset, recovery, and growth alongside fitness progress.',
                  style: TextStyle(color: AppColors.muted, height: 1.45),
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

class _PodcastBadge extends StatelessWidget {
  const _PodcastBadge();

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
          Icon(Icons.mic_rounded, size: 16, color: AppColors.orangeBright),
          SizedBox(width: 6),
          Text(
            'Growth Layer',
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

class _MusicProviderConnections extends ConsumerWidget {
  const _MusicProviderConnections({required this.state});

  final MusicIntegrationState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spotify = ref.watch(spotifyConnectionProvider);

    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _ProviderTile(
                service: MusicProviderService.spotify,
                connected: spotify.isConnected,
                busy: spotify.isBusy,
                primary: state.primaryService == MusicProviderService.spotify,
                icon: Icons.multitrack_audio_rounded,
                accent: const Color(0xFF1ED760),
                description: spotify.isConnected
                    ? 'Connected as ${spotify.profile?.displayName ?? 'your account'}'
                        '${spotify.profile?.isPremium == false ? ' (free account — playback control needs Premium)' : ''}'
                    : 'Sign in with Spotify to pull in your playlists.',
                actionLabel:
                    spotify.isConnected ? 'Disconnect' : 'Connect Spotify',
                onTap: () {
                  final controller =
                      ref.read(spotifyConnectionProvider.notifier);
                  if (spotify.isConnected) {
                    controller.disconnect();
                  } else {
                    controller.connect();
                  }
                },
                onSetPrimary: () => ref
                    .read(musicIntegrationControllerProvider.notifier)
                    .setPrimaryService(MusicProviderService.spotify),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _ProviderTile(
                service: MusicProviderService.appleMusic,
                connected: false,
                busy: false,
                primary: false,
                enabled: false,
                icon: Icons.library_music_rounded,
                accent: const Color(0xFFFF3B30),
                description:
                    'Coming with the iOS release — Apple Music requires '
                    'MusicKit and an Apple Developer account.',
                actionLabel: 'Not available yet',
                onTap: () {},
                onSetPrimary: () {},
              ),
            ),
          ],
        ),
        if (spotify.errorMessage != null) ...[
          const SizedBox(height: AppSpacing.md),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.stroke),
            ),
            child: Text(
              spotify.errorMessage!,
              style: const TextStyle(
                color: AppColors.orangeBright,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ProviderTile extends StatelessWidget {
  const _ProviderTile({
    required this.service,
    required this.connected,
    required this.primary,
    required this.icon,
    required this.accent,
    required this.description,
    required this.actionLabel,
    required this.onTap,
    required this.onSetPrimary,
    this.busy = false,
    this.enabled = true,
  });

  final MusicProviderService service;
  final bool connected;
  final bool primary;
  final IconData icon;
  final Color accent;
  final String description;
  final String actionLabel;
  final VoidCallback onTap;
  final VoidCallback onSetPrimary;
  final bool busy;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return DarkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: accent),
              ),
              const Spacer(),
              if (primary)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.orangeBright.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Primary',
                    style: TextStyle(
                      color: AppColors.orangeBright,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            service.label,
            style: const TextStyle(
              color: AppColors.white,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: const TextStyle(color: AppColors.muted, height: 1.4),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: (!enabled || busy) ? null : onTap,
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.orangeBright,
                      ),
                    )
                  : Text(actionLabel),
            ),
          ),
          if (connected && !primary) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: onSetPrimary,
                child: const Text('Set as Primary'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CreatePlaylistCard extends ConsumerStatefulWidget {
  const _CreatePlaylistCard({required this.state});

  final MusicIntegrationState state;

  @override
  ConsumerState<_CreatePlaylistCard> createState() => _CreatePlaylistCardState();
}

class _CreatePlaylistCardState extends ConsumerState<_CreatePlaylistCard> {
  late final TextEditingController _controller;
  MusicProviderService _provider = MusicProviderService.spotify;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final created = widget.state.createdPlaylists;
    final canCreate = _controller.text.trim().isNotEmpty;

    return DarkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Create Gym Playlist',
            style: TextStyle(
              color: AppColors.white,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Let users build workout-type-specific playlists that can later sync out to Spotify or Apple Music.',
            style: TextStyle(color: AppColors.muted, height: 1.45),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _controller,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'e.g. Leg Day Amapiano Push',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<MusicProviderService>(
                  initialValue: _provider,
                  items: MusicProviderService.values
                      .map(
                        (service) => DropdownMenuItem(
                          value: service,
                          child: Text(service.label),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _provider = value;
                    });
                  },
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: canCreate
                      ? () {
                          ref
                              .read(musicIntegrationControllerProvider.notifier)
                              .createPlaylist(
                                name: _controller.text,
                                workoutType: widget.state.selectedWorkoutType,
                                provider: _provider,
                              );
                          _controller.clear();
                          setState(() {});
                        }
                      : null,
                  icon: const Icon(Icons.playlist_add_rounded),
                  label: const Text('Create'),
                ),
              ),
            ],
          ),
          if (created.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            const Text(
              'Your Playlist Ideas',
              style: TextStyle(
                color: AppColors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < created.length && i < 3; i++) ...[
              _CreatedPlaylistTile(playlist: created[i]),
              if (i != created.length - 1 && i < 2)
                const SizedBox(height: AppSpacing.sm),
            ],
          ],
        ],
      ),
    );
  }
}

class _CreatedPlaylistTile extends StatelessWidget {
  const _CreatedPlaylistTile({required this.playlist});

  final UserCreatedPlaylist playlist;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.stroke),
      ),
      child: Row(
        children: [
          const Icon(Icons.queue_music_rounded, color: AppColors.orangeBright),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  playlist.name,
                  style: const TextStyle(
                    color: AppColors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${playlist.workoutType.label} • ${playlist.provider.label}',
                  style: const TextStyle(color: AppColors.muted),
                ),
              ],
            ),
          ),
          const Text(
            'Draft',
            style: TextStyle(color: AppColors.orangeBright, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _WorkoutTypePicker extends StatelessWidget {
  const _WorkoutTypePicker({
    required this.selectedType,
    required this.onSelected,
  });

  final WorkoutType selectedType;
  final ValueChanged<WorkoutType> onSelected;

  @override
  Widget build(BuildContext context) {
    return DarkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Workout-Matched Playlists',
            style: TextStyle(
              color: AppColors.white,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'FitSocial can suggest music for strength, cardio, HIIT, runs, or recovery while learning preferred genres over time.',
            style: TextStyle(color: AppColors.muted, height: 1.45),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: WorkoutType.values
                .map(
                  (type) => _WorkoutChip(
                    label: type.label,
                    selected: type == selectedType,
                    onTap: () => onSelected(type),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _WorkoutChip extends StatelessWidget {
  const _WorkoutChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.orangeBright.withValues(alpha: 0.18) : AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AppColors.orangeBright : AppColors.stroke,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.orangeBright : AppColors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _PodcastCategoryPicker extends StatelessWidget {
  const _PodcastCategoryPicker({
    required this.selectedCategory,
    required this.onSelected,
  });

  final PodcastCategory selectedCategory;
  final ValueChanged<PodcastCategory> onSelected;

  @override
  Widget build(BuildContext context) {
    return DarkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Self-Improvement Topics',
            style: TextStyle(
              color: AppColors.white,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Support users with podcasts that build mindset, discipline, recovery habits, and growth outside training.',
            style: TextStyle(color: AppColors.muted, height: 1.45),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: PodcastCategory.values
                .map(
                  (category) => _WorkoutChip(
                    label: category.label,
                    selected: category == selectedCategory,
                    onTap: () => onSelected(category),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _PlaylistList extends StatelessWidget {
  const _PlaylistList({
    required this.playlists,
    required this.state,
  });

  final List<WorkoutPlaylist> playlists;
  final MusicIntegrationState state;

  @override
  Widget build(BuildContext context) {
    final preferredService = state.primaryService;
    final visiblePlaylists = state.hasAnyConnection
        ? playlists.where((playlist) => playlist.provider == preferredService).toList()
        : playlists;

    if (visiblePlaylists.isEmpty) {
      return const _ProgressPlaceholder(
        label: 'No playlist previews match the current provider selection yet.',
      );
    }

    return Column(
      children: [
        for (var i = 0; i < visiblePlaylists.length; i++) ...[
          _PlaylistCard(
            playlist: visiblePlaylists[i],
            connected: state.isConnected(visiblePlaylists[i].provider),
          ),
          if (i != visiblePlaylists.length - 1) const SizedBox(height: AppSpacing.md),
        ],
        const SizedBox(height: AppSpacing.md),
        const _PlaylistInsightCard(),
      ],
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  const _PlaylistCard({
    required this.playlist,
    required this.connected,
  });

  final WorkoutPlaylist playlist;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 168,
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(
                  colors: playlist.backgroundColors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),
          if (playlist.visualTile != null)
            Positioned.fill(
              child: BrandImageTile(
                tile: playlist.visualTile!,
                borderRadius: BorderRadius.circular(24),
                overlay: const Color(0x6A050505),
              ),
            ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.stroke),
                gradient: const LinearGradient(
                  colors: [Color(0x22050505), Color(0xD0050505)],
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
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        playlist.provider.label,
                        style: const TextStyle(
                          color: AppColors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${playlist.trackCount} tracks',
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  playlist.title,
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  playlist.subtitle,
                  style: const TextStyle(color: AppColors.muted, height: 1.4),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Text(
                      playlist.durationLabel,
                      style: const TextStyle(
                        color: AppColors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.visibility_rounded),
                      label: Text(connected ? 'Preview Only' : 'Preview Queue'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PodcastCard extends StatelessWidget {
  const _PodcastCard({
    required this.recommendation,
    required this.connected,
  });

  final PodcastRecommendation recommendation;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 160,
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(
                  colors: recommendation.backgroundColors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),
          if (recommendation.visualTile != null)
            Positioned.fill(
              child: BrandImageTile(
                tile: recommendation.visualTile!,
                borderRadius: BorderRadius.circular(24),
                overlay: const Color(0x70050505),
              ),
            ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.stroke),
                gradient: const LinearGradient(
                  colors: [Color(0x22050505), Color(0xD0050505)],
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
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        recommendation.category.label,
                        style: const TextStyle(
                          color: AppColors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      recommendation.provider.label,
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  recommendation.title,
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${recommendation.host} • ${recommendation.durationLabel}',
                  style: const TextStyle(color: AppColors.muted),
                ),
                const SizedBox(height: 8),
                Text(
                  recommendation.episodeTitle,
                  style: const TextStyle(color: AppColors.white, height: 1.35),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.podcasts_rounded),
                  label: Text(connected ? 'Preview Episode' : 'Preview Recommendation'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaylistInsightCard extends StatelessWidget {
  const _PlaylistInsightCard();

  @override
  Widget build(BuildContext context) {
    return DarkCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.orangeBright.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.insights_rounded,
              color: AppColors.orangeBright,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Roadmap Truth',
                  style: TextStyle(
                    color: AppColors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'These music and podcast cards are now framed as previews and recommendations. Real Spotify and Apple Music auth, playback, and sync are the next backend step.',
                  style: TextStyle(color: AppColors.muted, height: 1.45),
                ),
              ],
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.stroke),
      ),
      child: Text(
        label,
        style: const TextStyle(color: AppColors.muted),
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xl,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.stroke),
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
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, fontSize: 14),
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

class _RangeTabs extends StatelessWidget {
  const _RangeTabs();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.stroke),
      ),
      child: const Row(
        children: [
          _RangeChip(label: '7D'),
          _RangeChip(label: '30D', selected: true),
          _RangeChip(label: '3M'),
          _RangeChip(label: '1Y'),
        ],
      ),
    );
  }
}

class _RangeChip extends StatelessWidget {
  const _RangeChip({required this.label, this.selected = false});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.orangeBright.withValues(alpha: 0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.orangeBright : AppColors.muted,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
