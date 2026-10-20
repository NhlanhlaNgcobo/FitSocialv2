import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/input/typed_number.dart';
import '../../../shared/services/instagram_photo_picker.dart';
import '../../../shared/services/run_card_exporter.dart';
import '../../../shared/widgets/dark_card.dart';
import '../../../shared/widgets/form_section_header.dart';
import '../../../shared/widgets/glass_well.dart';
import '../../../shared/widgets/glass.dart';
import '../../../shared/widgets/health_pull_card.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/quick_toast.dart';
import '../../../shared/widgets/run_background_section.dart';
import '../../../shared/widgets/run_summary_card.dart';
import '../../../shared/widgets/save_run_card_row.dart';
import '../../../shared/widgets/share_to_feed_toggle.dart';
import '../../../shared/widgets/staggered_fade_in.dart';
import '../../tracking/application/run_draft_providers.dart';
import '../../tracking/application/tracking_providers.dart';
import '../../tracking/data/run_import_service.dart';
import '../../tracking/domain/run_draft.dart';
import '../../tracking/domain/run_pace.dart';
import '../../auth/application/body_metrics_providers.dart';
import '../../weather/presentation/weather_card.dart';
import '../application/active_workout_controller.dart';
import '../application/activity_actions.dart';
import '../application/workout_background_notice.dart';
import '../application/workout_library_providers.dart';
import '../application/workout_preferences.dart';
import '../domain/exercise_library.dart';
import '../domain/workout_models.dart' show LibraryExercise;
import '../domain/workout_math.dart' show exerciseKeyFor;
import '../domain/activity_kind.dart';
import '../domain/app_models.dart';
import 'tag_people_sheet.dart';
import '../../music/presentation/music_island_action.dart';
import '../../../shared/widgets/liquid_glass.dart';

/// Where a walk, run, hike or ride is started: pick the activity, then go.
///
/// Only the ways of *recording* live here — GPS, the treadmill timer, an
/// indoor bike — with the conditions outside under them, because the weather
/// is what decides between them. Typing an outing in after the fact is a
/// different job, so it sits behind Manual in the app bar rather than filling
/// the bottom half of the page with a form most visits never touch.
class RunLogScreen extends ConsumerStatefulWidget {
  const RunLogScreen({super.key});

  @override
  ConsumerState<RunLogScreen> createState() => _RunLogScreenState();
}

