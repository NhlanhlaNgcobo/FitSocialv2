import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;
import 'package:uuid/uuid.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/connectivity/backend_reachability.dart';
import '../../../shared/widgets/confirm_destructive_sheet.dart';
import '../../../shared/widgets/quick_toast.dart';
import '../../../shared/widgets/run_route_map.dart';
import '../../../shared/widgets/staggered_fade_in.dart';
import '../../auth/application/body_metrics_providers.dart';
import '../../main/application/activity_actions.dart';
import '../../main/domain/activity_kind.dart';
import '../../main/domain/app_models.dart';
import '../../music/application/music_providers.dart';
import '../../music/presentation/connect_music_action.dart';
import '../../music/presentation/music_mini_player.dart';
import '../application/heart_rate_connection_controller.dart';
import '../application/run_draft_providers.dart';
import '../application/tracking_providers.dart';
import '../domain/gps_activity_profile.dart';
import '../domain/heart_rate_models.dart';
import '../domain/run_draft.dart';
import '../data/live_run_service.dart';
import 'finish_run_sheet.dart';
import 'live_run_map_screen.dart';
import 'live_share_card.dart';
import 'recover_run_sheet.dart';
import 'run_map_readout.dart';
import 'run_session_widgets.dart';
import 'start_countdown.dart';
import '../../music/presentation/music_island_action.dart';
import '../../../shared/widgets/liquid_glass.dart';

/// Live GPS run tracking: start/pause/stop with real-time distance,
/// duration, and pace from the phone's location sensors, plus live BPM
/// when a Bluetooth heart-rate device is connected.
class LiveRunScreen extends ConsumerStatefulWidget {
  const LiveRunScreen({super.key, this.kind = ActivityKind.run});

  /// Which activity is being recorded. Decides the GPS tuning, the wording,
  /// whether the headline figure is a pace or a speed, and what the saved
  /// session is filed as. Defaults to a run so a deep link still works.
  final ActivityKind kind;

  @override
  ConsumerState<LiveRunScreen> createState() => _LiveRunScreenState();
}

