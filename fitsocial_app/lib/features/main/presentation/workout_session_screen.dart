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
import '../application/active_workout_controller.dart';
import '../application/activity_actions.dart';
import '../application/workout_library_providers.dart';
import '../application/workout_preferences.dart';
import '../data/workout_preferences_store.dart';
import '../domain/active_workout.dart';
import '../domain/exercise_library.dart';
import '../domain/workout_math.dart';
import '../domain/workout_models.dart';
import 'exercise_picker_sheet.dart';
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
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  ActiveWorkoutController get _controller =>
      ref.read(activeWorkoutProvider.notifier);

  Future<void> _addExercise() async {
    final picked = await showExercisePicker(context);
    if (picked == null || !mounted) return;
    _controller.addExercise(name: picked.name, exerciseId: picked.id);
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
          sum +
          e.sets.where((s) => s.completedAt == null && s.reps > 0).length,
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
      final result =
          await ref.read(activityActionsProvider).saveWorkout(draft);
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
          for (var i = 0; i < workout.exercises.length; i++)
            Padding(
              // A superset's cards sit close, so they read as one block.
              padding: EdgeInsets.only(
                bottom: _continuesSuperset(workout.exercises, i)
                    ? AppSpacing.xs
                    : AppSpacing.md,
              ),
              child: _ExerciseCard(
                key: ValueKey(workout.exercises[i].key),
                exercise: workout.exercises[i],
                supersetLabel:
                    letters[workout.exercises[i].supersetGroup],
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
class _StatsStrip extends StatelessWidget {
  const _StatsStrip({required this.workout});

  final ActiveWorkout workout;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

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
            Text('${_formatKg(workout.volumeKg)} kg', style: valueStyle),
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
                    over ? 'Rest over' : 'Rest ${formatElapsed(Duration(seconds: seconds))}',
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
String? _equipmentFor(WidgetRef ref, String? exerciseId) {
  if (exerciseId == null) return null;
  final library = ExerciseLibrary.byId(exerciseId);
  if (library != null) return library.equipment;
  final custom = ref.read(customExercisesProvider).valueOrNull ?? const [];
  for (final c in custom) {
    if (customExerciseId(c.id) == exerciseId) return c.equipment;
  }
  return null;
}

enum _ExerciseAction {
  warmups,
  plates,
  rest,
  superset,
  unlinkSuperset,
  remove,
}

class _ExerciseCard extends ConsumerWidget {
  const _ExerciseCard({
    required this.exercise,
    this.supersetLabel,
    super.key,
  });

  final ActiveExercise exercise;

  /// "A", "B"… when this exercise is in a superset with at least one other.
  final String? supersetLabel;

  /// The heaviest working load on the card, the natural target for a
  /// warm-up ramp or the plate maths.
  double get _workingKg => exercise.sets
      .where((s) => s.type.isWorking)
      .fold<double>(0, (top, s) => s.weightKg > top ? s.weightKg : top);

  Future<void> _onAction(
    BuildContext context,
    WidgetRef ref,
    _ExerciseAction action,
  ) async {
    final controller = ref.read(activeWorkoutProvider.notifier);
    switch (action) {
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
      case _ExerciseAction.remove:
        controller.removeExercise(exercise.key);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final controller = ref.read(activeWorkoutProvider.notifier);
    final prefs = ref.watch(workoutPreferencesProvider);
    final records =
        ref.watch(sessionRecordsProvider)[exercise.key] ?? const {};
    final inSuperset = supersetLabel != null;
    final rest = exercise.restSeconds;

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
                child: Text(
                  exercise.name,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: palette.brandText,
                  ),
                ),
              ),
              PopupMenuButton<_ExerciseAction>(
                tooltip: 'Exercise options',
                icon: Icon(Icons.more_horiz_rounded, color: palette.muted),
                onSelected: (action) => _onAction(context, ref, action),
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: _ExerciseAction.warmups,
                    child: Text('Warm-up sets'),
                  ),
                  const PopupMenuItem(
                    value: _ExerciseAction.plates,
                    child: Text('Plate calculator'),
                  ),
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
                    child: Text(inSuperset ? 'Add to superset' : 'Superset with…'),
                  ),
                  if (inSuperset)
                    const PopupMenuItem(
                      value: _ExerciseAction.unlinkSuperset,
                      child: Text('Remove from superset'),
                    ),
                  const PopupMenuItem(
                    value: _ExerciseAction.remove,
                    child: Text('Remove exercise'),
                  ),
                ],
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8, bottom: 4),
            child: Row(
              children: [
                SizedBox(width: 44, child: Text('SET', style: head())),
                Expanded(
                  child: Center(child: Text('KG', style: head())),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Center(child: Text('REPS', style: head())),
                ),
                if (prefs.trackRpe)
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
                child: Icon(Icons.delete_outline_rounded,
                    color: palette.danger),
              ),
              onDismissed: (_) => controller.removeSet(exercise.key, i),
              child: _SetRow(
                exerciseKey: exercise.key,
                index: i,
                label: labels[i],
                set: exercise.sets[i],
                showRpe: prefs.trackRpe,
                record: records[i],
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

class _SetRow extends ConsumerStatefulWidget {
  const _SetRow({
    required this.exerciseKey,
    required this.index,
    required this.label,
    required this.set,
    required this.showRpe,
    this.record,
  });

  final String exerciseKey;
  final int index;
  final String label;
  final ExerciseSet set;
  final bool showRpe;

  /// The records this set broke, when it is ticked off and broke any.
  final Set<PrKind>? record;

  @override
  ConsumerState<_SetRow> createState() => _SetRowState();
}

class _SetRowState extends ConsumerState<_SetRow> {
  late final TextEditingController _weight;
  late final TextEditingController _reps;

  @override
  void initState() {
    super.initState();
    _weight = TextEditingController(text: _weightText(widget.set.weightKg));
    _reps = TextEditingController(text: _repsText(widget.set.reps));
  }

  @override
  void didUpdateWidget(_SetRow old) {
    super.didUpdateWidget(old);
    // A row can be handed different data without being rebuilt — a set above
    // it was removed — and its fields must follow. Only rewritten when they
    // disagree, so typing "6." is not overwritten with "6" mid-keystroke.
    final weight = parseTypedDouble(_weight.text) ?? 0;
    if ((weight - widget.set.weightKg).abs() > 0.0001) {
      _weight.text = _weightText(widget.set.weightKg);
    }
    final reps = parseTypedInt(_reps.text) ?? 0;
    if (reps != widget.set.reps) _reps.text = _repsText(widget.set.reps);
  }

  @override
  void dispose() {
    _weight.dispose();
    _reps.dispose();
    super.dispose();
  }

  static String _weightText(double kg) => kg <= 0 ? '' : _formatKg(kg);
  static String _repsText(int reps) => reps <= 0 ? '' : '$reps';

  static SetType _nextType(SetType type) => switch (type) {
        SetType.normal => SetType.warmup,
        SetType.warmup => SetType.dropset,
        SetType.dropset => SetType.failure,
        SetType.failure => SetType.normal,
      };

  void _toggleDone() {
    final controller = ref.read(activeWorkoutProvider.notifier);
    final ticking = widget.set.completedAt == null;
    final ok = controller.toggleDone(
      widget.exerciseKey,
      widget.index,
      defaultRestSeconds: ref.read(workoutPreferencesProvider).restSeconds,
    );
    if (!ok) {
      showQuickToast(context, 'Enter the reps first.');
      return;
    }
    if (!ticking) return;
    final broken =
        ref.read(sessionRecordsProvider)[widget.exerciseKey]?[widget.index];
    if (broken != null && broken.isNotEmpty) {
      HapticFeedback.mediumImpact();
      showQuickToast(
        context,
        'New PR: ${describeRecord(broken)}',
        icon: Icons.emoji_events_rounded,
        tone: ToastTone.success,
      );
    }
  }

  Future<void> _pickRpe() async {
    final picked = await showRpePicker(context, current: widget.set.rpe);
    if (picked == null || !mounted) return;
    ref.read(activeWorkoutProvider.notifier).updateSet(
          widget.exerciseKey,
          widget.index,
          rpe: picked.rpe,
          clearRpe: picked.rpe == null,
        );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final controller = ref.read(activeWorkoutProvider.notifier);
    final done = widget.set.completedAt != null;
    final isRecord = done && (widget.record?.isNotEmpty ?? false);
    final gold = palette.accent(_kRecordHue);

    Widget field(TextEditingController c, {required bool decimal, required ValueChanged<String> onChanged}) {
      return Expanded(
        child: TextField(
          controller: c,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.numberWithOptions(decimal: decimal),
          inputFormatters: [
            FilteringTextInputFormatter.allow(
              decimal ? RegExp(r'[0-9.,]') : RegExp(r'[0-9]'),
            ),
          ],
          style: TextStyle(
            color: palette.text,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
          decoration: InputDecoration(
            isDense: true,
            border: InputBorder.none,
            hintText: '—',
            hintStyle: TextStyle(color: palette.muted),
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
          ),
          onChanged: onChanged,
        ),
      );
    }

    final rpe = widget.set.rpe;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(
        color: done ? palette.brandSoft : Colors.transparent,
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
                  onPressed: () => controller.updateSet(
                    widget.exerciseKey,
                    widget.index,
                    type: _nextType(widget.set.type),
                  ),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(44, 44),
                    foregroundColor: switch (widget.set.type) {
                      SetType.normal => palette.text,
                      SetType.warmup => palette.muted,
                      _ => palette.brandText,
                    },
                  ),
                  child: Text(
                    widget.label,
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
                        color: gold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          field(
            _weight,
            decimal: true,
            onChanged: (text) => controller.updateSet(
              widget.exerciseKey,
              widget.index,
              weightKg: parseTypedDouble(text) ?? 0,
            ),
          ),
          const SizedBox(width: 8),
          field(
            _reps,
            decimal: false,
            onChanged: (text) => controller.updateSet(
              widget.exerciseKey,
              widget.index,
              reps: parseTypedInt(text) ?? 0,
            ),
          ),
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
                color: done ? palette.brand : palette.muted,
              ),
              onPressed: _toggleDone,
            ),
          ),
        ],
      ),
    );
  }
}
