import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/run_route_map.dart';
import '../../main/domain/activity_kind.dart';
import '../../music/application/music_player_controller.dart';
import '../../music/application/music_providers.dart';
import '../../music/domain/music_brand.dart';
import '../../main/domain/app_models.dart';
import '../application/tracking_providers.dart';
import '../data/live_run_service.dart';
import 'run_map_readout.dart';

/// The route, and nothing else.
///
/// Opened by tapping the map on the live run screen. The whole screen is the
/// GPS; everything the runner might need mid-run — the clock and the distance,
/// pause, finish, the music transport — floats over it as isolated plates, so
/// the map underneath is never boxed in by a card.
///
/// Nothing is decided here. Pause and resume go straight to the service, the
/// same as they do from the main screen, but Finish only *asks*: the screen
/// pops with `true` and the live run screen — which owns the finish sheet, the
/// save, the drafts fallback and the error banner — takes it from there. Doing
/// the save from up here would mean two copies of that path, and a sheet
/// opening over a screen that is about to close.
class LiveRunMapScreen extends ConsumerWidget {
  const LiveRunMapScreen({super.key, required this.kind});

  final ActivityKind kind;

  /// Pushes the map over whatever is showing and resolves to whether the
  /// runner tapped Finish. `false` (or null, on a back gesture) means they
  /// merely came back to the main screen, run still going.
  static Future<bool> show(BuildContext context, {required ActivityKind kind}) {
    return Navigator.of(context)
        .push<bool>(
          MaterialPageRoute<bool>(
            fullscreenDialog: true,
            builder: (_) => LiveRunMapScreen(kind: kind),
          ),
        )
        .then((finish) => finish ?? false);
  }