class _LiveRunScreenState extends ConsumerState<LiveRunScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const int _sectionCount = 3;

  late final AnimationController _entranceController;

  bool _isSaving = false;
  String? _errorMessage;

  /// Whether Android is already letting this app off battery optimisation.
  ///
  /// Starts true so the starvation banner never opens by accusing the runner
  /// of a setting that has not been read yet — the offer appears a frame later
  /// if it is really needed. Non-Android platforms stay true forever.
  bool _isBatteryExempt = true;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
    // Watched so returning from the Settings app re-reads the exemption: the
    // fallback path in BatteryOptimization.requestExemption hands the runner
    // off to a screen it cannot see the outcome of.
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refreshBatteryExemption());
    // After the first frame, so the sheet has a laid-out screen to open over.
    WidgetsBinding.instance.addPostFrameCallback((_) => _offerRecovery());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshBatteryExemption());
    }
  }

  Future<void> _refreshBatteryExemption() async {
    final exempt = await ref.read(batteryOptimizationProvider).isExempt();
    if (mounted && exempt != _isBatteryExempt) {
      setState(() => _isBatteryExempt = exempt);
    }
  }

  /// The banner's one tap. Asks Android for the exemption, then re-reads it
  /// rather than believing the answer: the fallback route only launches a
  /// settings screen, and the lifecycle hook above catches the way back.
  Future<void> _allowUnrestrictedBattery() async {
    await ref.read(batteryOptimizationProvider).requestExemption();
    await _refreshBatteryExemption();
  }

  /// Offers back a run the app died in the middle of.
  ///
  /// Asked here rather than on launch because this is the screen the answer
  /// belongs on — and because a runner who never opens it is not interrupted
  /// about a run they have already forgotten.
  Future<void> _offerRecovery() async {
    final service = ref.read(liveRunServiceProvider);
    // Never over the top of a run that is actually happening.
    if (service.current.isTracking) return;

    final checkpoint = await ref.read(recoverableRunProvider.future);
    if (checkpoint == null || !mounted) return;
    if (service.current.isTracking) return;

    final choice = await showRecoverRunSheet(
      context: context,
      checkpoint: checkpoint,
    );
    if (!mounted) return;

    switch (choice) {
      case RecoverRunChoice.resume:
        try {
          await service.resumeFrom(checkpoint);
        } on LocationPermissionException catch (e) {
          if (mounted) setState(() => _errorMessage = e.message);
        } catch (e) {
          if (mounted) {
            setState(() => _errorMessage = 'Could not resume the run: $e');
          }
        }
      case RecoverRunChoice.finishNow:
        // Put back, then taken through the ordinary finish — the same sheet,
        // the same save, the same drafts branch if there is still no signal.
        service.restoreForFinish(checkpoint);
        await _stopAndSave();
      case RecoverRunChoice.discard:
        final confirmed = await confirmDestructiveAction(
          context,
          title: 'Discard this run?',
          message: '${checkpoint.distanceKm.toStringAsFixed(2)} km was '
              'recorded before the app closed. This cannot be undone.',
          confirmLabel: 'Discard',
        );
        if (confirmed) {
          await ref.read(runCheckpointStoreProvider).clear();
        }
      // Dismissed. The checkpoint stays and the offer comes back next time.
      case RecoverRunChoice.later:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _entranceController.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() => _errorMessage = null);
    if (!await showStartCountdown(context) || !mounted) return;
    try {
      final service = ref.read(liveRunServiceProvider);
      // Gives the stride estimate a starting point from the runner's own
      // height rather than the average of everybody, for the stretch before
      // the GPS has measured one. Absent profile, absent height, unloaded
      // provider: all fine, the estimate just opens on the default.
      final heightCm = ref.read(bodyMetricsProvider).valueOrNull?.heightCm;
      if (heightCm != null) service.seedStrideFromHeight(heightCm);
      await service.start(profile: GpsActivityProfile.forKind(widget.kind));
      ref
          .read(heartRateRecorderProvider)
          .start(ref.read(bleHeartRateServiceProvider).heartRateStream);
    } on LocationPermissionException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (e) {
      setState(() => _errorMessage = 'Could not start GPS tracking: $e');
    }
  }

  /// The map, and only the map. Finish pressed up there comes back here to
  /// be acted on, because this screen owns the finish sheet and the save.
  Future<void> _expandMap() async {
    final finish = await LiveRunMapScreen.show(context, kind: widget.kind);
    if (!mounted || !finish) return;
    // Belt and braces: the map only offers Finish while tracking, but a run
    // that ended between the tap and the pop must not be stopped twice.
    if (!ref.read(liveRunServiceProvider).current.isTracking) return;
    await _stopAndSave();
  }

  Future<void> _stopAndSave() async {
    final service = ref.read(liveRunServiceProvider);
    final result = service.stop();
    // Stopped here rather than after the finish sheet: that sheet stays open
    // for as long as the runner spends choosing a backdrop, and the strap keeps
    // reporting the whole time. Recording through it would fold the cool-down
    // into the run's average.
    final heartRate = ref.read(heartRateRecorderProvider).stop();

    // Read once, here, and not again. The sheet below can stay open for a
    // minute while the runner crops a photo; branching on a fresh read
    // afterwards would mean the button said one thing and the app did another.
    final saveToDrafts = !kIsWeb && ref.read(isOfflineProvider);

    if (result.distanceKm < 0.05) {
      // The checkpoint goes too. Without this a discarded twenty-metre run
      // offers itself back for recovery on every launch.
      unawaited(ref.read(runCheckpointStoreProvider).clear());
      setState(() {
        _errorMessage =
            '${widget.kind.descriptor.singular} too short to save '
            '(${(result.distanceKm * 1000).round()} m).';
      });
      return;
    }

    final distanceKm = double.parse(result.distanceKm.toStringAsFixed(2));
    final route = result.points
        .map((p) => RoutePoint(latitude: p.latitude, longitude: p.longitude))
        .toList(growable: false);

    // The run is over and the numbers are final; this only asks what it should
    // look like on the way out. Dismissing the sheet saves, so nothing here
    // can lose the run by accident — only its Discard button can, on purpose.
    final choice = await showFinishRunSheet(
      context: context,
      route: route,
      distanceLabel: '${distanceKm.toStringAsFixed(2)} km',
      durationLabel: _formatElapsed(result.elapsed),
      paceLabel: result.formattedAverageFor(widget.kind),
      saveToDrafts: saveToDrafts,
    );
    if (!mounted) return;

    if (choice.discard) {
      // The checkpoint goes with it, or the run they just threw away would be
      // offered back for recovery on the next launch.
      await ref.read(runCheckpointStoreProvider).clear();
      if (!mounted) return;
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
        route: route,
        heartRate: heartRate,
      );
      return;
    }

    try {
      final saved = await ref.read(activityActionsProvider).saveRun(
            RunLogDraft(
              distanceKm: distanceKm,
              elapsed: result.elapsed,
              averagePace: result.formattedAverageFor(widget.kind),
              shareToFeed: choice.shareToFeed,
              activityKind: widget.kind,
              elevationGainMeters: result.elevationGainMeters,
              startedAt: result.startedAt,
              routePoints: route,
              showRouteMap: choice.showRouteMap,
              backgroundImagePath: choice.backgroundImagePath,
              heartRate: heartRate.hasData ? heartRate : null,
            ),
          );
      // Only now: if the app dies between stop() and here, the run is still
      // recoverable from disk.
      unawaited(ref.read(runCheckpointStoreProvider).clear());
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

  /// Files the finished run on this phone because there is no connection to
  /// send it over.
  ///
  /// Nothing is handed to Firestore here, deliberately. Letting its cache queue
  /// the run *and* keeping a draft would post the same run twice — once when
  /// signal returns and again when the runner taps Post. The draft is the only
  /// copy until they say otherwise.
  Future<void> _saveToDrafts({
    required FinishRunChoice choice,
    required double distanceKm,
    required LiveRunState result,
    required List<RoutePoint> route,
    required HeartRateSummary heartRate,
  }) async {
    try {
      await ref.read(runDraftsProvider.notifier).saveFromRun(
            RunDraft(
              id: const Uuid().v4(),
              savedAt: DateTime.now(),
              distanceKm: distanceKm,
              elapsed: result.elapsed,
              averagePace: result.formattedAverageFor(widget.kind),
              shareToFeed: choice.shareToFeed,
              activityKind: widget.kind,
              elevationGainMeters: result.elevationGainMeters,
              routePoints: route,
              startedAt: result.startedAt,
              heartRate: heartRate.hasData ? heartRate : null,
            ),
            sourcePhotoPath: choice.backgroundImagePath,
          );
      // The run is on disk twice over until this lands, which is the right way
      // round: clearing first would leave a window with no copy at all.
      await ref.read(runCheckpointStoreProvider).clear();
      if (!mounted) return;

      showQuickToast(
        context,
        "Saved to Drafts. Post it from Create when you're back online.",
        icon: Icons.cloud_off_rounded,
        tone: ToastTone.success,
        // Longer than the default: this one tells the runner where their run
        // went, and it is the only time they are told.
        visibleFor: const Duration(seconds: 5),
        actionLabel: 'View',
        onAction: () => context.go('/create'),
      );
      context.go('/create');
    } catch (e) {
      // Deliberately does not navigate. The run is still in memory and its
      // checkpoint is still on disk, so Finish can simply be pressed again —
      // walking away from the screen is what would lose it.
      if (!mounted) return;
      setState(() => _errorMessage =
          'Could not save this run to your phone: $e. Tap Finish to try '
          'again.');
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

  /// What the GPS is actually doing, in terms a tester can report back.
  ///
  /// Kept fixes are given against delivered ones because the two coming apart
  /// is the whole diagnosis. A healthy stream delivers about one a second and
  /// keeps one every few; a throttled one delivers so few that the route
  /// becomes a handful of long chords. The old counter showed only the kept
  /// number, which reads the same in both cases.
  static String _gpsStatusLine(LiveRunState state) {
    final stats = state.fixStats;
    final accuracy = stats.lastAccuracyMeters;
    final buffer = StringBuffer(
      '${stats.kept} of ${stats.received} fixes kept · ${stats.cadenceLabel}',
    );
    if (accuracy != null) buffer.write(' · ±${accuracy.round()} m');
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final runState =
        ref.watch(liveRunStateProvider).valueOrNull ?? LiveRunState.idle;
    // A ride is described in km/h; everything on foot in minutes per km.
    final usesPace = widget.kind.descriptor.usesPace;
    final showsClimb = widget.kind != ActivityKind.run;

    // Driven off the run state rather than the pause button so the GPS
    // auto-pause counts too — it is decided inside the service, and a runner
    // waiting at a crossing should not have the wait averaged into their run.
    ref.listen(liveRunStateProvider, (_, next) {
      final state = next.valueOrNull;
      if (state == null) return;
      final recorder = ref.read(heartRateRecorderProvider);
      if (state.isTracking && !state.isPaused && !state.isAutoPaused) {
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

    // "Covering ground right now" — the one condition that lights the screen
    // up. Standing still drops the glow, so a glance from arm's length tells
    // you whether the distance is still moving. The clock is not what it
    // reports: duration runs through a wait at a crossing, the same way it
    // does on every other running app.
    final isRunning =
        runState.isTracking && !runState.isPaused && !runState.isAutoPaused;

    final (String statusLabel, bool statusAccent) = switch (runState) {
      _ when isRunning => ('LIVE', true),
      _ when runState.isAutoPaused => ('STANDING STILL', true),
      _ when runState.isPaused => ('PAUSED', false),
      // Also the state a stopped-but-unsaved run lands in, which reads
      // correctly: the screen is ready to start another one.
      _ => ('READY', false),
    };

    var sectionIndex = 0;

    return Scaffold(
      appBar: AppBar(
        title: Text('Live ${widget.kind.descriptor.singular}'),
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
                child: _RouteStage(
                  route: runState.isTracking ? runState.routePoints : null,
                  onExpand: _expandMap,
                  readout: RunMapReadout(
                    statusLabel: statusLabel,
                    statusAccent: statusAccent,
                    distanceKm: runState.distanceKm,
                    elapsedLabel: _formatElapsed(runState.elapsed),
                    // Short labels: the figures share one row on the plate.
                    paceLabel: usesPace ? 'PACE /KM' : 'KM/H',
                    paceValue: usesPace
                        ? runState.formattedPace
                        : runState.formattedCurrentSpeed,
                    // Climb earns its place on a hike, where it is the number
                    // that describes the day, and on a ride. A run keeps the
                    // three figures it has always had rather than adding one
                    // most runners ignore.
                    climbMeters: showsClimb
                        ? runState.elevationGainMeters?.toString() ?? '--'
                        : null,
                  ),
                ),
              ),
              // Status, not an error: it explains why the distance stopped
              // climbing, so it belongs against the numbers it is explaining.
              // It is careful not to say "paused" — the duration is still
              // running, and a runner told otherwise would come back to a
              // clock that had counted the whole wait anyway.
              if (runState.isAutoPaused) ...[
                const SizedBox(height: AppSpacing.md),
                const RunBanner(
                  icon: Icons.motion_photos_paused_rounded,
                  message: 'Standing still — distance is holding',
                  tone: RunBannerTone.brand,
                ),
              ],
              // The one condition that quietly ruins a run: when the phone
              // delivers location this slowly the route is a handful of
              // straight lines between distant fixes, so every bend is cut and
              // the distance reads short. Said here, during the run, because
              // afterwards the only evidence is a number that looks merely
              // disappointing.
              //
              // Which of the two messages depends on whether there is still
              // something to change. Battery optimisation is the usual cause
              // and the banner carries the fix rather than describing where to
              // find it. Once the app is already exempt, repeating that
              // instruction is worse than saying nothing — the runner has done
              // it, the warning came back anyway, and the remaining cause is
              // reception, which no setting will help.
              if (runState.isTracking && runState.fixStats.isStarved) ...[
                const SizedBox(height: AppSpacing.md),
                // Steps covering the gap changes what is true to say here, so
                // it changes what is said. The distance is no longer reading
                // short, and telling a runner otherwise would send them into
                // Settings to fix something that is already handled — but the
                // GPS is still starved, the route is still coarse, and the
                // battery setting is still worth having, so the banner stays
                // and keeps its action.
                if (runState.fusion.isFillingGaps)
                  RunBanner(
                    icon: Icons.directions_run_rounded,
                    message: 'Weak GPS updates — filling the gaps from your '
                        'step counter, so the distance holds up. The route '
                        'itself will still look rough.',
                    tone: RunBannerTone.brand,
                    actionLabel:
                        _isBatteryExempt ? null : 'Allow unrestricted battery',
                    onAction:
                        _isBatteryExempt ? null : _allowUnrestrictedBattery,
                  )
                else if (!_isBatteryExempt)
                  RunBanner(
                    icon: Icons.satellite_alt_rounded,
                    message: 'Weak GPS updates — this phone is reporting '
                        'location far slower than usual, so distance will read '
                        'short. Android is holding FitSocial back to save '
                        'battery.',
                    tone: RunBannerTone.danger,
                    actionLabel: 'Allow unrestricted battery',
                    onAction: _allowUnrestrictedBattery,
                  )
                else
                  const RunBanner(
                    icon: Icons.satellite_alt_rounded,
                    message: 'Weak GPS updates — this phone is finding '
                        'satellites slowly, so distance will read short. '
                        'Battery is already unrestricted, so this is signal: '
                        'open sky helps, tall buildings and tunnels do not.',
                    tone: RunBannerTone.danger,
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
                  startLabel: 'Start ${widget.kind.descriptor.singular}',
                  onStart: _start,
                  onPause: () => ref.read(liveRunServiceProvider).pause(),
                  onResume: () => ref.read(liveRunServiceProvider).resume(),
                  onFinish: _stopAndSave,
                ),
              ),
              // Offered only once there is a position to share. Sits under
              // the controls rather than in the app bar because it is pressed
              // once, on the way out of the door, by someone handing a link
              // to whoever is waiting at home — not something to reach for
              // mid-run.
              if (runState.isTracking) ...[
                const SizedBox(height: AppSpacing.md),
                LiveShareCard(kind: widget.kind),
              ],
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
                        ? Icons.satellite_alt_rounded
                        : Icons.info_outline_rounded,
                    size: 14,
                    color: palette.muted,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      runState.isTracking
                          ? _gpsStatusLine(runState)
                          : 'Distance, time and ${usesPace ? 'pace' : 'speed'} '
                              'are measured live from GPS. Keep your phone '
                              'with you.',
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

/// The map and the numbers as one thing: the route fills the frame and the
/// readout sits along its bottom edge, so the screen is the run rather than a
/// map with a scoreboard under it. Full screen is the same picture with the
/// readout moved to the top.
///
/// Before the run starts [route] is null and the frame holds the placeholder
/// instead, at the same height with the same readout — so the page does not
/// reflow the moment tracking begins; the map simply drops in behind the
/// figures.
///
/// Tapping anywhere on the map — or the corner button, for whoever would not
/// think to — opens it full screen. The button exists because a tap on a map
/// is not something anyone expects to do anything; the map itself also takes
/// the tap because, mid-run, a target the size of the whole frame is the only
/// one that can be hit reliably.
class _RouteStage extends StatelessWidget {
  const _RouteStage({
    required this.route,
    required this.onExpand,
    required this.readout,
  });

  /// Null before tracking starts.
  final List<LatLng>? route;
  final VoidCallback onExpand;
  final RunMapReadout readout;

  /// The old map and hero card, stacked, less the gap between them.
  static const double _height = 400;

  /// Space between the plate and the frame's edge — the plate is *on* the map
  /// rather than a border of it.
  static const double _inset = 10;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final route = this.route;

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
      child: Stack(
        children: [
          if (route != null)
            RunRouteMap(
              route: route,
              height: _height,
              onTap: onExpand,
              // Keeps the Google logo and the camera's centre clear of the
              // plate along the bottom.
              padding: const EdgeInsets.only(
                bottom: RunMapReadout.approximateHeight + _inset,
              ),
            )
          else
            const _RoutePlaceholder(height: _height),
          if (route != null)
            Positioned(
              top: 8,
              right: 8,
              child: Tooltip(
                message: 'Full screen map',
                child: Material(
                  color: RunMapPlate.fill(context),
                  shape: CircleBorder(
                    side: BorderSide(
                      color: palette.stroke.withValues(alpha: 0.6),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: onExpand,
                    child: SizedBox(
                      width: 36,
                      height: 36,
                      child: Icon(
                        Icons.open_in_full_rounded,
                        size: 17,
                        color: palette.text,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            left: _inset,
            right: _inset,
            bottom: _inset,
            child: readout,
          ),
        ],
      ),
    );
  }
}

/// What sits where the map will be, before the run starts. Its message sits in
/// the upper part of the frame, above the readout that shares it.
class _RoutePlaceholder extends StatelessWidget {
  const _RoutePlaceholder({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return LiquidGlass(
      // Painted by the lens rather than by a fill of its own: a pane
      // over the app backdrop, like every other card.
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: height,
        width: double.infinity,
        // Leaves the plate's strip at the bottom out of the centring, so the
        // message sits in the middle of what is actually empty.
        padding: const EdgeInsets.only(
          bottom: RunMapReadout.approximateHeight + _RouteStage._inset,
        ),
        decoration: BoxDecoration(
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
      ),
    );
  }
}
