import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/quick_toast.dart';
import '../../../shared/widgets/run_route_map.dart';
import '../../../shared/widgets/staggered_fade_in.dart';
import '../../main/application/activity_actions.dart';
import '../../main/domain/app_models.dart';
import '../../music/application/music_providers.dart';
import '../../music/presentation/connect_music_action.dart';
import '../../music/presentation/music_mini_player.dart';
import '../application/tracking_providers.dart';
import '../data/live_run_service.dart';
import 'finish_run_sheet.dart';
import 'run_session_widgets.dart';
import '../../music/presentation/music_island_action.dart';

/// Live GPS run tracking: start/pause/stop with real-time distance,
/// duration, and pace from the phone's location sensors, plus live BPM
/// when a Bluetooth heart-rate device is connected.
class LiveRunScreen extends ConsumerStatefulWidget {
  const LiveRunScreen({super.key});

  @override
  ConsumerState<LiveRunScreen> createState() => _LiveRunScreenState();
}

class _LiveRunScreenState extends ConsumerState<LiveRunScreen>
    with SingleTickerProviderStateMixin {
  static const int _sectionCount = 4;

  late final AnimationController _entranceController;

  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() => _errorMessage = null);
    try {
      await ref.read(liveRunServiceProvider).start();
    } on LocationPermissionException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (e) {
      setState(() => _errorMessage = 'Could not start GPS tracking: $e');
    }
  }

  Future<void> _stopAndSave() async {
    final service = ref.read(liveRunServiceProvider);
    final result = service.stop();

    if (result.distanceKm < 0.05) {
      setState(() {
        _errorMessage =
            'Run too short to save (${(result.distanceKm * 1000).round()} m).';
      });
      return;
    }

    final distanceKm = double.parse(result.distanceKm.toStringAsFixed(2));
    final route = result.points
        .map((p) => RoutePoint(latitude: p.latitude, longitude: p.longitude))
        .toList(growable: false);

    // The run is over and the numbers are final; this only asks what it should
    // look like on the way out. Every exit from the sheet saves, so nothing
    // here can lose the run that just finished.
    final choice = await showFinishRunSheet(
      context: context,
      route: route,
      distanceLabel: '${distanceKm.toStringAsFixed(2)} km',
      durationLabel: _formatElapsed(result.elapsed),
    );
    if (!mounted) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    try {
      final saved = await ref.read(activityActionsProvider).saveRun(
            RunLogDraft(
              distanceKm: distanceKm,
              elapsed: result.elapsed,
              averagePace: result.formattedAveragePace,
              shareToFeed: choice.shareToFeed,
              startedAt: result.startedAt,
              routePoints: route,
              backgroundImagePath: choice.backgroundImagePath,
            ),
          );
      if (!mounted) return;
      showQuickToast(context, saved.message, tone: ToastTone.success);
      context.go('/home');
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String _formatElapsed(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final runState =
        ref.watch(liveRunStateProvider).valueOrNull ?? LiveRunState.idle;
    final liveBpm = ref.watch(liveHeartRateProvider).valueOrNull;
    final hasMusicConnection =
        ref.watch(musicConnectionsProvider).hasAnyConnection;

    // "Running right now" — the one condition that lights the screen up. A
    // paused or auto-paused run keeps the numbers but drops the glow, so a
    // glance from arm's length tells you whether the clock is still counting.
    final isRunning =
        runState.isTracking && !runState.isPaused && !runState.isAutoPaused;

    final (String statusLabel, bool statusAccent) = switch (runState) {
      _ when isRunning => ('LIVE', true),
      _ when runState.isAutoPaused => ('AUTO-PAUSED', true),
      _ when runState.isPaused => ('PAUSED', false),
      // Also the state a stopped-but-unsaved run lands in, which reads
      // correctly: the screen is ready to start another one.
      _ => ('READY', false),
    };

    var sectionIndex = 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Run'),
        actions: [
          const MusicIslandAction(),
          RunHeartRateAction(
            bpm: liveBpm,
            onPressed: () => context.push('/health'),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: Stack(
        children: [
          // Ambient orange wash behind the hero.
          AmbientRunGlow(active: isRunning),
          ListView(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              // Clears the gesture pill so the controls aren't sitting under
              // it at the end of the scroll.
              AppSpacing.xl + MediaQuery.of(context).viewPadding.bottom,
            ),
            children: [
              StaggeredFadeIn(
                controller: _entranceController,
                index: sectionIndex++,
                itemCount: _sectionCount,
                child: runState.isTracking
                    ? _MapFrame(route: runState.routePoints)
                    : const _RoutePlaceholder(),
              ),
              const SizedBox(height: AppSpacing.md),
              StaggeredFadeIn(
                controller: _entranceController,
                index: sectionIndex++,
                itemCount: _sectionCount,
                child: RunHeroCard(
                  statusLabel: statusLabel,
                  statusAccent: statusAccent,
                  isRunning: isRunning,
                  headlineValue: runState.distanceKm.toStringAsFixed(2),
                  headlineUnit: 'KM',
                  metrics: [
                    RunMetric(
                      icon: Icons.timer_outlined,
                      label: 'TIME',
                      value: _formatElapsed(runState.elapsed),
                    ),
                    RunMetric(
                      icon: Icons.speed_rounded,
                      label: 'PACE /KM',
                      value: runState.formattedPace,
                    ),
                    RunMetric(
                      icon: liveBpm != null
                          ? Icons.favorite_rounded
                          : Icons.monitor_heart_outlined,
                      label: 'BPM',
                      value: liveBpm?.toString() ?? '--',
                      accent: liveBpm != null,
                    ),
                  ],
                ),
              ),
              // Status, not an error: it explains why the clock stopped on its
              // own, so it belongs against the numbers it is explaining.
              if (runState.isAutoPaused) ...[
                const SizedBox(height: AppSpacing.md),
                const RunBanner(
                  icon: Icons.motion_photos_paused_rounded,
                  message: 'Auto-paused — start moving to resume',
                  tone: RunBannerTone.brand,
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              StaggeredFadeIn(
                controller: _entranceController,
                index: sectionIndex++,
                itemCount: _sectionCount,
                child: RunControls(
                  isTracking: runState.isTracking,
                  isPaused: runState.isPaused,
                  isSaving: _isSaving,
                  startLabel: 'Start GPS Run',
                  onStart: _start,
                  onPause: () => ref.read(liveRunServiceProvider).pause(),
                  onResume: () => ref.read(liveRunServiceProvider).resume(),
                  onFinish: _stopAndSave,
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: AppSpacing.md),
                RunBanner(
                  icon: Icons.error_outline_rounded,
                  message: _errorMessage!,
                  tone: RunBannerTone.danger,
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              // Sits with the run controls rather than on the feed: music is
              // something you set up on your way into a run, not while
              // scrolling.
              //
              // Before a service is linked this is the same connect card as the
              // Music tab, so connecting happens here instead of bouncing the
              // runner out to another screen. Once linked it becomes the
              // transport, because mid-run the only thing anyone needs is to
              // skip a track — managing accounts can wait until they have
              // stopped.
              StaggeredFadeIn(
                controller: _entranceController,
                index: sectionIndex++,
                itemCount: _sectionCount,
                child: hasMusicConnection
                    ? const MusicMiniPlayer()
                    : const ConnectMusicAction(),
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    runState.isTracking
                        ? Icons.satellite_alt_rounded
                        : Icons.info_outline_rounded,
                    size: 14,
                    color: palette.muted,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      runState.isTracking
                          ? '${runState.points.length} location fixes recorded'
                          : 'Distance, time and pace are measured live from '
                              'GPS. Keep your phone with you.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: palette.muted,
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The route map, framed to match the cards under it.
class _MapFrame extends StatelessWidget {
  const _MapFrame({required this.route});

  final List<LatLng> route;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.stroke),
        boxShadow: [
          BoxShadow(
            color: palette.navShadow,
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: RunRouteMap(route: route, height: 240),
    );
  }
}

/// What sits where the map will be, before the run starts. Keeps the page from
/// reflowing the moment tracking begins — the map drops into the same slot at
/// the same height.
class _RoutePlaceholder extends StatelessWidget {
  const _RoutePlaceholder();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      height: 240,
      width: double.infinity,
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.stroke),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: context.palette.brandSoft,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.route_rounded,
              color: context.palette.brand,
              size: 26,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Your route draws here',
            style: TextStyle(
              color: palette.text,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Start the run and GPS takes over',
            style: TextStyle(color: palette.muted, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}
