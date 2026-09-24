import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/connectivity/backend_reachability.dart';
import '../../../shared/input/typed_number.dart';
import '../../../shared/widgets/bouncy_chip.dart';
import '../../../shared/widgets/quick_toast.dart';
import '../../../shared/widgets/staggered_fade_in.dart';
import '../../main/application/activity_actions.dart';
import '../../main/domain/activity_kind.dart';
import '../../main/domain/app_models.dart';
import '../../music/application/music_providers.dart';
import '../../music/presentation/connect_music_action.dart';
import '../../music/presentation/music_island_action.dart';
import '../../music/presentation/music_mini_player.dart';
import '../application/heart_rate_connection_controller.dart';
import '../application/run_draft_providers.dart';
import '../application/tracking_providers.dart';
import '../domain/heart_rate_models.dart';
import '../domain/run_draft.dart';
import '../data/treadmill_run_service.dart';
import 'finish_run_sheet.dart';
import 'run_session_widgets.dart';
import 'start_countdown.dart';
import '../../../shared/widgets/form_section_header.dart';
import '../../../shared/widgets/glass_well.dart';
import '../../../shared/widgets/liquid_glass.dart';

/// Timer-based run tracking for a treadmill.
///
/// Same run, recorded the other way round: indoors the phone goes nowhere, so
/// the clock is the thing being measured and the distance is copied off the
/// machine's display. Nothing here touches location — no permission prompt, no
/// route, no map.
class TreadmillRunScreen extends ConsumerStatefulWidget {
  const TreadmillRunScreen({super.key});

  @override
  ConsumerState<TreadmillRunScreen> createState() => _TreadmillRunScreenState();
}

