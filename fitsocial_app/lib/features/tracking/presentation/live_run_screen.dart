import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/run_route_map.dart';
import '../../../shared/widgets/staggered_fade_in.dart';
import '../../main/application/activity_actions.dart';
import '../../main/domain/app_models.dart';
import '../../music/application/music_providers.dart';
import '../../music/presentation/connect_music_action.dart';
import '../../music/presentation/music_mini_player.dart';
import '../application/tracking_providers.dart';
import '../data/live_run_service.dart';

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

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    try {
      final saved = await ref.read(activityActionsProvider).saveRun(
            RunLogDraft(
              distanceKm: double.parse(result.distanceKm.toStringAsFixed(2)),
              elapsed: result.elapsed,
              averagePace: result.formattedAveragePace,
              shareToFeed: true,
              startedAt: result.startedAt,
              routePoints: result.points
                  .map((p) =>
                      RoutePoint(latitude: p.latitude, longitude: p.longitude))
                  .toList(growable: false),
            ),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(saved.message)),
      );
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

    var sectionIndex = 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Run'),
        actions: [
          _HeartRateAction(
            bpm: liveBpm,
            onPressed: () => context.push('/health'),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: Stack(
        children: [
          // Ambient orange wash behind the hero. Barely there when idle, and
          // it lifts while the run is live — the screen's only cue that
          // doesn't cost a pixel of layout.
          _AmbientGlow(active: isRunning),
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
                child: _RunHeroCard(
                  state: runState,
                  isRunning: isRunning,
                  elapsedLabel: _formatElapsed(runState.elapsed),
                  bpm: liveBpm,
                ),
              ),
              // Status, not an error: it explains why the clock stopped on its
              // own, so it belongs against the numbers it is explaining.
              if (runState.isAutoPaused) ...[
                const SizedBox(height: AppSpacing.md),
                const _Banner(
                  icon: Icons.motion_photos_paused_rounded,
                  message: 'Auto-paused — start moving to resume',
                  tone: _BannerTone.brand,
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              StaggeredFadeIn(
                controller: _entranceController,
                index: sectionIndex++,
                itemCount: _sectionCount,
                child: _Controls(
                  state: runState,
                  isSaving: _isSaving,
                  onStart: _start,
                  onPause: () => ref.read(liveRunServiceProvider).pause(),
                  onResume: () => ref.read(liveRunServiceProvider).resume(),
                  onFinish: _stopAndSave,
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: AppSpacing.md),
                _Banner(
                  icon: Icons.error_outline_rounded,
                  message: _errorMessage!,
                  tone: _BannerTone.danger,
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

/// Soft radial orange behind the top of the page.
class _AmbientGlow extends StatelessWidget {
  const _AmbientGlow({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -0.85),
              radius: 1.1,
              colors: [
                AppColors.orangeBright.withValues(alpha: active ? 0.16 : 0.05),
                Colors.transparent,
              ],
            ),
          ),
        ),
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
              color: AppColors.orangeBright.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.route_rounded,
              color: AppColors.orangeBright,
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

/// Distance, big, with the supporting metrics beneath it.
class _RunHeroCard extends StatelessWidget {
  const _RunHeroCard({
    required this.state,
    required this.isRunning,
    required this.elapsedLabel,
    required this.bpm,
  });

  final LiveRunState state;
  final bool isRunning;
  final String elapsedLabel;
  final int? bpm;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg - 4,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.surface, palette.surfaceHigh],
        ),
        border: Border.all(
          color: isRunning
              ? AppColors.orangeBright.withValues(alpha: 0.35)
              : palette.stroke,
        ),
        boxShadow: [
          BoxShadow(
            color: isRunning
                ? AppColors.orangeBright.withValues(alpha: 0.18)
                : palette.navShadow,
            blurRadius: 26,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          _StatusPill(state: state, isRunning: isRunning),
          const SizedBox(height: AppSpacing.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                state.distanceKm.toStringAsFixed(2),
                style: TextStyle(
                  fontSize: 76,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -2,
                  color: palette.text,
                  // Fixed-width digits: without them the whole number shuffles
                  // sideways every time a digit ticks over.
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'KM',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                  color: palette.muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Container(height: 1, color: palette.stroke),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _Metric(
                  icon: Icons.timer_outlined,
                  label: 'TIME',
                  value: elapsedLabel,
                ),
              ),
              _MetricRule(color: palette.stroke),
              Expanded(
                child: _Metric(
                  icon: Icons.speed_rounded,
                  label: 'PACE /KM',
                  value: state.formattedPace,
                ),
              ),
              _MetricRule(color: palette.stroke),
              Expanded(
                child: _Metric(
                  icon: bpm != null
                      ? Icons.favorite_rounded
                      : Icons.monitor_heart_outlined,
                  label: 'BPM',
                  value: bpm?.toString() ?? '--',
                  accent: bpm != null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// LIVE / PAUSED / AUTO-PAUSED / READY, in the tone that matches.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.state, required this.isRunning});

  final LiveRunState state;
  final bool isRunning;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    final (String label, Color color) = switch (state) {
      _ when isRunning => ('LIVE', AppColors.orangeBright),
      _ when state.isAutoPaused => ('AUTO-PAUSED', AppColors.orangeBright),
      _ when state.isPaused => ('PAUSED', palette.muted),
      // Also the state a stopped-but-unsaved run lands in, which reads
      // correctly: the screen is ready to start another one.
      _ => ('READY', palette.muted),
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 14, 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PulseDot(color: color, active: isRunning),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// A dot that breathes while [active]. Owns its own controller so the ticker
/// only runs on the frames that actually need it.
class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.color, required this.active});

  final Color color;
  final bool active;

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_PulseDot old) {
    super.didUpdateWidget(old);
    if (widget.active == old.active) return;
    if (widget.active) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.55 * t),
                blurRadius: 4 + 6 * t,
                spreadRadius: 1 + 3 * t,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MetricRule extends StatelessWidget {
  const _MetricRule({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 42, color: color);
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.icon,
    required this.label,
    required this.value,
    this.accent = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final valueColor = accent ? AppColors.orangeBright : palette.text;

    return Column(
      children: [
        Icon(icon, size: 14, color: accent ? valueColor : palette.muted),
        const SizedBox(height: 6),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w800,
            color: valueColor,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: palette.muted,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}

/// Start, or pause-and-finish. Pause is the quiet circle and Finish is the lit
/// bar, so the two mid-run controls can't be confused for one another at a
/// glance the way two identical orange buttons could.
class _Controls extends StatelessWidget {
  const _Controls({
    required this.state,
    required this.isSaving,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onFinish,
  });

  final LiveRunState state;
  final bool isSaving;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    if (!state.isTracking) {
      return _GlowButton(
        label: 'Start GPS Run',
        icon: Icons.play_arrow_rounded,
        onPressed: onStart,
      );
    }

    final isPaused = state.isPaused;

    return Row(
      children: [
        _CircleControl(
          icon: isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
          tooltip: isPaused ? 'Resume' : 'Pause',
          onTap: isPaused ? onResume : onPause,
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: _GlowButton(
            label: isSaving ? 'Saving...' : 'Finish',
            icon: isSaving ? null : Icons.stop_rounded,
            onPressed: isSaving ? null : onFinish,
          ),
        ),
      ],
    );
  }
}

/// [PrimaryButton] with the brand glow the run-log hero card uses, dropped
/// while the button is disabled so a dead control doesn't look lit.
class _GlowButton extends StatelessWidget {
  const _GlowButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.orangeBright
                .withValues(alpha: onPressed == null ? 0 : 0.32),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: PrimaryButton(label: label, icon: icon, onPressed: onPressed),
    );
  }
}

/// The secondary mid-run control: same height as the primary bar beside it, so
/// the pair reads as one row rather than two stacked ideas.
class _CircleControl extends StatelessWidget {
  const _CircleControl({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: Material(
          color: palette.surfaceHigh,
          shape: CircleBorder(side: BorderSide(color: palette.stroke)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: 56,
              height: 56,
              child: Icon(icon, size: 26, color: palette.text),
            ),
          ),
        ),
      ),
    );
  }
}

enum _BannerTone { brand, danger }

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.message,
    required this.tone,
  });

  final IconData icon;
  final String message;
  final _BannerTone tone;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = switch (tone) {
      _BannerTone.brand => AppColors.orangeBright,
      _BannerTone.danger => palette.danger,
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Heart-rate shortcut in the app bar. Reads as a lit chip once a strap is
/// connected, and as a plain glyph when there is nothing to show.
class _HeartRateAction extends StatelessWidget {
  const _HeartRateAction({required this.bpm, required this.onPressed});

  final int? bpm;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isLive = bpm != null;

    return Tooltip(
      message: isLive ? 'Heart-rate device' : 'Connect heart-rate device',
      child: Material(
        color: isLive
            ? AppColors.orangeBright.withValues(alpha: 0.14)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(99),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Icon(
              isLive ? Icons.favorite_rounded : Icons.monitor_heart_outlined,
              size: 20,
              color: isLive ? AppColors.orangeBright : palette.text,
            ),
          ),
        ),
      ),
    );
  }
}
