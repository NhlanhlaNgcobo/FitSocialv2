import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/input/typed_number.dart';
import '../../../shared/widgets/confirm_destructive_sheet.dart';
import '../../../shared/widgets/glass_well.dart';
import '../../../shared/widgets/keyboard_safe_bottom_bar.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/quick_toast.dart';
import '../../auth/application/body_metrics_providers.dart';
import '../../../core/config/feature_flags.dart';
import '../../auth/domain/body_metrics.dart';
import '../application/active_workout_controller.dart';
import '../application/activity_actions.dart';
import '../application/rest_alerts.dart';
import '../application/workout_library_providers.dart';
import '../application/workout_preferences.dart';
import '../data/workout_preferences_store.dart';
import '../domain/active_workout.dart';
import '../domain/exercise_library.dart';
import '../domain/previous_performance.dart';
import '../domain/workout_math.dart';
import '../domain/workout_models.dart';
import 'exercise_picker_sheet.dart';
import 'workout_settings_sheet.dart';
import 'workout_tool_sheets.dart';

/// The workout that is happening now: a running clock, a card per exercise,
/// and a row per set that gets ticked off as it is done.
///
/// Distinct from `WorkoutLogScreen`, which is the form for a session already
/// finished. Both end in the same saved document.
///
/// Leaving the screen does not end the workout — it is persisted on every
/// change, so the Create page offers to resume it. Only Finish and Discard end
/// it.
class WorkoutSessionScreen extends ConsumerStatefulWidget {
  const WorkoutSessionScreen({super.key});

  @override
  ConsumerState<WorkoutSessionScreen> createState() =>
      _WorkoutSessionScreenState();
}