class _TreadmillRunScreenState extends ConsumerState<TreadmillRunScreen>
    with SingleTickerProviderStateMixin {
  static const int _sectionCount = 4;

  /// Below this there is nothing worth posting, and it is the same floor the
  /// GPS run refuses to save under.
  static const double _minimumDistanceKm = 0.05;

  late final AnimationController _entranceController;
  late final TextEditingController _distanceController;

  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
    // The service owns the distance, so coming back to a run already in
    // progress restores what was typed rather than blanking the field.
    final existing = ref.read(treadmillRunServiceProvider).current.distanceKm;
    _distanceController = TextEditingController(
      text: existing > 0 ? _formatDistance(existing) : '',
    );
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _distanceController.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() => _errorMessage = null);
    if (!await showStartCountdown(context) || !mounted) return;
    ref.read(treadmillRunServiceProvider).start();
    ref
        .read(heartRateRecorderProvider)
        .start(ref.read(bleHeartRateServiceProvider).heartRateStream);
    // start() resets the run, and with it the distance the field is showing.
    _distanceController.clear();
  }

  void _setDistance(String raw) {
    ref
        .read(treadmillRunServiceProvider)
        .setDistanceKm(parseTypedDouble(raw) ?? 0);
  }

  void _bumpDistance(double amount) {
    final service = ref.read(treadmillRunServiceProvider);
    final next = double.parse(
      (service.current.distanceKm + amount).toStringAsFixed(2),
    );
    service.setDistanceKm(next);
    _distanceController.text = _formatDistance(next);
    _distanceController.selection = TextSelection.collapsed(
      offset: _distanceController.text.length,
    );
  }

  Future<void> _finishAndSave() async {
    final service = ref.read(treadmillRunServiceProvider);

    // Checked *before* stopping, unlike the GPS screen: there the numbers are
    // already recorded and a short run is simply not worth saving, whereas here
    // a missing distance is something the runner can still go and read off the
    // machine — so the clock keeps running while they do.
    if (service.current.distanceKm < _minimumDistanceKm) {
      setState(() {
        _errorMessage =
            'Enter the distance from the treadmill display before finishing.';
      });
      return;
    }

    final result = service.stop();
    // Stopped before the finish sheet opens, for the same reason the GPS screen
    // does it here: the sheet waits on the runner and the strap does not.
    final heartRate = ref.read(heartRateRecorderProvider).stop();
    final distanceKm = double.parse(result.distanceKm.toStringAsFixed(2));

    // Read once, before the sheet — see the GPS screen for why it is not read
    // again afterwards.
    final saveToDrafts = !kIsWeb && ref.read(isOfflineProvider);

    // Dismissing the sheet saves — the run is over by the time it opens. Only
    // its Discard button, after confirming, throws the run away.
    final choice = await showFinishRunSheet(
      context: context,
      route: const [],
      distanceLabel: '${distanceKm.toStringAsFixed(2)} km',
      durationLabel: _formatElapsed(result.elapsed),
      paceLabel: result.formattedAveragePace,
      saveToDrafts: saveToDrafts,
    );
    if (!mounted) return;

    if (choice.discard) {
      // Nothing was checkpointed for a treadmill run, so there is nothing to
      // clear: leaving is the whole of discarding.
      showQuickToast(context, 'Run discarded');
      context.go('/home');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    if (saveToDrafts) {
      await _saveToDrafts(
        choice: choice,
        distanceKm: distanceKm,
        result: result,
        heartRate: heartRate,
      );
      return;
    }

    try {
      final saved = await ref.read(activityActionsProvider).saveRun(
            RunLogDraft(
              distanceKm: distanceKm,
              elapsed: result.elapsed,
              averagePace: result.formattedAveragePace,
              shareToFeed: choice.shareToFeed,
              // Stated rather than left to the default. A treadmill is a way
              // of running indoors and nothing else — there is no such thing
              // as an indoor hike, and a stationary bike is a different
              // machine reporting different numbers.
              activityKind: ActivityKind.run,
              startedAt: result.startedAt,
              // No trace to record: the run happened on the spot.
              backgroundImagePath: choice.backgroundImagePath,
              heartRate: heartRate.hasData ? heartRate : null,
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

  /// Files the treadmill run on this phone, exactly as the GPS screen does —
  /// minus the route, which a run on the spot never had.
  Future<void> _saveToDrafts({
    required FinishRunChoice choice,
    required double distanceKm,
    required TreadmillRunState result,
    required HeartRateSummary heartRate,
  }) async {
    try {
      await ref.read(runDraftsProvider.notifier).saveFromRun(
            RunDraft(
              id: const Uuid().v4(),
              savedAt: DateTime.now(),
              distanceKm: distanceKm,
              elapsed: result.elapsed,
              averagePace: result.formattedAveragePace,
              shareToFeed: choice.shareToFeed,
              startedAt: result.startedAt,
              heartRate: heartRate.hasData ? heartRate : null,
            ),
            sourcePhotoPath: choice.backgroundImagePath,
          );
      if (!mounted) return;

      showQuickToast(
        context,
        "Saved to Drafts. Post it from Create when you're back online.",
        icon: Icons.cloud_off_rounded,
        tone: ToastTone.success,
        visibleFor: const Duration(seconds: 5),
        actionLabel: 'View',
        onAction: () => context.go('/create'),
      );
      context.go('/create');
    } catch (e) {
      // Does not navigate: the run is still in memory, so Finish can be
      // pressed again.
      if (!mounted) return;
      setState(() => _errorMessage =
          'Could not save this run to your phone: $e. Tap Finish to try '
          'again.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  static String _formatElapsed(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final runState = ref.watch(treadmillRunStateProvider).valueOrNull ??
        TreadmillRunState.idle;

    // A treadmill run has no auto-pause, but the recorder is driven from the
    // state here too so both screens read the same way.
    ref.listen(treadmillRunStateProvider, (_, next) {
      final state = next.valueOrNull;
      if (state == null) return;
      final recorder = ref.read(heartRateRecorderProvider);
      if (state.isTracking && !state.isPaused) {
        recorder.resume();
      } else {
        recorder.pause();
      }
    });
    // Gated on the connection being live, not merely on a reading having
    // arrived once. A dropped strap emits nothing further, so the stream's last
    // value would otherwise sit on screen looking like a current heart rate for
    // the rest of the run.
    final connection = ref.watch(heartRateConnectionProvider);
    final liveBpm =
        connection.isLive ? ref.watch(liveHeartRateProvider).valueOrNull : null;
    final isReconnecting =
        connection.status == HeartRateConnectionStatus.reconnecting;
    // Notification access counts as much as a linked account here: both give
    // the mini player something to drive.
    final hasMusicSource = ref.watch(hasMusicSourceProvider);

    final isRunning = runState.isTracking && !runState.isPaused;
    final (String statusLabel, bool statusAccent) = switch (runState) {
      _ when isRunning => ('LIVE', true),
      _ when runState.isPaused => ('PAUSED', false),
      _ => ('READY', false),
    };

    var sectionIndex = 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Treadmill Run'),
        actions: [
          const MusicIslandAction(),
          RunHeartRateAction(
            bpm: liveBpm,
            isReconnecting: isReconnecting,
            onPressed: () => context.push('/health'),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: Stack(
        children: [
          AmbientRunGlow(active: isRunning),
          ListView(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              // Clears the gesture pill so the controls aren't sitting under it
              // at the end of the scroll.
              AppSpacing.xl + MediaQuery.of(context).viewPadding.bottom,
            ),
            children: [
              StaggeredFadeIn(
                controller: _entranceController,
                index: sectionIndex++,
                itemCount: _sectionCount,
                child: RunHeroCard(
                  statusLabel: statusLabel,
                  statusAccent: statusAccent,
                  isRunning: isRunning,
                  // The clock is the headline here — it is the only number the
                  // phone actually measures indoors.
                  headlineValue: _formatElapsed(runState.elapsed),
                  headlineUnit: null,
                  metrics: [
                    RunMetric(
                      icon: Icons.straighten_rounded,
                      label: 'DISTANCE',
                      value: runState.distanceKm > 0
                          ? '${_formatDistance(runState.distanceKm)} km'
                          : '--',
                    ),
                    RunMetric(
                      icon: Icons.speed_rounded,
                      label: 'PACE /KM',
                      value: runState.formattedPace,
                    ),
                    RunMetric(
                      icon: liveBpm != null
                          ? Icons.favorite_rounded
                          : isReconnecting
                              ? Icons.bluetooth_searching_rounded
                              : Icons.monitor_heart_outlined,
                      label: isReconnecting ? 'RECONNECTING' : 'BPM',
                      value: liveBpm?.toString() ?? '--',
                      accent: liveBpm != null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              StaggeredFadeIn(
                controller: _entranceController,
                index: sectionIndex++,
                itemCount: _sectionCount,
                child: _DistanceWell(
                  controller: _distanceController,
                  invalid: _errorMessage != null && runState.distanceKm <= 0,
                  onChanged: _setDistance,
                  onBump: _bumpDistance,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              StaggeredFadeIn(
                controller: _entranceController,
                index: sectionIndex++,
                itemCount: _sectionCount,
                child: RunControls(
                  isTracking: runState.isTracking,
                  isPaused: runState.isPaused,
                  isSaving: _isSaving,
                  startLabel: 'Start Treadmill Run',
                  onStart: _start,
                  onPause: () => ref.read(treadmillRunServiceProvider).pause(),
                  onResume: () =>
                      ref.read(treadmillRunServiceProvider).resume(),
                  onFinish: _finishAndSave,
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
              StaggeredFadeIn(
                controller: _entranceController,
                index: sectionIndex++,
                itemCount: _sectionCount,
                child: hasMusicSource
                    ? const MusicMiniPlayer()
                    : const ConnectMusicAction(),
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    runState.isTracking
                        ? Icons.timer_outlined
                        : Icons.info_outline_rounded,
                    size: 14,
                    color: palette.muted,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      runState.isTracking
                          ? 'The clock keeps running with the screen off. '
                              'Copy the distance across before you finish.'
                          : 'No GPS indoors — press start when the belt does, '
                              'and read the distance off the machine.',
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

/// `3.25`, `1.5`, `4` — a distance with no trailing zeros to read past.
String _formatDistance(double value) {
  var text = value.toStringAsFixed(2);
  if (text.contains('.')) {
    text = text.replaceFirst(RegExp(r'0+$'), '');
    text = text.replaceFirst(RegExp(r'\.$'), '');
  }
  return text;
}

/// The one number the phone can't measure indoors, asked for plainly.
class _DistanceWell extends StatelessWidget {
  const _DistanceWell({
    required this.controller,
    required this.invalid,
    required this.onChanged,
    required this.onBump,
  });

  final TextEditingController controller;
  final bool invalid;
  final ValueChanged<String> onChanged;
  final ValueChanged<double> onBump;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return LiquidGlass(
      // Painted by the lens rather than by a fill of its own: a pane
      // over the app backdrop, like every other card.
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: palette.stroke),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const FormSectionHeader(
              icon: Icons.straighten_rounded,
              label: 'Distance on the display',
            ),
            // The same well the two logging forms use, so a distance typed on
            // a treadmill sits in the same material as one typed anywhere else.
            GlassWell(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              borderColor: invalid ? palette.danger : null,
              child: Row(
                children: [
                  // Balances the unit on the right so the number stays optically
                  // centred in the well.
                  const SizedBox(width: 24),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      onChanged: onChanged,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      textAlign: TextAlign.center,
                      cursorColor: palette.brand,
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 18),
                        border: InputBorder.none,
                        hintText: '0.00',
                        hintStyle: TextStyle(
                          color: palette.muted.withValues(alpha: 0.5),
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 24,
                    child: Text(
                      'km',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: palette.muted,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final amount in const [0.5, 1.0, 5.0])
                  BouncyChip(
                    label: '+${_formatDistance(amount)} km',
                    onTap: () => onBump(amount),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
