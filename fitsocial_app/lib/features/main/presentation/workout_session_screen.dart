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
import '../domain/active_workout.dart';
import '../domain/workout_models.dart';
import 'exercise_picker_sheet.dart';

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
          for (final exercise in workout.exercises)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: _ExerciseCard(
                key: ValueKey(exercise.key),
                exercise: exercise,
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

class _ExerciseCard extends ConsumerWidget {
  const _ExerciseCard({required this.exercise, super.key});

  final ActiveExercise exercise;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final controller = ref.read(activeWorkoutProvider.notifier);

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

    return GlassWell(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
              PopupMenuButton<String>(
                tooltip: 'Exercise options',
                icon: Icon(Icons.more_horiz_rounded, color: palette.muted),
                onSelected: (value) {
                  if (value == 'remove') {
                    controller.removeExercise(exercise.key);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'remove', child: Text('Remove exercise')),
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
  }
}

class _SetRow extends ConsumerStatefulWidget {
  const _SetRow({
    required this.exerciseKey,
    required this.index,
    required this.label,
    required this.set,
  });

  final String exerciseKey;
  final int index;
  final String label;
  final ExerciseSet set;

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

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final controller = ref.read(activeWorkoutProvider.notifier);
    final done = widget.set.completedAt != null;

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
            child: TextButton(
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
              onPressed: () {
                final ok = controller.toggleDone(
                  widget.exerciseKey,
                  widget.index,
                );
                if (!ok) showQuickToast(context, 'Enter the reps first.');
              },
            ),
          ),
        ],
      ),
    );
  }
}