class _RunLogScreenState extends ConsumerState<RunLogScreen>
    with SingleTickerProviderStateMixin {
  /// The stagger's denominator: how many sections this build actually emits.
  /// Has to match, or a section that isn't counted never finishes its fade.
  /// The treadmill card is the run tab's and the indoor bike the ride tab's,
  /// so one of them comes and goes with the activity.
  int get _sectionCount =>
      3 + (_kind == ActivityKind.run || _kind == ActivityKind.ride ? 1 : 0);

  late final AnimationController _entranceController;

  /// Which activity the page is about: the GPS card it opens, the indoor
  /// option under it, and what the manual sheet starts on.
  ActivityKind _kind = ActivityKind.run;

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

  Future<void> _openManual() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      isScrollControlled: true,
      builder: (_) => _ManualRunSheet(initialKind: _kind),
    );
  }

  /// A bike ridden indoors is a cardio machine, not a ride with a route, so it
  /// is logged in a live workout: pick the bike, and the session opens with it
  /// already on the card — or the one already running gains it.
  Future<void> _startIndoorBike() async {
    // Both are auto-disposing and nothing else on this page watches them, so a
    // plain read would always find them empty. Held open while the bike is
    // picked, which is time enough for last session's numbers to arrive.
    final keepCustom = ref.listenManual(customExercisesProvider, (_, __) {});
    final keepPrevious =
        ref.listenManual(previousPerformanceProvider, (_, __) {});
    try {
      final bike = await _pickIndoorBike(context);
      if (bike == null || !mounted) return;

      unawaited(ref.read(workoutBackgroundNoticeProvider).requestPermission());
      final controller = ref.read(activeWorkoutProvider.notifier);
      await controller.ensureStarted(
        title: bike.name,
        bodyweightKg: ref.read(bodyMetricsProvider).valueOrNull?.weightKg,
      );
      final custom = keepCustom.read().valueOrNull ?? const [];
      controller.addExercises([
        NewExercise(
          name: bike.name,
          exerciseId: bike.id,
          trackingType:
              ExerciseLibrary.trackingTypeFor(bike.id, custom: custom),
          // Last time's time and distance on this bike, as hints in the row.
          previous: keepPrevious.read().lastSets(
                exerciseKeyFor(name: bike.name, exerciseId: bike.id),
                source: ref.read(workoutPreferencesProvider).previousSource,
              ),
        ),
      ]);
      if (mounted) unawaited(context.push('/workout-session'));
    } finally {
      keepCustom.close();
      keepPrevious.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    var sectionIndex = 0;

    Widget section(Widget child) => StaggeredFadeIn(
          controller: _entranceController,
          index: sectionIndex++,
          itemCount: _sectionCount,
          child: child,
        );

    return Scaffold(
      appBar: AppBar(
        title: Text('Log ${_kind.descriptor.singular}'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: TextButton.icon(
              onPressed: _openManual,
              icon: const Icon(Icons.edit_note_rounded, size: 20),
              label: const Text(
                'Manual',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const MusicIslandAction(),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.xl + MediaQuery.of(context).viewPadding.bottom,
        ),
        children: [
          section(
            _ActivityPicker(
              selected: _kind,
              onChanged: (kind) => setState(() => _kind = kind),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          section(
            _GpsHeroCard(
              kind: _kind,
              onTap: () => context.push('/live-run', extra: _kind),
            ),
          ),
          // A treadmill is a way of running indoors and nothing else: there is
          // no indoor hike, and a stationary bike is a different machine with
          // different numbers. Shown for runs only rather than offered and
          // then behaving oddly.
          if (_kind == ActivityKind.run) ...[
            const SizedBox(height: AppSpacing.sm + 4),
            section(
              _IndoorCard(
                icon: Icons.timer_outlined,
                title: 'Treadmill run',
                subtitle: 'Press start and the timer runs — no GPS needed',
                onTap: () => context.push('/treadmill-run'),
              ),
            ),
          ],
          // The ride tab's indoor option, and only bikes: a rower or the
          // stairs is not a ride, and offering them here sent people to the
          // workout log looking for a bike.
          if (_kind == ActivityKind.ride) ...[
            const SizedBox(height: AppSpacing.sm + 4),
            section(
              _IndoorCard(
                icon: Icons.pedal_bike_rounded,
                title: 'Indoor bike',
                subtitle: 'Stationary, spin, air or recumbent — '
                    'starts a workout with it',
                onTap: _startIndoorBike,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          // Conditions sit with the choice they decide: out on GPS, or in.
          section(const WeatherCard()),
        ],
      ),
    );
  }
}

/// The bikes a ride can be done on indoors, from the exercise library — the
/// outdoor one is the GPS card's job.
List<LibraryExercise> get _indoorBikes => [
      for (final name in const [
        'Stationary Bike',
        'Spin Class',
        'Assault Bike',
        'Recumbent Bike',
      ])
        if (ExerciseLibrary.byId(ExerciseLibrary.slug(name)) case final bike?)
          bike,
    ];

Future<LibraryExercise?> _pickIndoorBike(BuildContext context) {
  return showModalBottomSheet<LibraryExercise>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (sheetContext) {
      final palette = sheetContext.palette;
      return _SheetFrame(
        title: 'Which bike?',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final bike in _indoorBikes)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.pedal_bike_rounded, color: palette.brand),
                title: Text(
                  bike.name,
                  style: TextStyle(
                    color: palette.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                trailing: Icon(
                  Icons.chevron_right_rounded,
                  color: palette.muted,
                ),
                onTap: () => Navigator.of(sheetContext).pop(bike),
              ),
          ],
        ),
      );
    },
  );
}

/// A bottom sheet's pane: handle, title, content.
class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        12,
        0,
        12,
        12 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      child: LiquidGlass(
        lens: true,
        borderRadius: BorderRadius.circular(28),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: palette.stroke),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SheetHandle(),
              const SizedBox(height: 16),
              Text(
                title,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: palette.text,
                ),
              ),
              const SizedBox(height: 4),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: context.palette.stroke,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

/// An outing typed in after the fact, and everything that goes with posting
/// it: a pull from the health store, the distance and time, a photo for the
/// card, sharing and tags.
class _ManualRunSheet extends ConsumerStatefulWidget {
  const _ManualRunSheet({required this.initialKind});

  final ActivityKind initialKind;

  @override
  ConsumerState<_ManualRunSheet> createState() => _ManualRunSheetState();
}

class _ManualRunSheetState extends ConsumerState<_ManualRunSheet> {
  late final TextEditingController _distanceController;
  late final TextEditingController _durationController;

  /// Which activity the form is about: the wording, and whether its third
  /// figure is a pace or a speed.
  late ActivityKind _kind = widget.initialKind;

  double _distanceKm = 0;

  /// Typed as minutes, held as a Duration so a fractional entry keeps its
  /// seconds all the way to the post.
  Duration _elapsed = Duration.zero;
  bool _shareToFeed = true;
  List<TaggedUser> _taggedUsers = const [];
  bool _isSaving = false;

  /// The health-store session the form was filled from, if it was. Carried
  /// through to the save so the outing keeps its real start time and cannot
  /// arrive a second time as an import.
  HealthRunPrefill? _healthPrefill;
  bool _isPullingHealth = false;

  /// Why the last pull produced nothing, shown under the card. Cleared by the
  /// next attempt.
  String? _healthNote;

  /// The chosen backdrop, as a local path. Uploaded on save, not on pick — a
  /// user who backs out of the form should not have left a file behind.
  String? _backgroundPath;
  // Set the first time Save is pressed with a blank field, so the wells only
  // turn red after the user has actually tried to submit.
  bool _showFieldErrors = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _distanceController = TextEditingController();
    _durationController = TextEditingController();
  }

  @override
  void dispose() {
    _distanceController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  bool get _hasDistance => _distanceKm > 0;
  bool get _hasDuration => _elapsed > Duration.zero;
  bool get _isComplete => _hasDistance && _hasDuration;

  /// The headline second figure: `m:ss /km` on foot, `x.x km/h` on a bike.
  ///
  /// Formatted by the shared helpers rather than here, so a manually entered
  /// ride and a recorded one cannot drift into two different shapes.
  String get _paceLabel {
    if (!_isComplete) return '--';
    return formatPaceOrSpeed(
      kind: _kind,
      distanceKm: _distanceKm,
      elapsed: _elapsed,
    );
  }

  /// What that figure is called: "Avg pace" or "Avg speed".
  String get _paceStatLabel =>
      _kind.descriptor.usesPace ? 'Avg pace' : 'Avg speed';

  String get _durationLabel {
    if (!_hasDuration) return '--';
    final hours = _elapsed.inHours;
    final mins = _elapsed.inMinutes % 60;
    if (hours == 0) return '$mins min';
    return mins == 0 ? '${hours}h' : '${hours}h ${mins}m';
  }

  /// The elapsed time as the *post* will carry it — a clock, not a phrase.
  ///
  /// Deliberately not [_durationLabel]: the card below is a preview of what
  /// gets shared, and a preview that reads "45 min" where the post will read
  /// "45:00" is a preview of something else.
  String get _clockLabel {
    final hours = _elapsed.inHours;
    final mins = (_elapsed.inMinutes % 60).toString().padLeft(2, '0');
    final secs = (_elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return hours == 0 ? '$mins:$secs' : '$hours:$mins:$secs';
  }

  static String _formatDistance(double value) {
    var text = value.toStringAsFixed(2);
    if (text.contains('.')) {
      text = text.replaceFirst(RegExp(r'0+$'), '');
      text = text.replaceFirst(RegExp(r'\.$'), '');
    }
    return text;
  }

  /// Minutes for the duration field, to the same two places: 50:25 is typed
  /// back as "50.42", which parses to the same second.
  static String _formatMinutes(Duration value) =>
      _formatDistance(value.inSeconds / 60);

  /// Reads the latest session out of the health store into the form.
  ///
  /// Access is *asked for* rather than checked. The dashboard's gate covers
  /// steps and heart rate but not exercise sessions, so "granted" there can
  /// still mean "declined" here, and the silent import can only find nothing.
  /// Health Connect returns at once when everything is already allowed, and a
  /// tap on a button that says what it wants is the one moment a permission
  /// dialog is not a surprise.
  Future<void> _pullFromHealth() async {
    if (_isPullingHealth || _isSaving) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _isPullingHealth = true;
      _healthNote = null;
    });
    try {
      final granted =
          await ref.read(healthServiceProvider).requestPermissions();
      if (!mounted) return;
      if (!granted) {
        setState(() => _healthNote = HealthPullCard.refusedNote);
        return;
      }
      final prefill = await ref.read(runImportServiceProvider).latest();
      if (!mounted) return;
      if (prefill == null) {
        setState(() => _healthNote = HealthPullCard.emptyNote);
        return;
      }
      _applyHealthPrefill(prefill);
    } catch (_) {
      if (!mounted) return;
      setState(() => _healthNote = HealthPullCard.failedNote);
    } finally {
      if (mounted) setState(() => _isPullingHealth = false);
    }
  }

  void _applyHealthPrefill(HealthRunPrefill prefill) {
    final km = prefill.distanceKm;
    setState(() {
      _healthPrefill = prefill;
      // The session decides the activity: a hike pulled into a form set to
      // "run" would be saved as a run, and the picker is right there to
      // override it.
      _kind = prefill.kind;
      _distanceKm = km ?? 0;
      _elapsed = prefill.elapsed;
      _distanceController.text = km == null ? '' : _formatDistance(km);
      _durationController.text = _formatMinutes(prefill.elapsed);
      _showFieldErrors = false;
      _errorMessage = null;
    });
    final source = prefill.record.sourceName;
    showQuickToast(
      context,
      km == null
          ? 'Time filled from $source. Add the distance.'
          : 'Filled from $source',
      tone: ToastTone.success,
    );
  }

  /// "Run · Today 07:12 · 10.01 km in 50:25".
  static String _describePrefill(HealthRunPrefill prefill) {
    final distance = prefill.distanceKm;
    final clock = HealthPullCard.clockLabel(prefill.elapsed);
    return [
      prefill.kind.descriptor.singular,
      HealthPullCard.whenLabel(prefill.record.startedAt),
      distance == null
          ? '$clock, no distance recorded'
          : '${_formatDistance(distance)} km in $clock',
    ].join(' · ');
  }

  /// A saved session came out of the health store: stamp the ledger so the
  /// background import never files it, and drop the draft if it already has.
  ///
  /// Housekeeping, so it must not fail the save: the run is already in
  /// Firestore, and its window blocks the import on its own even if this
  /// throws.
  Future<void> _retireImport(String externalId) async {
    try {
      await ref.read(runImportLedgerProvider).markHandled([externalId]);
      final controller = ref.read(runDraftsProvider.notifier);
      final drafts =
          ref.read(runDraftsProvider).valueOrNull ?? const <RunDraft>[];
      for (final draft in drafts) {
        if (draft.externalId == externalId) await controller.discard(draft);
      }
    } catch (error) {
      debugPrint('Could not retire imported run $externalId: $error');
    }
  }

  /// Picks and crops a backdrop. The cropper downscales and re-encodes, so what
  /// comes back is already feed-spec — the same path a post photo takes.
  Future<void> _pickBackground(ImageSource source) async {
    final path = await InstagramPhotoPicker.pickAndCrop(
      // A card's backdrop: 9:16 by default, and the card follows
      // whichever shape the photo is cropped to.
      otherShapes: true,
      context: context,
      source: source,
    );
    // Null means they backed out of the picker or the cropper. Leave whatever
    // was already chosen rather than clearing it.
    if (path == null || !mounted) return;
    setState(() => _backgroundPath = path);
  }

  /// Null is a dismissal and leaves the selection alone; an empty list is a
  /// deliberate "nobody".
  Future<void> _pickTaggedPeople() async {
    final picked = await showTagPeopleSheet(context, selected: _taggedUsers);
    if (picked == null || !mounted) return;
    setState(() => _taggedUsers = picked);
  }

  Future<void> _saveRun() async {
    if (!_isComplete) {
      setState(() {
        _showFieldErrors = true;
        _errorMessage = 'Add a distance and a time before saving.';
      });
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final result = await ref.read(activityActionsProvider).saveRun(
            RunLogDraft(
              distanceKm: _distanceKm,
              elapsed: _elapsed,
              averagePace: _paceLabel,
              shareToFeed: _shareToFeed,
              activityKind: _kind,
              backgroundImagePath: _backgroundPath,
              // Only ever set by a health pull. A run typed from memory has
              // no start worth recording beyond "now".
              startedAt: _healthPrefill?.record.startedAt,
              heartRate: _healthPrefill?.heartRate,
              taggedUsers: _shareToFeed ? _taggedUsers : const [],
            ),
          );
      if (!mounted) return;
      if (_healthPrefill case final prefill?) {
        await _retireImport(prefill.record.externalId);
        if (!mounted) return;
      }
      showQuickToast(context, result.message, tone: ToastTone.success);
      context.go('/home');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final media = MediaQuery.of(context);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.92,
      builder: (context, scrollController) => Padding(
        padding: EdgeInsets.fromLTRB(12, 0, 12, 12 + media.viewPadding.bottom),
        child: LiquidGlass(
          lens: true,
          borderRadius: BorderRadius.circular(28),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: palette.stroke),
            ),
            child: ListView(
              controller: scrollController,
              padding: EdgeInsets.fromLTRB(
                AppSpacing.md,
                10,
                AppSpacing.md,
                // Lifts the last field and the button above the keyboard.
                AppSpacing.md + media.viewInsets.bottom,
              ),
              children: [
                const _SheetHandle(),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Log ${_kind.descriptor.singular.toLowerCase()} '
                        'manually',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: palette.text,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(Icons.close_rounded, color: palette.muted),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                // Its own picker: the session pulled from the health store
                // decides the activity, and the user can still correct it.
                _ActivityPicker(
                  selected: _kind,
                  onChanged: (kind) => setState(() => _kind = kind),
                ),
                const SizedBox(height: AppSpacing.md),
                if (!kIsWeb) ...[
                  HealthPullCard(
                    busy: _isPullingHealth,
                    filled: _healthPrefill != null,
                    title: _healthPrefill == null
                        ? HealthPullCard.idleTitle
                        : 'Filled from ${_healthPrefill!.record.sourceName}',
                    subtitle: _healthPrefill == null
                        ? 'Pull your latest session from Samsung Health or '
                            'your watch'
                        : _describePrefill(_healthPrefill!),
                    note: _healthNote,
                    onTap: _isSaving ? null : _pullFromHealth,
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    border: Border.all(color: palette.stroke),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _MetricField(
                        icon: Icons.straighten_rounded,
                        label: 'Distance',
                        controller: _distanceController,
                        suffix: 'km',
                        hint: '0.00',
                        decimal: true,
                        invalid: _showFieldErrors && !_hasDistance,
                        onChanged: (value) {
                          setState(() {
                            _distanceKm = parseTypedDouble(value) ?? 0;
                          });
                        },
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _MetricField(
                        icon: Icons.timer_outlined,
                        label: 'Duration',
                        controller: _durationController,
                        suffix: 'min',
                        hint: '0',
                        // Minutes, but not whole ones: "50,5" is a real time.
                        decimal: true,
                        invalid: _showFieldErrors && !_hasDuration,
                        onChanged: (value) {
                          setState(() {
                            _elapsed = parseTypedMinutes(value);
                          });
                        },
                      ),
                    ],
                  ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOut,
                  alignment: Alignment.topCenter,
                  // Height alone, no fade over it: a pane of glass inside an
                  // opacity buffer has no backdrop left to bend, so it would
                  // hollow out for the whole reveal and then snap.
                  child: _isComplete
                      ? Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.md),
                          child: _RunSummary(
                            distance: '${_formatDistance(_distanceKm)} km',
                            duration: _durationLabel,
                            pace: _paceLabel,
                            paceLabel: _paceStatLabel,
                          ),
                        )
                      : const SizedBox(width: double.infinity),
                ),
                const SizedBox(height: AppSpacing.lg),
                RunBackgroundSection(
                  imagePath: _backgroundPath,
                  // A logged run has no trace, so a blank card is just numbers
                  // on a gradient: offer the photo, preview only once picked.
                  previewWithoutImage: false,
                  distanceLabel: _hasDistance
                      ? '${_formatDistance(_distanceKm)} km'
                      : null,
                  durationLabel: _hasDuration ? _clockLabel : null,
                  paceLabel: _isComplete ? _paceLabel : null,
                  onPick: _isSaving ? null : _pickBackground,
                  onRemove: _isSaving
                      ? null
                      : () => setState(() => _backgroundPath = null),
                ),
                // The card only exists on screen once there is a photo, so
                // the export follows it.
                if (!kIsWeb && _backgroundPath != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  SaveRunCardRow(
                    card: RunCardExport(
                      // A logged run has no trace — the numbers and the photo
                      // carry the card, exactly as they do on screen.
                      distanceLabel: _hasDistance
                          ? '${_formatDistance(_distanceKm)} km'
                          : null,
                      durationLabel: _hasDuration ? _clockLabel : null,
                      paceLabel: _isComplete ? _paceLabel : null,
                      background: localBackgroundImage(_backgroundPath!),
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                ShareToFeedToggle(
                  value: _shareToFeed,
                  subtitle: 'Post this run to your profile activity',
                  onChanged: (value) {
                    setState(() {
                      _shareToFeed = value;
                    });
                  },
                ),
                if (_shareToFeed) ...[
                  const SizedBox(height: AppSpacing.md),
                  TagPeopleRow(
                    tagged: _taggedUsers,
                    onTap: _isSaving ? null : _pickTaggedPeople,
                  ),
                ],
                if (_errorMessage != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  _ErrorBanner(message: _errorMessage!),
                ],
                const SizedBox(height: AppSpacing.lg),
                PrimaryButton(
                  icon: _isSaving ? null : Icons.check_rounded,
                  label: _isSaving
                      ? 'Saving...'
                      : (_shareToFeed ? 'Save Run & Share' : 'Save Run'),
                  onPressed: _isSaving ? null : _saveRun,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Run, hike or ride — the choice that everything below it answers to.
///
/// Three segments on one pane rather than three tiles on the Create page. The
/// activities differ in their numbers, not in what you do to start one, so
/// putting the choice here keeps the Create page at five rows and lets the
/// selection recolour the card you are about to tap.
class _ActivityPicker extends StatelessWidget {
  const _ActivityPicker({required this.selected, required this.onChanged});

  final ActivityKind selected;
  final ValueChanged<ActivityKind> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return LiquidGlass(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: palette.stroke),
        ),
        child: Row(
          children: [
            for (final kind in ActivityDescriptor.gpsKinds)
              Expanded(
                child: _ActivitySegment(
                  kind: kind,
                  isSelected: kind == selected,
                  onTap: () => onChanged(kind),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ActivitySegment extends StatelessWidget {
  const _ActivitySegment({
    required this.kind,
    required this.isSelected,
    required this.onTap,
  });

  final ActivityKind kind;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final descriptor = kind.descriptor;
    // Through the palette rather than raw: the fixed hues are set for the dark
    // theme and glare on the cream one if painted straight.
    final accent = palette.accent(descriptor.accent);

    return Semantics(
      selected: isSelected,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm + 2),
          decoration: BoxDecoration(
            color: isSelected
                ? palette.accentFill(descriptor.accent)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                descriptor.icon,
                size: 18,
                color: isSelected ? accent : palette.muted,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  descriptor.singular,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isSelected ? accent : palette.muted,
                    fontSize: 13.5,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The primary way into a session: a solid gradient card that reads as the
/// recommended path before the manual form does.
///
/// Takes its hue from the selected activity, so tapping a segment above
/// visibly changes the thing you are about to start rather than only changing
/// a word.
class _GpsHeroCard extends StatelessWidget {
  const _GpsHeroCard({required this.kind, required this.onTap});

  final ActivityKind kind;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final descriptor = kind.descriptor;
    // Every kind takes its own accent — a run is blue, same as its segment and
    // its feed cards — darkened one step for the far end of the gradient.
    final accent = palette.accent(descriptor.accent);
    final gradientStart = accent;
    final gradientEnd = Color.lerp(accent, const Color(0xFF1A120B), 0.32)!;
    final subtitle = descriptor.usesPace
        ? 'Real-time distance, pace and route map'
        : 'Real-time distance, speed and route map';

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: [
          BoxShadow(
            color: gradientStart.withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.card),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [gradientStart, gradientEnd],
            ),
          ),
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg - 4),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      // On the accent fill, so the white is fixed in both
                      // themes — same rule as AppColors.onBrand.
                      color: AppColors.onBrand.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      descriptor.icon,
                      color: AppColors.onBrand,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Track live with GPS',
                          style: TextStyle(
                            color: AppColors.onBrand,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            color: AppColors.onBrand,
                            fontSize: 12.5,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    color: AppColors.onBrand,
                    size: 20,
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

/// The indoor way in, sitting directly under the GPS card.
///
/// Deliberately the quieter of the two: it is the same live tracking, minus the
/// one signal a treadmill can't give — so it reads as the alternative to the
/// accent card above rather than a second recommendation competing with it.
///
/// The same quiet card serves the other machines, which is the same choice —
/// indoors, no GPS — made for a different piece of kit.
class _IndoorCard extends StatelessWidget {
  const _IndoorCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return LiquidGlass(
      // Material stays for the ink splash and gives up its colour:
      // an opaque fill in there would sit between the glass and
      // everything it is meant to bend.
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.card),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: palette.stroke),
            ),
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: palette.brandSoft,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: palette.brand, size: 22),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: palette.text,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: palette.muted,
                          fontSize: 12.5,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Icon(
                  Icons.arrow_forward_rounded,
                  color: palette.muted,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MetricField extends StatelessWidget {
  const _MetricField({
    required this.icon,
    required this.label,
    required this.controller,
    required this.suffix,
    required this.hint,
    required this.decimal,
    required this.invalid,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final TextEditingController controller;
  final String suffix;
  final String hint;
  final bool decimal;
  final bool invalid;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FormSectionHeader(icon: icon, label: label),
        // The same well the workout form uses, so a number typed on one screen
        // sits in the same material as a number typed on the other.
        GlassWell(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          borderColor: invalid ? palette.danger : null,
          child: Row(
            children: [
              // Balances the unit on the right so the number stays optically
              // centred in the well.
              SizedBox(width: _suffixWidth(suffix)),
              Expanded(
                child: TextField(
                  controller: controller,
                  onChanged: onChanged,
                  keyboardType: decimal
                      ? const TextInputType.numberWithOptions(decimal: true)
                      : TextInputType.number,
                  textAlign: TextAlign.center,
                  cursorColor: palette.brand,
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 18),
                    border: InputBorder.none,
                    hintText: hint,
                    hintStyle: TextStyle(
                      color: palette.muted.withValues(alpha: 0.5),
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: _suffixWidth(suffix),
                // One line whatever the font's widths: "km" broke into "k"
                // over "m" in the narrower sheet.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    suffix,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      color: palette.muted,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static double _suffixWidth(String suffix) => suffix.length * 10.0 + 8;
}

/// The read-out that slides in once both fields are filled: what the run will
/// look like on the feed.
class _RunSummary extends StatelessWidget {
  const _RunSummary({
    required this.distance,
    required this.duration,
    required this.pace,
    required this.paceLabel,
  });

  final String distance;
  final String duration;
  final String pace;

  /// "Avg pace" or "Avg speed" — a ride's headline figure is neither measured
  /// nor named the way a run's is.
  final String paceLabel;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return DarkCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      // The brand wash goes under the lens and arrives bent, rather than
      // sitting on top as the one flat surface on the page.
      backdrop: GlassBloom(colors: [palette.brand]),
      child: Row(
        children: [
          Expanded(
            child: _SummaryStat(label: 'Distance', value: distance),
          ),
          _SummaryRule(color: palette.stroke),
          Expanded(
            child: _SummaryStat(label: 'Time', value: duration),
          ),
          _SummaryRule(color: palette.stroke),
          Expanded(
            child: _SummaryStat(label: paceLabel, value: pace),
          ),
        ],
      ),
    );
  }
}

class _SummaryRule extends StatelessWidget {
  const _SummaryRule({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 32, color: color);
  }
}

class _SummaryStat extends StatelessWidget {
  const _SummaryStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Column(
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: palette.brandText,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: palette.muted,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.danger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.field),
        border: Border.all(color: palette.danger.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, size: 18, color: palette.danger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: palette.danger,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