  static String _formatElapsed(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final runState =
        ref.watch(liveRunStateProvider).valueOrNull ?? LiveRunState.idle;
    final usesPace = kind.descriptor.usesPace;
    final showsClimb = kind != ActivityKind.run;
    final hasMusicSource = ref.watch(hasMusicSourceProvider);

    // The run can end from underneath this screen — a recovery, a crash
    // elsewhere — and a full-screen map of a run that is over is a trap with
    // no controls that mean anything. Leave with it.
    ref.listen(liveRunStateProvider, (_, next) {
      final state = next.valueOrNull;
      if (state != null && !state.isTracking) Navigator.of(context).pop(false);
    });

    final (String statusLabel, bool statusAccent) = switch (runState) {
      _ when runState.isTracking &&
              !runState.isPaused &&
              !runState.isAutoPaused =>
        ('LIVE', true),
      _ when runState.isAutoPaused => ('STANDING STILL', true),
      _ => ('PAUSED', false),
    };

    final viewPadding = MediaQuery.viewPaddingOf(context);
    // Roughly the height of the bottom cluster with the music row present.
    // Keeps the runner's dot in the uncovered middle and the Google logo
    // clear of the buttons.
    final bottomInset = viewPadding.bottom + (hasMusicSource ? 168 : 104);

    return Scaffold(
      backgroundColor: palette.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: RunRouteMap(
              route: runState.routePoints,
              height: double.infinity,
              borderRadius: BorderRadius.zero,
              showBadge: false,
              padding: EdgeInsets.only(
                top: viewPadding.top +
                    AppSpacing.sm +
                    RunMapReadout.approximateHeight,
                bottom: bottomInset,
              ),
            ),
          ),
          // Top edge: the way out, then the numbers. Status sits with the
          // numbers because it explains them — STANDING STILL is why the
          // distance has stopped moving while the clock has not.
          Positioned(
            top: viewPadding.top + AppSpacing.sm,
            left: AppSpacing.md,
            right: AppSpacing.md,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _MapCircleButton(
                  icon: Icons.close_fullscreen_rounded,
                  tooltip: 'Back to run',
                  onTap: () => Navigator.of(context).pop(false),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: RunMapReadout(
                    statusLabel: statusLabel,
                    statusAccent: statusAccent,
                    distanceKm: runState.distanceKm,
                    elapsedLabel: _formatElapsed(runState.elapsed),
                    paceLabel: usesPace ? 'PACE /KM' : 'KM/H',
                    paceValue: usesPace
                        ? runState.formattedPace
                        : runState.formattedCurrentSpeed,
                    climbMeters: showsClimb
                        ? runState.elevationGainMeters?.toString() ?? '--'
                        : null,
                  ),
                ),
              ],
            ),
          ),
          // Bottom edge: the transport above the run controls, so the thing
          // that ends the run is the lowest and largest — under the thumb,
          // not the thing hit while reaching for the skip button.
          Positioned(
            left: AppSpacing.md,
            right: AppSpacing.md,
            bottom: viewPadding.bottom + AppSpacing.md,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasMusicSource) ...[
                  const _FloatingMusicTransport(),
                  const SizedBox(height: AppSpacing.md),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _MapCircleButton(
                      icon: runState.isPaused
                          ? Icons.play_arrow_rounded
                          : Icons.pause_rounded,
                      tooltip: runState.isPaused ? 'Resume' : 'Pause',
                      size: 64,
                      iconSize: 30,
                      onTap: () {
                        final service = ref.read(liveRunServiceProvider);
                        runState.isPaused ? service.resume() : service.pause();
                      },
                    ),
                    const SizedBox(width: AppSpacing.md),
                    _FinishButton(
                      onPressed: () => Navigator.of(context).pop(true),
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

/// A round control on the map plate. The default size matches
/// [RunCircleControl] on the main screen; the pause control goes larger
/// because it is pressed on the move.
class _MapCircleButton extends StatelessWidget {
  const _MapCircleButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.size = 48,
    this.iconSize = 24,
    this.fill,
    this.iconColor,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;

  /// Overrides the plate colour — the music play button takes the service's
  /// own accent so it reads as the music control at a glance.
  final Color? fill;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final enabled = onTap != null;

    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: tooltip,
        child: Material(
          color: fill ?? RunMapPlate.fill(context),
          shape: CircleBorder(
            side: BorderSide(color: palette.stroke.withValues(alpha: 0.6)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(
                icon,
                size: iconSize,
                color: iconColor ??
                    (enabled
                        ? palette.text
                        : palette.muted.withValues(alpha: 0.4)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Finish, as a lit pill rather than another circle: it is the one control
/// here that ends something, and it should not look like the ones that don't.
class _FinishButton extends StatelessWidget {
  const _FinishButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: palette.brand.withValues(alpha: 0.32),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: palette.brand,
        borderRadius: BorderRadius.circular(32),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            height: 64,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.stop_rounded, size: 28, color: palette.background),
                  const SizedBox(width: 8),
                  Text(
                    'Finish',
                    style: TextStyle(
                      color: palette.background,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Previous / play-pause / next as three isolated plates, with what is playing
/// on a fourth. The same three controls as the mini player and the same
/// controller behind them, so a skip here is a skip on the Music tab too —
/// only the card around them is gone, because a card would cover the map.
class _FloatingMusicTransport extends ConsumerWidget {
  const _FloatingMusicTransport();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final player = ref.watch(musicPlayerControllerProvider);
    final controller = ref.read(musicPlayerControllerProvider.notifier);
    final connected = ref.watch(musicConnectionsProvider).connectedServices;
    final service = player.service ??
        (connected.isEmpty ? MusicProviderService.device : connected.first);
    final accent = MusicBrand.of(service).accent;
    final track = player.snapshot?.track;
    final canControl = player.canControl;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (track != null) ...[
          RunMapPlate(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.music_note_rounded, size: 14, color: accent),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    '${track.title} · ${track.artist}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.text,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _MapCircleButton(
              icon: Icons.skip_previous_rounded,
              tooltip: 'Previous track',
              onTap: canControl ? controller.previous : null,
            ),
            const SizedBox(width: AppSpacing.sm),
            _MapCircleButton(
              icon: player.isPlaying
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              tooltip: player.isPlaying ? 'Pause music' : 'Play music',
              size: 56,
              iconSize: 28,
              fill: canControl ? accent : null,
              iconColor: canControl ? palette.background : null,
              onTap: canControl ? controller.togglePlayPause : null,
            ),
            const SizedBox(width: AppSpacing.sm),
            _MapCircleButton(
              icon: Icons.skip_next_rounded,
              tooltip: 'Next track',
              onTap: canControl ? controller.next : null,
            ),
          ],
        ),
      ],
    );
  }
}