class _WorkoutSessionScreenState extends ConsumerState<WorkoutSessionScreen> {
  final _title = TextEditingController();
  bool _titleSynced = false;
  bool _shareToFeed = true;
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // A session resumed from the pill, or started before the profile loaded,
    // takes the bodyweight once it is known.
    ref.listenManual(bodyMetricsProvider, (_, next) {
      final kg = next.valueOrNull?.weightKg;
      if (kg != null && ref.read(activeWorkoutProvider)?.bodyweightKg == null) {
        _controller.setBodyweight(kg);
      }
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  ActiveWorkoutController get _controller =>
      ref.read(activeWorkoutProvider.notifier);

  /// One per card, so a superset can scroll to its next exercise.
  final _cardKeys = <String, GlobalKey>{};

  bool get _v2 => ref.read(featureEnabledProvider(FeatureFlag.workoutLoggerV2));

  Future<void> _addExercise() async {
    final custom = ref.read(customExercisesProvider).valueOrNull ?? const [];
    if (!_v2) {
      final picked = await showExercisePicker(context);
      if (picked == null || !mounted) return;
      _controller.addExercise(
        name: picked.name,
        exerciseId: picked.id,
        trackingType:
            ExerciseLibrary.trackingTypeFor(picked.id, custom: custom),
      );
      return;
    }
    final picked = await showExercisesPicker(context);
    if (picked == null || !mounted) return;
    final previous = ref.read(previousPerformanceProvider);
    final source = ref.read(workoutPreferencesProvider).previousSource;
    _controller.addExercises(
      [
        for (final p in picked.exercises)
          NewExercise(
            name: p.name,
            exerciseId: p.id,
            trackingType: ExerciseLibrary.trackingTypeFor(p.id, custom: custom),
            // As many rows as last time, so repeating it is a tick a set.
            previous: previous.lastSets(
              exerciseKeyFor(name: p.name, exerciseId: p.id),
              source: source,
            ),
          ),
      ],
      asSuperset: picked.asSuperset,
    );
  }

  /// After a set in a superset, brings the next exercise in it into view, at
  /// its first row not yet done — the next thing to do.
  void _onSetTicked(String key) {
    if (!_v2 || !ref.read(workoutPreferencesProvider).smartSupersetScroll) {
      return;
    }
    final workout = ref.read(activeWorkoutProvider);
    final group = workout?.exercise(key)?.supersetGroup;
    if (workout == null || group == null) return;
    final members = workout.supersetMembers(group);
    if (members.length < 2) return;
    final at = members.indexWhere((e) => e.key == key);
    for (var step = 1; step < members.length; step++) {
      final next = members[(at + step) % members.length];
      if (next.sets.any((s) => s.completedAt == null)) {
        final target = _cardKeys[next.key]?.currentContext;
        if (target != null) {
          Scrollable.ensureVisible(
            target,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 300),
            alignment: 0.1,
          );
        }
        return;
      }
    }
  }

  Future<void> _askBodyweight(ActiveWorkout workout) async {
    final kg =
        await showBodyweightSheet(context, current: workout.bodyweightKg);
    if (kg != null) _controller.setBodyweight(kg);
  }

  Future<void> _discard() async {
    final confirmed = await confirmDestructiveAction(
      context,
      title: 'Discard this workout?',
      message: 'Everything logged so far will be lost.',
      confirmLabel: 'Discard workout',
    );
    if (!confirmed || !mounted) return;
    _controller.discard();
    context.go('/home');
  }

  Future<void> _finish(ActiveWorkout workout) async {
    if (!workout.hasLoggedSets) {
      showQuickToast(context, 'Tick off at least one set first.');
      return;
    }

    // A row with reps typed in but never ticked is not saved. Say so rather
    // than dropping it quietly.
    final unticked = workout.exercises.fold<int>(
      0,
      (sum, e) =>
          sum + e.sets.where((s) => s.completedAt == null && s.reps > 0).length,
    );
    if (unticked > 0) {
      final proceed = await confirmDestructiveAction(
        context,
        title: 'Finish with unticked sets?',
        message: unticked == 1
            ? 'One set has reps but is not ticked off, so it will not be saved.'
            : '$unticked sets have reps but are not ticked off, so they '
                'will not be saved.',
        confirmLabel: 'Finish anyway',
        icon: Icons.check_rounded,
      );
      if (!proceed || !mounted) return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      final draft = workout.toDraft(
        endedAt: DateTime.now(),
        shareToFeed: _shareToFeed,
      );
      final result = await ref.read(activityActionsProvider).saveWorkout(draft);
      if (!mounted) return;
      // Cleared only after the save went through: a failure leaves the whole
      // session where it was, to try again.
      _controller.complete();
      showQuickToast(context, result.message, tone: ToastTone.success);
      context.go('/home');
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final workout = ref.watch(activeWorkoutProvider);

    if (workout == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Workout')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'No workout in progress.',
                  style: TextStyle(color: palette.muted, fontSize: 16),
                ),
                const SizedBox(height: AppSpacing.md),
                TextButton(
                  onPressed: () => context.go('/home'),
                  child: const Text('Back home'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // The title is typed into, so it cannot be rebuilt from state every frame.
    // Filled once, from whatever a resumed session already had.
    if (!_titleSynced) {
      _title.text = workout.title;
      _titleSynced = true;
    }
    final letters = supersetLetters(workout);
    final v2 = ref.watch(featureEnabledProvider(FeatureFlag.workoutLoggerV2));
    // Bodyweight work with no bodyweight to count: say so once, without
    // standing in the way of logging.
    final needsBodyweight = v2 &&
        workout.bodyweightKg == null &&
        workout.exercises.any((e) => e.trackingType.usesBodyweight);
    _cardKeys.removeWhere(
      (key, _) => workout.exercises.every((e) => e.key != key),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Workout')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.xl,
        ),
        children: [
          GlassWell(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _title,
              textCapitalization: TextCapitalization.words,
              style: TextStyle(
                color: palette.text,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: 'Workout name',
                hintStyle: TextStyle(color: palette.muted),
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onChanged: _controller.setTitle,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _StatsStrip(workout: workout),
          const SizedBox(height: AppSpacing.md),
          if (needsBodyweight)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: GlassWell(
                padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Add your bodyweight to count bodyweight volume.',
                        style: TextStyle(color: palette.text, fontSize: 14),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _askBodyweight(workout),
                      style: TextButton.styleFrom(
                        foregroundColor: palette.brandText,
                        minimumSize: const Size(48, 44),
                      ),
                      child: const Text('Add'),
                    ),
                  ],
                ),
              ),
            ),
          for (var i = 0; i < workout.exercises.length; i++)
            Padding(
              // A superset's cards sit close, so they read as one block.
              padding: EdgeInsets.only(
                bottom: _continuesSuperset(workout.exercises, i)
                    ? AppSpacing.xs
                    : AppSpacing.md,
              ),
              child: KeyedSubtree(
                key: _cardKeys.putIfAbsent(
                  workout.exercises[i].key,
                  GlobalKey.new,
                ),
                child: _ExerciseCard(
                  key: ValueKey(workout.exercises[i].key),
                  exercise: workout.exercises[i],
                  supersetLabel: letters[workout.exercises[i].supersetGroup],
                  onSetTicked: _onSetTicked,
                ),
              ),
            ),
          OutlinedButton.icon(
            onPressed: _addExercise,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add exercise'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              foregroundColor: palette.brandText,
              side: BorderSide(color: palette.brandSoftStroke),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
          if (v2) ...[
            const SizedBox(height: AppSpacing.sm),
            TextButton.icon(
              onPressed: () => showWorkoutSettingsSheet(context),
              icon: const Icon(Icons.tune_rounded, size: 18),
              label: const Text('Settings'),
              style: TextButton.styleFrom(
                foregroundColor: palette.muted,
                minimumSize: const Size(48, 44),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          TextButton(
            onPressed: _isSaving ? null : _discard,
            child: Text(
              'Discard workout',
              style: TextStyle(
                color: palette.danger,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: KeyboardSafeBottomBar(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (workout.rest != null)
                RestTimerBar(
                  rest: workout.rest!,
                  onAdjust: _controller.adjustRest,
                  onSkip: _controller.skipRest,
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _error!,
                    style: TextStyle(color: palette.danger, fontSize: 13),
                  ),
                ),
              SwitchListTile.adaptive(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Share to feed',
                  style: TextStyle(
                    color: palette.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                value: _shareToFeed,
                onChanged: _isSaving
                    ? null
                    : (value) => setState(() => _shareToFeed = value),
              ),
              PrimaryButton(
                icon: Icons.check_rounded,
                label: _isSaving ? 'Saving…' : 'Finish workout',
                onPressed: _isSaving ? null : () => _finish(workout),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The running clock with the sets and volume beside it.
class _StatsStrip extends ConsumerWidget {
  const _StatsStrip({required this.workout});

  final ActiveWorkout workout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final v2 = ref.watch(featureEnabledProvider(FeatureFlag.workoutLoggerV2));
    final units = v2
        ? _Units(
            imperial: ref.watch(bodyMetricsProvider).valueOrNull?.units ==
                MeasurementUnits.imperial,
          )
        : const _Units();
    final volume = workout.volume(
      includeWarmups:
          v2 && ref.watch(workoutPreferencesProvider).includeWarmupsInStats,
    );

    Widget stat(String label, Widget value) => Expanded(
          child: Column(
            children: [
              value,
              const SizedBox(height: 2),
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  color: palette.muted,
                ),
              ),
            ],
          ),
        );

    final valueStyle = TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w800,
      color: palette.text,
    );

    return GlassWell(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          stat(
            'Duration',
            ElapsedClock(startedAt: workout.startedAt, style: valueStyle),
          ),
          stat('Sets', Text('${workout.doneSetCount}', style: valueStyle)),
          stat(
            'Volume',
            Text(
              '${_formatKg(v2 ? units.toDisplay(volume).roundToDouble() : volume)} '
              '${units.label}',
              style: valueStyle,
            ),
          ),
        ],
      ),
    );
  }
}

/// Whether the exercise after [i] is in the same superset as it.
bool _continuesSuperset(List<ActiveExercise> exercises, int i) {
  final group = exercises[i].supersetGroup;
  return group != null &&
      i + 1 < exercises.length &&
      exercises[i + 1].supersetGroup == group;
}

/// "A", "B", … per superset, in the order they first appear. A group with one
/// exercise left in it gets no letter.
Map<String?, String> supersetLetters(ActiveWorkout workout) {
  final out = <String?, String>{};
  for (final e in workout.exercises) {
    final group = e.supersetGroup;
    if (group == null || out.containsKey(group)) continue;
    if (workout.supersetMembers(group).length < 2) continue;
    out[group] = String.fromCharCode(65 + out.length % 26);
  }
  return out;
}

/// The rest between sets: a countdown draining a bar, with time to add or
/// take off and a way to skip it.
///
/// Counts down from the stored end time, so it is right after the phone was
/// locked. When it runs out with the screen open it buzzes, says so for a few
/// seconds, and goes.
class RestTimerBar extends StatefulWidget {
  const RestTimerBar({
    required this.rest,
    required this.onAdjust,
    required this.onSkip,
    this.now = DateTime.now,
    super.key,
  });

  final RestTimer rest;
  final ValueChanged<int> onAdjust;
  final VoidCallback onSkip;

  /// Injected so a test can drive the clock.
  final DateTime Function() now;

  /// How long "Rest over" stays up once the countdown reaches zero.
  static const lingerFor = Duration(seconds: 4);

  @override
  State<RestTimerBar> createState() => _RestTimerBarState();
}

class _RestTimerBarState extends State<RestTimerBar> {
  Timer? _ticker;

  /// Set while counting down, so the buzz fires once, on the way through
  /// zero — not on opening the screen to a rest that ended an hour ago.
  late bool _running;

  @override
  void initState() {
    super.initState();
    _running = !widget.rest.isOver(widget.now());
    _ticker = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => _tick(),
    );
  }

  @override
  void didUpdateWidget(RestTimerBar old) {
    super.didUpdateWidget(old);
    if (!widget.rest.isOver(widget.now())) _running = true;
  }

  void _tick() {
    if (_running && widget.rest.isOver(widget.now())) {
      _running = false;
      HapticFeedback.heavyImpact();
      SystemSound.play(SystemSoundType.alert);
    }
    setState(() {});
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final now = widget.now();
    final rest = widget.rest;
    final over = rest.isOver(now);
    if (over && now.difference(rest.endsAt) > RestTimerBar.lingerFor) {
      return const SizedBox.shrink();
    }

    final remaining = rest.remaining(now);
    // Rounded up, so "0:00" never shows while there is still time left.
    final seconds = (remaining.inMilliseconds / 1000).ceil();
    final fraction = over
        ? 0.0
        : (remaining.inMilliseconds / (rest.totalSeconds * 1000))
            .clamp(0.0, 1.0);

    Widget adjust(String label, String tooltip, int delta) => Tooltip(
          message: tooltip,
          child: TextButton(
            onPressed: over ? null : () => widget.onAdjust(delta),
            style: TextButton.styleFrom(
              foregroundColor: palette.brandText,
              minimumSize: const Size(48, 40),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GlassWell(
        padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  over
                      ? Icons.notifications_active_rounded
                      : Icons.timer_outlined,
                  color: palette.brandText,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    over
                        ? 'Rest over'
                        : 'Rest ${formatElapsed(Duration(seconds: seconds))}',
                    key: const ValueKey('rest-countdown'),
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: palette.text,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                adjust('−15', 'Take 15 seconds off', -15),
                adjust('+15', 'Add 15 seconds', 15),
                TextButton(
                  onPressed: widget.onSkip,
                  style: TextButton.styleFrom(
                    foregroundColor: palette.muted,
                    minimumSize: const Size(48, 40),
                  ),
                  child: Text(over ? 'Dismiss' : 'Skip'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 4,
                color: palette.brand,
                backgroundColor: palette.stroke,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "42:07", or "1:02:07" past the hour. Counts from [startedAt] by reading the
/// clock each second, so it is right however long the app was away.
class ElapsedClock extends StatefulWidget {
  const ElapsedClock({
    required this.startedAt,
    this.style,
    this.now = DateTime.now,
    super.key,
  });

  final DateTime startedAt;
  final TextStyle? style;

  /// Injected so a test can drive the clock.
  final DateTime Function() now;

  @override
  State<ElapsedClock> createState() => _ElapsedClockState();
}

class _ElapsedClockState extends State<ElapsedClock> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = widget.now().difference(widget.startedAt);
    return Text(
      formatElapsed(elapsed.isNegative ? Duration.zero : elapsed),
      style: widget.style?.copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

/// "5:03", "42:07" or "1:02:07".
String formatElapsed(Duration elapsed) {
  final hours = elapsed.inHours;
  final minutes = elapsed.inMinutes.remainder(60);
  final seconds = elapsed.inSeconds.remainder(60);
  String two(int n) => n.toString().padLeft(2, '0');
  return hours > 0
      ? '$hours:${two(minutes)}:${two(seconds)}'
      : '$minutes:${two(seconds)}';
}

String _formatKg(double kg) {
  if (kg == kg.roundToDouble()) return kg.round().toString();
  return kg.toStringAsFixed(1);
}

/// The colour a personal record is marked in — the achievements gold.
const Color _kRecordHue = Color(0xFFF2B01E);

/// The equipment behind [exerciseId], from the library or the user's own
/// exercises. Null for free-text names.
String? _equipmentFor(WidgetRef ref, String? exerciseId) =>
    ExerciseLibrary.equipmentFor(
      exerciseId,
      custom: ref.read(customExercisesProvider).valueOrNull ?? const [],
    );

/// `1500` seconds → `25`, `750` → `12.5`. Blank for nothing typed.
String _minutesText(int? seconds) {
  if (seconds == null || seconds <= 0) return '';
  final minutes = seconds / 60;
  if (minutes == minutes.roundToDouble()) return '${minutes.round()}';
  return minutes.toStringAsFixed(1);
}

String _kmText(double? km) {
  if (km == null || km <= 0) return '';
  if (km == km.roundToDouble()) return '${km.round()}';
  return km.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
}

enum _ExerciseAction {
  notes,
  warmups,
  plates,
  rest,
  superset,
  unlinkSuperset,
  replace,
  reorder,
  bodyweight,
  remove,
}

/// One input column on a set row.
enum _Field {
  /// Load, in the user's unit. On assisted work, the assistance; on weighted
  /// bodyweight, the weight added.
  kg,
  reps,

  /// A hold, typed as m:ss.
  time,

  /// A cardio interval, typed in minutes.
  minutes,
  km;

  bool get decimal => this == kg || this == minutes || this == km;
}

/// The columns a row shows. With the v2 logger off, a set is load and reps,
/// or minutes and kilometres on a cardio machine, as it always was.
List<_Field> _fieldsFor(TrackingType type,
    {required bool v2, required bool cardio}) {
  if (!v2)
    return cardio
        ? const [_Field.minutes, _Field.km]
        : const [_Field.kg, _Field.reps];
  return switch (type) {
    TrackingType.weightReps ||
    TrackingType.weightedBodyweight ||
    TrackingType.assistedBodyweight =>
      const [_Field.kg, _Field.reps],
    TrackingType.bodyweightReps => const [_Field.reps],
    TrackingType.duration => const [_Field.time],
    TrackingType.weightDuration => const [_Field.kg, _Field.time],
    TrackingType.cardio => const [_Field.minutes, _Field.km],
  };
}

/// Kilograms in storage, the user's unit on screen.
class _Units {
  const _Units({this.imperial = false});

  static const _kgPerLb = 0.45359237;

  final bool imperial;

  String get label => imperial ? 'lb' : 'kg';

  double toDisplay(double kg) => imperial ? kg / _kgPerLb : kg;

  double toKg(double value) => imperial ? value * _kgPerLb : value;

  /// "82.5 kg", "135 lb".
  String weight(double kg) => '${_formatKg(toDisplay(kg))} $label';
}

String _columnLabel(_Field field, TrackingType type, _Units units) =>
    switch (field) {
      _Field.kg => switch (type) {
          TrackingType.weightedBodyweight => '+${units.label.toUpperCase()}',
          TrackingType.assistedBodyweight => '−${units.label.toUpperCase()}',
          _ => units.label.toUpperCase(),
        },
      _Field.reps => 'REPS',
      _Field.time => 'TIME',
      _Field.minutes => 'MIN',
      _Field.km => 'KM',
    };

/// "0:45", "1:02:30".
String _timeText(int? seconds) => seconds == null || seconds <= 0
    ? ''
    : formatElapsed(Duration(seconds: seconds));

/// "1:30" → 90, "45" → 45 seconds. Null when it does not read as a time.
int? _parseTime(String text) {
  final t = text.trim();
  if (t.isEmpty) return 0;
  final parts = t.split(':');
  if (parts.length > 3) return null;
  var seconds = 0;
  for (final part in parts) {
    final n = int.tryParse(part.isEmpty ? '0' : part);
    if (n == null) return null;
    seconds = seconds * 60 + n;
  }
  return seconds;
}

String _fieldText(_Field field, ExerciseSet set, _Units units) =>
    switch (field) {
      _Field.kg =>
        set.weightKg <= 0 ? '' : _formatKg(units.toDisplay(set.weightKg)),
      _Field.reps => set.reps <= 0 ? '' : '${set.reps}',
      _Field.time => _timeText(set.durationSeconds),
      _Field.minutes => _minutesText(set.durationSeconds),
      _Field.km => _kmText(set.distanceKm),
    };

/// Whether [text] already says what [set] holds, so a rebuild does not
/// rewrite a field mid-keystroke ("6." is not "6").
bool _fieldAgrees(_Field field, String text, ExerciseSet set, _Units units) =>
    switch (field) {
      _Field.kg =>
        (units.toKg(parseTypedDouble(text) ?? 0) - set.weightKg).abs() < 0.001,
      _Field.reps => (parseTypedInt(text) ?? 0) == set.reps,
      _Field.time => (_parseTime(text) ?? -1) == (set.durationSeconds ?? 0),
      _Field.minutes => ((parseTypedDouble(text) ?? 0) * 60).round() ==
          (set.durationSeconds ?? 0),
      _Field.km =>
        ((parseTypedDouble(text) ?? 0) - (set.distanceKm ?? 0)).abs() < 0.0001,
    };

/// What last time's set says, in the PREVIOUS column: "82.5 kg × 8", "× 8",
/// "+20 kg × 5", "0:45", "2 km · 10:00".
String _previousLabel(ExerciseSet set, TrackingType type, _Units units) {
  final kg = set.weightKg;
  return switch (type) {
    TrackingType.bodyweightReps => '× ${set.reps}',
    TrackingType.weightedBodyweight => '+${units.weight(kg)} × ${set.reps}',
    TrackingType.assistedBodyweight => '−${units.weight(kg)} × ${set.reps}',
    TrackingType.duration => _timeText(set.durationSeconds),
    TrackingType.weightDuration =>
      '${units.weight(kg)} · ${_timeText(set.durationSeconds)}',
    TrackingType.cardio => [
        if ((set.distanceKm ?? 0) > 0) '${_kmText(set.distanceKm)} km',
        if ((set.durationSeconds ?? 0) > 0) _timeText(set.durationSeconds),
      ].join(' · '),
    TrackingType.weightReps =>
      kg > 0 ? '${units.weight(kg)} × ${set.reps}' : '× ${set.reps}',
  };
}

/// What a blank row shows and takes when ticked: the routine's target where
/// it set one, else last time.
ExerciseSet? _hintFor(ExerciseSet set, ExerciseSet? previous) {
  final target = set.target;
  if (target == null) return previous;
  return ExerciseSet(
    weightKg: target.weightKg ?? previous?.weightKg ?? 0,
    reps: target.adoptedReps ?? previous?.reps ?? 0,
    type: set.type,
    durationSeconds: target.durationSeconds ?? previous?.durationSeconds,
    distanceKm: target.distanceKm ?? previous?.distanceKm,
  );
}

/// "Bench Press (Barbell) · best est. 1RM 102.4 kg" — what a ticked record
/// broke, with the number.
String describeRecordFor(
  String exerciseName,
  Set<PrKind> kinds,
  ExerciseSet set, {
  String unit = 'kg',
  double Function(double kg)? toDisplay,
}) {
  String kg(double v) => '${_formatKg((toDisplay ?? (x) => x)(v))} $unit';
  final what = kinds.contains(PrKind.weight)
      ? 'heaviest weight ${kg(set.weightKg)}'
      : kinds.contains(PrKind.oneRepMax)
          ? 'best est. 1RM ${kg(estimatedOneRepMax(set.weightKg, set.reps))}'
          : kinds.contains(PrKind.repsSet)
              ? 'most reps in a set, ${set.reps}'
              : 'most reps at this weight, ${set.reps}';
  return 'New PR · $exerciseName, $what';
}

/// Above these a typed value is probably a slip of the thumb. Warned about,
/// never refused.
bool _looksHigh(_Field field, ExerciseSet set) => switch (field) {
      _Field.kg => set.weightKg > 500,
      _Field.reps => set.reps > 100,
      _Field.time || _Field.minutes => (set.durationSeconds ?? 0) > 3 * 3600,
      _Field.km => (set.distanceKm ?? 0) > 100,
    };

class _ExerciseCard extends ConsumerStatefulWidget {
  const _ExerciseCard({
    required this.exercise,
    this.supersetLabel,
    this.onSetTicked,
    super.key,
  });

  final ActiveExercise exercise;

  /// "A", "B"… when this exercise is in a superset with at least one other.
  final String? supersetLabel;

  /// Called after a set on this card is ticked off.
  final ValueChanged<String>? onSetTicked;

  @override
  ConsumerState<_ExerciseCard> createState() => _ExerciseCardState();
}

class _ExerciseCardState extends ConsumerState<_ExerciseCard> {
  late final _notes = TextEditingController(text: widget.exercise.sessionNotes);
  late bool _showNotes = widget.exercise.sessionNotes.isNotEmpty;
  final _notesFocus = FocusNode();

  ActiveExercise get exercise => widget.exercise;

  @override
  void dispose() {
    _notes.dispose();
    _notesFocus.dispose();
    super.dispose();
  }

  /// The heaviest working load on the card, the natural target for a
  /// warm-up ramp or the plate maths.
  double get _workingKg => exercise.sets
      .where((s) => s.type.isWorking)
      .fold<double>(0, (top, s) => s.weightKg > top ? s.weightKg : top);

  Future<void> _onAction(_ExerciseAction action) async {
    final controller = ref.read(activeWorkoutProvider.notifier);
    switch (action) {
      case _ExerciseAction.notes:
        setState(() => _showNotes = true);
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _notesFocus.requestFocus());
      case _ExerciseAction.warmups:
        final ramp = await showWarmupSheet(
          context,
          exerciseName: exercise.name,
          workingKg: _workingKg,
          equipment: _equipmentFor(ref, exercise.exerciseId),
        );
        if (ramp != null) controller.addWarmups(exercise.key, ramp);
      case _ExerciseAction.plates:
        await showPlateCalculator(context, initialKg: _workingKg);
      case _ExerciseAction.rest:
        final picked = await showRestOverridePicker(
          context,
          exerciseName: exercise.name,
          current: exercise.restSeconds,
          defaultSeconds: ref.read(workoutPreferencesProvider).restSeconds,
          choices: WorkoutPreferences.restChoices,
        );
        if (picked != null) {
          controller.setRestOverride(exercise.key, picked.seconds);
        }
      case _ExerciseAction.superset:
        final workout = ref.read(activeWorkoutProvider);
        if (workout == null) return;
        final group = exercise.supersetGroup;
        final key = await showSupersetPicker(
          context,
          exerciseName: exercise.name,
          candidates: [
            for (final e in workout.exercises)
              if (e.key != exercise.key &&
                  (group == null || e.supersetGroup != group))
                e,
          ],
        );
        if (key != null) controller.linkSuperset(exercise.key, key);
      case _ExerciseAction.unlinkSuperset:
        controller.unlinkSuperset(exercise.key);
      case _ExerciseAction.replace:
        final picked = await showExercisePicker(context, enhanced: true);
        if (picked == null || !mounted) return;
        final custom =
            ref.read(customExercisesProvider).valueOrNull ?? const [];
        controller.replaceExercise(
          exercise.key,
          name: picked.name,
          exerciseId: picked.id,
          trackingType:
              ExerciseLibrary.trackingTypeFor(picked.id, custom: custom),
        );
      case _ExerciseAction.reorder:
        final workout = ref.read(activeWorkoutProvider);
        if (workout == null) return;
        final order = await showReorderExercisesSheet(
          context,
          exercises: workout.exercises,
        );
        if (order != null) controller.reorderExercises(order);
      case _ExerciseAction.bodyweight:
        final kg = await showBodyweightSheet(
          context,
          current: ref.read(activeWorkoutProvider)?.bodyweightKg,
        );
        if (kg != null) controller.setBodyweight(kg);
      case _ExerciseAction.remove:
        controller.removeExercise(exercise.key);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final controller = ref.read(activeWorkoutProvider.notifier);
    final prefs = ref.watch(workoutPreferencesProvider);
    final v2 = ref.watch(featureEnabledProvider(FeatureFlag.workoutLoggerV2));
    final records = ref.watch(sessionRecordsProvider)[exercise.key] ?? const {};
    final supersetLabel = widget.supersetLabel;
    final inSuperset = supersetLabel != null;
    final rest = exercise.restSeconds;
    final equipment = _equipmentFor(ref, exercise.exerciseId);
    // A rower or an elliptical is logged as time and distance. Kilograms and
    // reps mean nothing on one, and offering only those was why cardio could
    // be logged by name and nothing else.
    final type = exercise.trackingType;
    final cardio = v2 ? type == TrackingType.cardio : equipment == 'cardio';
    final fields = _fieldsFor(type, v2: v2, cardio: cardio);
    final units = v2
        ? _Units(
            imperial: ref.watch(bodyMetricsProvider).valueOrNull?.units ==
                MeasurementUnits.imperial,
          )
        : const _Units();

    final previous = v2
        ? ref.watch(previousPerformanceProvider).lastSets(
              exerciseKeyFor(
                  name: exercise.name, exerciseId: exercise.exerciseId),
              source: prefs.previousSource,
            )
        : null;

    TextStyle head() => TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          color: palette.muted,
        );

    // Warm-ups are not numbered, so the first working set is "1" whatever came
    // before it.
    var working = 0;
    final labels = [
      for (final set in exercise.sets)
        switch (set.type) {
          SetType.warmup => 'W',
          SetType.dropset => 'D',
          SetType.failure => 'F',
          SetType.normal => '${++working}',
        },
    ];

    final caption = v2
        ? [
            if (equipment != null) _capitalised(equipment),
            _typeCaption(type),
          ].join(' · ')
        : null;

    final card = GlassWell(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (inSuperset || rest != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Wrap(
                spacing: 12,
                children: [
                  if (inSuperset)
                    Text('SUPERSET $supersetLabel',
                        style: head().copyWith(color: palette.brandText)),
                  if (rest != null)
                    Text(
                      rest == 0 ? 'NO REST TIMER' : 'REST ${formatRest(rest)}',
                      style: head(),
                    ),
                ],
              ),
            ),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      exercise.name,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: palette.brandText,
                      ),
                    ),
                    if (caption != null && caption.isNotEmpty)
                      Text(
                        caption,
                        style: TextStyle(fontSize: 12, color: palette.muted),
                      ),
                  ],
                ),
              ),
              PopupMenuButton<_ExerciseAction>(
                tooltip: 'Exercise options',
                icon: Icon(Icons.more_horiz_rounded, color: palette.muted),
                onSelected: _onAction,
                itemBuilder: (_) => [
                  if (v2)
                    const PopupMenuItem(
                      value: _ExerciseAction.notes,
                      child: Text('Notes'),
                    ),
                  if (!cardio &&
                      !(v2 &&
                          type.isTimed &&
                          type != TrackingType.weightDuration)) ...[
                    const PopupMenuItem(
                      value: _ExerciseAction.warmups,
                      child: Text('Warm-up sets'),
                    ),
                    if (!v2 || equipment == 'barbell')
                      const PopupMenuItem(
                        value: _ExerciseAction.plates,
                        child: Text('Plate calculator'),
                      ),
                  ],
                  PopupMenuItem(
                    value: _ExerciseAction.rest,
                    child: Text(
                      rest == null
                          ? 'Rest timer'
                          : 'Rest timer (${formatRest(rest)})',
                    ),
                  ),
                  PopupMenuItem(
                    value: _ExerciseAction.superset,
                    child:
                        Text(inSuperset ? 'Add to superset' : 'Superset with…'),
                  ),
                  if (inSuperset)
                    const PopupMenuItem(
                      value: _ExerciseAction.unlinkSuperset,
                      child: Text('Remove from superset'),
                    ),
                  if (v2) ...[
                    const PopupMenuItem(
                      value: _ExerciseAction.replace,
                      child: Text('Replace exercise'),
                    ),
                    const PopupMenuItem(
                      value: _ExerciseAction.reorder,
                      child: Text('Reorder exercises'),
                    ),
                    if (type.usesBodyweight)
                      const PopupMenuItem(
                        value: _ExerciseAction.bodyweight,
                        child: Text('Update bodyweight'),
                      ),
                  ],
                  const PopupMenuItem(
                    value: _ExerciseAction.remove,
                    child: Text('Remove exercise'),
                  ),
                ],
              ),
            ],
          ),
          if (v2 && (exercise.routineNotes?.isNotEmpty ?? false))
            Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 4),
              child: Text(
                exercise.routineNotes!,
                style: TextStyle(fontSize: 13, color: palette.muted),
              ),
            ),
          if (v2 && _showNotes)
            Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 6),
              child: TextField(
                controller: _notes,
                focusNode: _notesFocus,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                style: TextStyle(color: palette.text, fontSize: 14),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: 'Add notes…',
                  hintStyle: TextStyle(color: palette.muted),
                ),
                onChanged: (text) =>
                    controller.setSessionNotes(exercise.key, text),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 8, bottom: 4),
            child: Row(
              children: [
                SizedBox(width: 44, child: Text('SET', style: head())),
                if (v2)
                  SizedBox(
                    width: _previousWidth,
                    child: Text('PREVIOUS', style: head()),
                  ),
                for (var f = 0; f < fields.length; f++) ...[
                  if (f > 0) const SizedBox(width: 8),
                  Expanded(
                    child: Center(
                      child: Text(
                        _columnLabel(fields[f], type, units),
                        style: head(),
                      ),
                    ),
                  ),
                ],
                if (prefs.trackRpe && !(v2 && type.isTimed))
                  SizedBox(
                    width: 44,
                    child: Center(child: Text('RPE', style: head())),
                  ),
                const SizedBox(width: 52),
              ],
            ),
          ),
          for (var i = 0; i < exercise.sets.length; i++)
            Dismissible(
              key: ValueKey('${exercise.key}:$i:${exercise.sets.length}'),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 16),
                color: palette.danger.withValues(alpha: 0.25),
                child:
                    Icon(Icons.delete_outline_rounded, color: palette.danger),
              ),
              onDismissed: (_) => controller.removeSet(exercise.key, i),
              child: _SetRow(
                exerciseKey: exercise.key,
                exerciseName: exercise.name,
                index: i,
                label: labels[i],
                set: exercise.sets[i],
                showRpe: prefs.trackRpe && !(v2 && type.isTimed),
                record: records[i],
                fields: fields,
                trackingType: type,
                v2: v2,
                units: units,
                previous: previous == null
                    ? null
                    : PreviousPerformance.match(previous, exercise.sets, i),
                inlineTimer: v2 && prefs.inlineTimer,
                onTicked: () => widget.onSetTicked?.call(exercise.key),
              ),
            ),
          Center(
            child: TextButton.icon(
              onPressed: () => controller.addSet(exercise.key),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add set'),
              style: TextButton.styleFrom(foregroundColor: palette.brandText),
            ),
          ),
        ],
      ),
    );

    if (!inSuperset) return card;
    // A rail down the left edge ties a superset's cards together.
    return Stack(
      children: [
        Padding(padding: const EdgeInsets.only(left: 10), child: card),
        Positioned(
          left: 0,
          top: 10,
          bottom: 10,
          child: Container(
            width: 4,
            decoration: BoxDecoration(
              color: palette.brand,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ],
    );
  }
}

const double _previousWidth = 78;

String _capitalised(String text) =>
    text.isEmpty ? text : '${text[0].toUpperCase()}${text.substring(1)}';

String _typeCaption(TrackingType type) => switch (type) {
      TrackingType.weightReps => 'weight & reps',
      TrackingType.bodyweightReps => 'bodyweight',
      TrackingType.weightedBodyweight => 'weighted bodyweight',
      TrackingType.assistedBodyweight => 'assisted',
      TrackingType.duration => 'timed',
      TrackingType.weightDuration => 'weight & time',
      TrackingType.cardio => 'time & distance',
    };

class _SetRow extends ConsumerStatefulWidget {
  const _SetRow({
    required this.exerciseKey,
    required this.exerciseName,
    required this.index,
    required this.label,
    required this.set,
    required this.showRpe,
    required this.fields,
    required this.trackingType,
    this.v2 = false,
    this.units = const _Units(),
    this.previous,
    this.record,
    this.inlineTimer = false,
    this.onTicked,
  });

  final String exerciseKey;
  final String exerciseName;
  final int index;
  final String label;
  final ExerciseSet set;
  final bool showRpe;
  final List<_Field> fields;
  final TrackingType trackingType;

  /// The v2 logger: PREVIOUS, hints, the type sheet, high-value warnings.
  final bool v2;
  final _Units units;

  /// Last time's matching set, for the PREVIOUS column and the hints.
  final ExerciseSet? previous;

  /// The records this set broke, when it is ticked off and broke any.
  final Set<PrKind>? record;

  /// A stopwatch on a TIME field.
  final bool inlineTimer;

  final VoidCallback? onTicked;

  @override
  ConsumerState<_SetRow> createState() => _SetRowState();
}

class _SetRowState extends ConsumerState<_SetRow> {
  late final Map<_Field, TextEditingController> _text = {
    for (final f in widget.fields)
      f: TextEditingController(text: _fieldText(f, widget.set, widget.units)),
  };
  late final Map<_Field, FocusNode> _focus = {
    for (final f in widget.fields)
      f: FocusNode()..addListener(() => _onFocus(f)),
  };

  /// When the inline stopwatch was started; null when it is not running.
  DateTime? _stopwatchFrom;
  Timer? _stopwatch;

  @override
  void didUpdateWidget(_SetRow old) {
    super.didUpdateWidget(old);
    // A row can be handed different data without being rebuilt — a set above
    // it was removed — and its fields must follow. Only rewritten when they
    // disagree, so typing "6." is not overwritten with "6" mid-keystroke.
    for (final entry in _text.entries) {
      if (!_fieldAgrees(
          entry.key, entry.value.text, widget.set, widget.units)) {
        entry.value.text = _fieldText(entry.key, widget.set, widget.units);
      }
    }
  }

  @override
  void dispose() {
    _stopwatch?.cancel();
    for (final c in _text.values) {
      c.dispose();
    }
    for (final f in _focus.values) {
      f.dispose();
    }
    super.dispose();
  }

  ActiveWorkoutController get _controller =>
      ref.read(activeWorkoutProvider.notifier);

  ExerciseSet? get _hint =>
      widget.v2 ? _hintFor(widget.set, widget.previous) : null;

  void _write(_Field field, String text) {
    final key = widget.exerciseKey;
    final i = widget.index;
    switch (field) {
      case _Field.kg:
        _controller.updateSet(key, i,
            weightKg: widget.units.toKg(parseTypedDouble(text) ?? 0));
      case _Field.reps:
        _controller.updateSet(key, i, reps: parseTypedInt(text) ?? 0);
      case _Field.time:
        final seconds = _parseTime(text);
        if (seconds != null) {
          _controller.updateSet(key, i, durationSeconds: seconds);
        }
      case _Field.minutes:
        _controller.updateSet(key, i,
            durationSeconds: ((parseTypedDouble(text) ?? 0) * 60).round());
      case _Field.km:
        _controller.updateSet(key, i, distanceKm: parseTypedDouble(text) ?? 0);
    }
  }

  Future<void> _onFocus(_Field field) async {
    if (!widget.v2 || (_focus[field]?.hasFocus ?? true)) return;
    if (!_looksHigh(field, widget.set)) return;
    final value = switch (field) {
      _Field.kg => widget.units.weight(widget.set.weightKg),
      _Field.reps => '${widget.set.reps} reps',
      _Field.time || _Field.minutes => _timeText(widget.set.durationSeconds),
      _Field.km => '${_kmText(widget.set.distanceKm)} km',
    };
    final keep = await confirmHighValue(context, value);
    if (keep || !mounted) return;
    _text[field]!.clear();
    _write(field, '');
    _focus[field]!.requestFocus();
  }

  void _toggleStopwatch() {
    if (_stopwatchFrom != null) {
      _stopwatch?.cancel();
      final seconds = DateTime.now().difference(_stopwatchFrom!).inSeconds;
      setState(() => _stopwatchFrom = null);
      _controller.updateSet(widget.exerciseKey, widget.index,
          durationSeconds: seconds);
      return;
    }
    final from = DateTime.now();
    setState(() => _stopwatchFrom = from);
    _stopwatch = Timer.periodic(const Duration(seconds: 1), (_) {
      final seconds = DateTime.now().difference(from).inSeconds;
      _text[_Field.time]?.text = _timeText(seconds);
    });
  }

  void _copyPrevious() {
    final p = widget.previous;
    if (p == null) return;
    _controller.updateSet(
      widget.exerciseKey,
      widget.index,
      weightKg: widget.fields.contains(_Field.kg) ? p.weightKg : null,
      reps: widget.fields.contains(_Field.reps) ? p.reps : null,
      durationSeconds: p.durationSeconds,
      distanceKm: p.distanceKm,
    );
  }

  Future<void> _pickType() async {
    if (!widget.v2) {
      _controller.updateSet(
        widget.exerciseKey,
        widget.index,
        type: switch (widget.set.type) {
          SetType.normal => SetType.warmup,
          SetType.warmup => SetType.dropset,
          SetType.dropset => SetType.failure,
          SetType.failure => SetType.normal,
        },
      );
      return;
    }
    final choice = await showSetTypeSheet(context, current: widget.set.type);
    if (!mounted) return;
    switch (choice) {
      case SetTypePicked(:final type):
        _controller.updateSet(widget.exerciseKey, widget.index, type: type);
      case SetRemoved():
        _controller.removeSet(widget.exerciseKey, widget.index);
      case null:
        break;
    }
  }

  void _toggleDone() {
    if (_stopwatchFrom != null) _toggleStopwatch();
    final ticking = widget.set.completedAt == null;
    final ok = _controller.toggleDone(
      widget.exerciseKey,
      widget.index,
      defaultRestSeconds: ref.read(workoutPreferencesProvider).restSeconds,
      hint: _hint,
    );
    if (!ok) {
      showQuickToast(
        context,
        switch (widget.fields.first) {
          _Field.minutes || _Field.km => 'Enter the time or distance first.',
          _Field.time => 'Enter the time first.',
          _ when widget.fields.contains(_Field.time) => 'Enter the time first.',
          _ => 'Enter the reps first.',
        },
      );
      return;
    }
    if (!ticking) return;
    widget.onTicked?.call();
    // The first rest of a session is the moment a "your rest is over"
    // notification makes sense to ask about. Asked once per launch at most.
    if (ref.read(activeWorkoutProvider)?.rest != null) {
      unawaited(ref.read(restAlertsProvider).requestPermission());
    }
    final prefs = ref.read(workoutPreferencesProvider);
    if (widget.v2 && !prefs.livePrAlerts) return;
    final broken =
        ref.read(sessionRecordsProvider)[widget.exerciseKey]?[widget.index];
    if (broken != null && broken.isNotEmpty) {
      HapticFeedback.mediumImpact();
      final ticked = ref
          .read(activeWorkoutProvider)
          ?.exercise(widget.exerciseKey)
          ?.sets
          .elementAtOrNull(widget.index);
      showQuickToast(
        context,
        widget.v2 && ticked != null
            ? describeRecordFor(
                widget.exerciseName,
                broken,
                ticked,
                unit: widget.units.label,
                toDisplay: widget.units.toDisplay,
              )
            : 'New PR: ${describeRecord(broken)}',
        icon: Icons.emoji_events_rounded,
        tone: ToastTone.success,
      );
    }
  }

  Future<void> _pickRpe() async {
    final picked = await showRpePicker(context, current: widget.set.rpe);
    if (picked == null || !mounted) return;
    _controller.updateSet(
      widget.exerciseKey,
      widget.index,
      rpe: picked.rpe,
      clearRpe: picked.rpe == null,
    );
  }

  String? _hintText(_Field field) {
    final hint = _hint;
    if (hint == null) return null;
    final target = widget.set.target;
    if (field == _Field.reps &&
        target?.repsMin != null &&
        target?.repsMax != null) {
      return '${target!.repsMin}–${target.repsMax}';
    }
    final text = _fieldText(field, hint, widget.units);
    return text.isEmpty ? null : text;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final done = widget.set.completedAt != null;
    final isRecord = done && (widget.record?.isNotEmpty ?? false);
    final gold = palette.accent(_kRecordHue);
    final v2 = widget.v2;

    Widget field(_Field f) {
      final input = TextField(
        controller: _text[f],
        focusNode: _focus[f],
        textAlign: TextAlign.center,
        keyboardType: f == _Field.time
            ? TextInputType.datetime
            : TextInputType.numberWithOptions(decimal: f.decimal),
        inputFormatters: [
          FilteringTextInputFormatter.allow(
            switch (f) {
              _Field.time => RegExp(r'[0-9:]'),
              _ when f.decimal => RegExp(r'[0-9.,]'),
              _ => RegExp(r'[0-9]'),
            },
          ),
        ],
        readOnly: _stopwatchFrom != null && f == _Field.time,
        style: TextStyle(
          color: palette.text,
          fontSize: 17,
          fontWeight: FontWeight.w800,
        ),
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          hintText: _hintText(f) ?? '—',
          hintStyle: TextStyle(color: palette.muted),
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
        onChanged: (text) => _write(f, text),
      );
      if (f != _Field.time || !widget.inlineTimer)
        return Expanded(child: input);
      final running = _stopwatchFrom != null;
      return Expanded(
        child: Row(
          children: [
            Expanded(child: input),
            SizedBox(
              width: 32,
              child: IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 44),
                tooltip: running ? 'Stop the timer' : 'Time this set',
                icon: Icon(
                  running ? Icons.stop_rounded : Icons.play_arrow_rounded,
                  size: 20,
                  color: running ? palette.brand : palette.muted,
                ),
                onPressed: done ? null : _toggleStopwatch,
              ),
            ),
          ],
        ),
      );
    }

    final rpe = widget.set.rpe;
    final previous = widget.previous;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(
        color: done
            ? (v2 ? palette.accentFill(palette.success) : palette.brandSoft)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                TextButton(
                  onPressed: _pickType,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(44, 44),
                    foregroundColor: v2
                        ? setTypeColor(context, widget.set.type)
                        : switch (widget.set.type) {
                            SetType.normal => palette.text,
                            SetType.warmup => palette.muted,
                            _ => palette.brandText,
                          },
                  ),
                  child: Text(
                    widget.label,
                    semanticsLabel:
                        v2 ? 'Set ${widget.label}, change type' : null,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (isRecord)
                  Positioned(
                    top: 2,
                    right: 2,
                    child: Tooltip(
                      message:
                          'Personal record: ${describeRecord(widget.record!)}',
                      child: Icon(
                        Icons.emoji_events_rounded,
                        key: const ValueKey('set-record'),
                        size: 14,
                        color: v2 ? palette.brand : gold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (v2)
            SizedBox(
              width: _previousWidth,
              child: previous == null
                  ? Text('—', style: TextStyle(color: palette.muted))
                  : InkWell(
                      key: ValueKey('previous-${widget.index}'),
                      borderRadius: BorderRadius.circular(8),
                      onTap: done ? null : _copyPrevious,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 44),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              _previousLabel(
                                previous,
                                widget.trackingType,
                                widget.units,
                              ),
                              semanticsLabel:
                                  'Last time ${_previousLabel(previous, widget.trackingType, widget.units)}, tap to copy',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: palette.muted,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          for (var f = 0; f < widget.fields.length; f++) ...[
            if (f > 0) const SizedBox(width: 8),
            field(widget.fields[f]),
          ],
          if (widget.showRpe)
            SizedBox(
              width: 44,
              child: TextButton(
                onPressed: _pickRpe,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(44, 44),
                  foregroundColor: rpe == null ? palette.muted : palette.text,
                ),
                child: Text(
                  rpe == null ? '—' : formatRpe(rpe),
                  semanticsLabel:
                      rpe == null ? 'Rate this set' : 'RPE ${formatRpe(rpe)}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          SizedBox(
            width: 52,
            child: IconButton(
              tooltip: done ? 'Mark set not done' : 'Mark set done',
              icon: Icon(
                done
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: done
                    ? (v2 ? palette.success : palette.brand)
                    : palette.muted,
              ),
              onPressed: _toggleDone,
            ),
          ),
        ],
      ),
    );
  }
}
