import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/input/typed_number.dart';
import '../../../shared/services/instagram_photo_picker.dart';
import '../../../shared/services/workout_card_exporter.dart';
import '../../../shared/widgets/glass_well.dart';
import '../../../shared/widgets/health_pull_card.dart';
import '../../../shared/widgets/keyboard_safe_bottom_bar.dart';
import '../../../shared/widgets/liquid_glass.dart';
import '../../../shared/widgets/quick_toast.dart';
import '../../../shared/widgets/run_summary_card.dart'
    show localBackgroundImage;
import '../../../shared/widgets/save_workout_card_row.dart';
import '../../music/presentation/music_island_action.dart';
import '../../tracking/application/tracking_providers.dart';
import '../../tracking/data/workout_prefill_service.dart';
import '../application/activity_actions.dart';
import '../application/content_providers.dart';
import '../domain/app_models.dart';
import 'exercise_editor_sheet.dart';

/// The training log.
///
/// Built around the person logging their fourth session of the week rather than
/// their first ever. Three things follow from that:
///
///  * **Repeat before entry.** A chip across the top refills the entire form
///    from a session already logged, so the common case is one tap and Save.
///  * **The exercises are the screen.** A real table with a row per lift and a
///    load on each, not one sets/reps pair standing in for a whole session.
///    Volume, sets and reps are then read *out* of that table rather than
///    typed, because they are facts about it.
///  * **Save is always reachable.** It is pinned to the bottom, so the screen
///    is never in a state where finishing it means scrolling first.
class WorkoutLogScreen extends ConsumerStatefulWidget {
  const WorkoutLogScreen({super.key});

  @override
  ConsumerState<WorkoutLogScreen> createState() => _WorkoutLogScreenState();
}

class _WorkoutLogScreenState extends ConsumerState<WorkoutLogScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _durationController;
  late final TextEditingController _caloriesController;
  late final TextEditingController _notesController;

  final List<ExerciseEntry> _exercises = [];

  bool _shareToFeed = true;
  bool _isSaving = false;
  String? _errorMessage;

  /// The chosen backdrop, as a local path. Uploaded on save, not on pick — a
  /// user who backs out of the form should not have left a file behind.
  String? _backgroundPath;

  /// When the session happened. Stamped once on open rather than read at save
  /// time, so the chip cannot say one thing while the record says another —
  /// and moved only by a health pull, which knows when the session really was.
  DateTime _loggedAt = DateTime.now();

  /// The health-store session the form was filled from, if it was.
  HealthWorkoutPrefill? _healthPrefill;
  bool _isPullingHealth = false;

  /// Why the last pull produced nothing, shown under the card.
  String? _healthNote;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _durationController = TextEditingController();
    _caloriesController = TextEditingController();
    _notesController = TextEditingController();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _durationController.dispose();
    _caloriesController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  int get _durationMinutes => parseTypedInt(_durationController.text) ?? 0;

  int get _calories => parseTypedInt(_caloriesController.text) ?? 0;

  int get _totalSets => _exercises.fold<int>(0, (sum, e) => sum + e.sets);

  int get _totalReps =>
      _exercises.fold<int>(0, (sum, e) => sum + e.sets * e.reps);

  /// Sets × reps × load, over every row that carries all three.
  ///
  /// The figure the whole screen is arranged around, and the reason weight is
  /// on the table at all: it is the one number that says how hard the session
  /// was, and it cannot be typed — only derived.
  double get _volumeKg => _exercises.fold<double>(
        0,
        (sum, e) =>
            sum + (e.weightKg == null ? 0 : e.sets * e.reps * e.weightKg!),
      );

  /// The form as the post will carry it, for drawing the card before the save.
  ///
  /// Goes through [WorkoutLogDraft] rather than building a map here so the
  /// file the row below exports is the same document the repository is about
  /// to write — one place decides what "the workout" looks like.
  WorkoutLogDraft get _draft => WorkoutLogDraft(
        title: _titleController.text.trim(),
        durationMinutes: _durationMinutes,
        calories: _calories,
        exercises: List.of(_exercises),
        notes: _notesController.text.trim(),
        shareToFeed: _shareToFeed,
        backgroundImagePath: _backgroundPath,
        loggedAt: _loggedAt,
      );

  /// Whether there is a card worth saving yet. A photo or a lift is enough;
  /// a title on its own is not a workout anyone would put on their wall.
  bool get _hasCard => _exercises.isNotEmpty || _backgroundPath != null;

  /// Fills the whole form from a session already logged.
  void _repeat(RecentWorkout workout) {
    setState(() {
      _titleController.text = workout.title;
      _durationController.text =
          workout.durationMinutes > 0 ? '${workout.durationMinutes}' : '';
      _caloriesController.text =
          workout.calories > 0 ? '${workout.calories}' : '';
      _exercises
        ..clear()
        ..addAll(workout.exercises);
      _errorMessage = null;
    });
    // The numbers are a starting point, not a claim about today — say so, so
    // nobody saves last Tuesday's session by accident.
    showQuickToast(
      context,
      workout.exercises.isEmpty
          ? 'Loaded ${workout.title}. Adjust and save.'
          : 'Loaded ${workout.title} — '
              '${workout.exercises.length} exercises. Adjust and save.',
    );
  }

  /// Reads the latest gym session out of the health store into the form.
  ///
  /// Access is asked for, not checked, for the reason the run log does the
  /// same: the dashboard's gate never covered exercise sessions, so a user
  /// who said yes there can still have nothing readable here.
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
      final prefill = await ref.read(workoutPrefillServiceProvider).latest();
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

  /// Name, duration, calories and the date. Not the exercises: the store has
  /// no idea what was lifted, and the table is left as it is — a repeat chip
  /// may already have filled it, and this must not wipe that out.
  void _applyHealthPrefill(HealthWorkoutPrefill prefill) {
    setState(() {
      _healthPrefill = prefill;
      _loggedAt = prefill.record.startedAt;
      _titleController.text = prefill.title;
      _durationController.text = '${prefill.durationMinutes}';
      _caloriesController.text =
          prefill.calories == null ? '' : '${prefill.calories}';
      _errorMessage = null;
    });
    showQuickToast(
      context,
      'Filled from ${prefill.record.sourceName}. Add your exercises.',
      tone: ToastTone.success,
    );
  }

  /// "Strength training · Today 07:12 · 45 min · 320 kcal".
  static String _describePrefill(HealthWorkoutPrefill prefill) {
    return [
      prefill.title,
      HealthPullCard.whenLabel(prefill.record.startedAt),
      '${prefill.durationMinutes} min',
      if (prefill.calories case final kcal?) '$kcal kcal',
    ].join(' · ');
  }

  Future<void> _addExercise() async {
    final result = await showExerciseEditor(context);
    if (result?.entry == null || !mounted) return;
    setState(() {
      _exercises.add(result!.entry!);
      _errorMessage = null;
    });
  }

  Future<void> _editExercise(int index) async {
    final result = await showExerciseEditor(
      context,
      initial: _exercises[index],
    );
    if (result == null || !mounted) return;
    setState(() {
      if (result.removed) {
        _exercises.removeAt(index);
      } else {
        _exercises[index] = result.entry!;
      }
    });
  }

  /// Picks and crops a backdrop. The cropper downscales and re-encodes, so what
  /// comes back is already feed-spec — the same path a post photo takes.
  Future<void> _pickBackground(ImageSource source) async {
    final path = await InstagramPhotoPicker.pickAndCrop(
      context: context,
      source: source,
    );
    // Null means they backed out of the picker or the cropper. Leave whatever
    // was already chosen rather than clearing it.
    if (path == null || !mounted) return;
    setState(() => _backgroundPath = path);
  }

  Future<void> _saveWorkout() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _errorMessage = 'Give your workout a name.');
      return;
    }
    if (_durationMinutes <= 0) {
      setState(() => _errorMessage = 'Add how long the session lasted.');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final result =
          await ref.read(activityActionsProvider).saveWorkout(_draft);
      if (!mounted) return;
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
    // Errors and the loading state both mean "no chips": the row is an
    // accelerator, and a screen that cannot be used because a convenience
    // failed to load is worse than one without the convenience.
    final recents = ref.watch(recentWorkoutsProvider).valueOrNull ??
        const <RecentWorkout>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Log Workout'),
        actions: const [MusicIslandAction()],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.md,
              ),
              children: [
                _DateChip(loggedAt: _loggedAt),
                if (!kIsWeb) ...[
                  const SizedBox(height: AppSpacing.md),
                  HealthPullCard(
                    busy: _isPullingHealth,
                    filled: _healthPrefill != null,
                    title: _healthPrefill == null
                        ? HealthPullCard.idleTitle
                        : 'Filled from ${_healthPrefill!.record.sourceName}',
                    subtitle: _healthPrefill == null
                        ? 'Pull your latest gym session from Samsung Health '
                            'or your watch'
                        : _describePrefill(_healthPrefill!),
                    note: _healthNote,
                    onTap: _isSaving ? null : _pullFromHealth,
                  ),
                ],
                if (recents.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  _RepeatRow(
                    workouts: recents,
                    onPick: _isSaving ? null : _repeat,
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                _TitleField(
                  controller: _titleController,
                  onChanged: () => setState(() {}),
                ),
                const SizedBox(height: AppSpacing.md),
                _MetricGrid(
                  durationController: _durationController,
                  caloriesController: _caloriesController,
                  onChanged: () => setState(() {}),
                  volumeKg: _volumeKg,
                  totalSets: _totalSets,
                  totalReps: _totalReps,
                ),
                const SizedBox(height: AppSpacing.lg),
                _ExerciseTable(
                  exercises: _exercises,
                  onAdd: _isSaving ? null : _addExercise,
                  onEdit: _isSaving ? null : _editExercise,
                ),
                const SizedBox(height: AppSpacing.lg),
                _NotesField(controller: _notesController),
                const SizedBox(height: AppSpacing.md),
                _PhotoRow(
                  imagePath: _backgroundPath,
                  onPick: _isSaving ? null : _pickBackground,
                  onRemove: _isSaving
                      ? null
                      : () => setState(() => _backgroundPath = null),
                ),
                // The card as a file, the way the run and meal screens offer
                // theirs. Under the photo row because the photo is the one
                // thing here that changes what the card looks like rather
                // than what it says.
                if (!kIsWeb && _hasCard) ...[
                  const SizedBox(height: AppSpacing.sm),
                  SaveWorkoutCardRow(
                    card: WorkoutCardExport(
                      activity: 'Workout',
                      workoutData: _draft.workoutData,
                      background: _backgroundPath == null
                          ? null
                          : localBackgroundImage(_backgroundPath!),
                    ),
                  ),
                ],
                _ErrorBanner(message: _errorMessage),
              ],
            ),
          ),
          _SaveBar(
            shareToFeed: _shareToFeed,
            hasPhoto: _backgroundPath != null,
            isSaving: _isSaving,
            onShareChanged: (value) => setState(() => _shareToFeed = value),
            onSave: _isSaving ? null : _saveWorkout,
          ),
        ],
      ),
    );
  }
}

/// When this session happened.
class _DateChip extends StatelessWidget {
  const _DateChip({required this.loggedAt});

  final DateTime loggedAt;

  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String get _label {
    final day = _days[loggedAt.weekday - 1];
    final month = _months[loggedAt.month - 1];
    final minute = loggedAt.minute.toString().padLeft(2, '0');
    return '$day ${loggedAt.day} $month · ${loggedAt.hour}:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: palette.stroke),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.calendar_today_rounded,
              size: 13,
              color: palette.muted,
            ),
            const SizedBox(width: 7),
            Text(
              _label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: palette.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sessions already logged, offered as a starting point.
class _RepeatRow extends StatelessWidget {
  const _RepeatRow({required this.workouts, required this.onPick});

  final List<RecentWorkout> workouts;
  final ValueChanged<RecentWorkout>? onPick;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Text(
            'REPEAT A SESSION',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: palette.muted,
            ),
          ),
        ),
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: workouts.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final workout = workouts[index];
              return _RepeatChip(
                workout: workout,
                onTap: onPick == null ? null : () => onPick!(workout),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _RepeatChip extends StatelessWidget {
  const _RepeatChip({required this.workout, required this.onTap});

  final RecentWorkout workout;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final count = workout.exercises.length;

    // A pane of glass rather than a flat fill, like every other capsule in the
    // app — the picker on the run screen, the nav itself. The lens paints the
    // chip; all it carries of its own is the hairline.
    return LiquidGlass(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: palette.stroke),
        ),
        // Transparent, so the ripple lands on the glass instead of a slab of
        // colour sitting on top of it.
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            customBorder: const StadiumBorder(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.refresh_rounded,
                    size: 15,
                    color: palette.brandText,
                  ),
                  const SizedBox(width: 7),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 150),
                    child: Text(
                      workout.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: palette.text,
                      ),
                    ),
                  ),
                  // Only when there is something to promise. A chip that says
                  // "3 moves" and then fills nothing in is worse than a bare
                  // title.
                  if (count > 0) ...[
                    const SizedBox(width: 6),
                    Text(
                      '· $count',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: palette.muted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TitleField extends StatelessWidget {
  const _TitleField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    // Underlined in the brand rather than sunk in a well: this is the one field
    // that names the thing, and on a screen of wells it has to outrank them.
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: palette.brand, width: 2),
        ),
      ),
      child: TextField(
        controller: controller,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.next,
        style: TextStyle(
          color: palette.text,
          fontSize: 21,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
        ),
        decoration: InputDecoration(
          // All three, not just `border`. The app's inputDecorationTheme sets
          // enabledBorder and focusedBorder, and InputDecoration only falls
          // back to `border` when those are null — so clearing `border` alone
          // leaves the theme's rounded outline drawn around a field that is
          // supposed to be a single underline.
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
          isDense: true,
          hintText: 'Name this session',
          hintStyle: TextStyle(
            color: palette.muted,
            fontSize: 21,
            fontWeight: FontWeight.w700,
          ),
          contentPadding: const EdgeInsets.only(bottom: 9),
        ),
        onChanged: (_) => onChanged(),
      ),
    );
  }
}

/// Duration and calories are typed; volume and sets are read off the table.
///
/// They share one grid because they are the same kind of thing to the reader —
/// the session's headline figures — and separating "yours" from "ours" into two
/// blocks would be an implementation detail drawn on the screen.
class _MetricGrid extends StatelessWidget {
  const _MetricGrid({
    required this.durationController,
    required this.caloriesController,
    required this.onChanged,
    required this.volumeKg,
    required this.totalSets,
    required this.totalReps,
  });

  final TextEditingController durationController;
  final TextEditingController caloriesController;
  final VoidCallback onChanged;
  final double volumeKg;
  final int totalSets;
  final int totalReps;

  /// `3885` → `3,885`.
  static String grouped(int value) {
    final digits = value.abs().toString();
    final buffer = StringBuffer(value < 0 ? '-' : '');
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: palette.stroke),
      ),
      child: Column(
        children: [
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: _EditableMetric(
                    icon: Icons.timer_outlined,
                    label: 'Duration',
                    unit: 'min',
                    controller: durationController,
                    onChanged: onChanged,
                  ),
                ),
                _VerticalRule(color: palette.stroke),
                Expanded(
                  child: _EditableMetric(
                    icon: Icons.local_fire_department_outlined,
                    label: 'Calories',
                    unit: 'kcal',
                    controller: caloriesController,
                    onChanged: onChanged,
                  ),
                ),
              ],
            ),
          ),
          Container(height: 1, color: palette.stroke),
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: _DerivedMetric(
                    icon: Icons.fitness_center_rounded,
                    label: 'Volume',
                    value: volumeKg > 0 ? grouped(volumeKg.round()) : '—',
                    unit: volumeKg > 0 ? 'kg' : null,
                    hint: volumeKg > 0 ? null : 'Add a weight',
                  ),
                ),
                _VerticalRule(color: palette.stroke),
                Expanded(
                  child: _DerivedMetric(
                    icon: Icons.repeat_rounded,
                    label: 'Sets',
                    value: totalSets > 0 ? '$totalSets' : '—',
                    hint: totalReps > 0 ? '$totalReps reps' : 'From the table',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VerticalRule extends StatelessWidget {
  const _VerticalRule({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(width: 1, color: color);
}

class _MetricLabel extends StatelessWidget {
  const _MetricLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Row(
      children: [
        Icon(icon, size: 14, color: palette.muted),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label.toUpperCase(),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              color: palette.muted,
            ),
          ),
        ),
      ],
    );
  }
}

class _EditableMetric extends StatelessWidget {
  const _EditableMetric({
    required this.icon,
    required this.label,
    required this.unit,
    required this.controller,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final String unit;
  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MetricLabel(icon: icon, label: label),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                    color: palette.text,
                  ),
                  decoration: InputDecoration(
                    // See [_TitleField]: the theme's own borders have to be
                    // cleared by name. The grid draws the cell's edges.
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    isDense: true,
                    hintText: '0',
                    hintStyle: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: palette.muted,
                    ),
                    contentPadding: const EdgeInsets.only(top: 6, bottom: 2),
                  ),
                  onChanged: (_) => onChanged(),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                unit,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: palette.muted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DerivedMetric extends StatelessWidget {
  const _DerivedMetric({
    required this.icon,
    required this.label,
    required this.value,
    this.unit,
    this.hint,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? unit;

  /// The quiet line under the figure — what it is made of, or how to make one.
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isEmpty = value == '—';

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MetricLabel(icon: icon, label: label),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                    // Derived figures take the brand once they exist, which is
                    // what separates them at a glance from the two above that
                    // the user typed.
                    color: isEmpty ? palette.muted : palette.brandText,
                  ),
                ),
              ),
              if (unit != null) ...[
                const SizedBox(width: 4),
                Text(
                  unit!,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: palette.muted,
                  ),
                ),
              ],
            ],
          ),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                hint!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: palette.muted),
              ),
            ),
        ],
      ),
    );
  }
}

/// The log itself: a row per exercise, tapped to edit.
class _ExerciseTable extends StatelessWidget {
  const _ExerciseTable({
    required this.exercises,
    required this.onAdd,
    required this.onEdit,
  });

  final List<ExerciseEntry> exercises;
  final VoidCallback? onAdd;
  final ValueChanged<int>? onEdit;

  /// Matches the feed card's columns, so the table someone fills in and the
  /// card their followers read are laid out the same way.
  static const double _setsWidth = 44;
  static const double _repsWidth = 44;
  static const double _loadWidth = 62;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 10),
          child: Row(
            children: [
              Text(
                'EXERCISES',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: palette.muted,
                ),
              ),
              const Spacer(),
              if (exercises.isNotEmpty)
                Text(
                  '${exercises.length}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: palette.muted,
                  ),
                ),
            ],
          ),
        ),
        if (exercises.isEmpty)
          _EmptyTable(onAdd: onAdd)
        else
          Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: Row(
                  children: [
                    Expanded(child: _ColumnHead('Exercise')),
                    SizedBox(
                      width: _setsWidth,
                      child: _ColumnHead('Sets', end: true),
                    ),
                    SizedBox(
                      width: _repsWidth,
                      child: _ColumnHead('Reps', end: true),
                    ),
                    SizedBox(
                      width: _loadWidth,
                      child: _ColumnHead('kg', end: true),
                    ),
                  ],
                ),
              ),
              for (var i = 0; i < exercises.length; i++)
                _ExerciseRow(
                  exercise: exercises[i],
                  onTap: onEdit == null ? null : () => onEdit!(i),
                ),
              const SizedBox(height: 10),
              _AddExerciseButton(onAdd: onAdd),
            ],
          ),
      ],
    );
  }
}

class _ColumnHead extends StatelessWidget {
  const _ColumnHead(this.label, {this.end = false});

  final String label;
  final bool end;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      textAlign: end ? TextAlign.right : TextAlign.left,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
        color: context.palette.muted,
      ),
    );
  }
}

class _ExerciseRow extends StatelessWidget {
  const _ExerciseRow({required this.exercise, required this.onTap});

  final ExerciseEntry exercise;
  final VoidCallback? onTap;

  /// `60.0` → `60`, `22.5` → `22.5`.
  static String trimmed(double value) {
    final text = value.toStringAsFixed(1);
    return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.nested),
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: palette.stroke)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                exercise.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: palette.text,
                ),
              ),
            ),
            _Cell(
              width: _ExerciseTable._setsWidth,
              text: exercise.sets > 0 ? '${exercise.sets}' : '—',
              muted: exercise.sets == 0,
            ),
            _Cell(
              width: _ExerciseTable._repsWidth,
              text: exercise.reps > 0 ? '${exercise.reps}' : '—',
              muted: exercise.reps == 0,
            ),
            _Cell(
              width: _ExerciseTable._loadWidth,
              text:
                  exercise.weightKg == null ? '—' : trimmed(exercise.weightKg!),
              muted: exercise.weightKg == null,
            ),
          ],
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.width,
    required this.text,
    required this.muted,
  });

  final double width;
  final String text;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return SizedBox(
      width: width,
      child: Text(
        text,
        textAlign: TextAlign.right,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w700,
          color: muted ? palette.muted : palette.text,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _EmptyTable extends StatelessWidget {
  const _EmptyTable({required this.onAdd});

  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return LiquidGlass(
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: palette.stroke),
        ),
        child: Column(
          children: [
            Text(
              'Add the lifts you did, with the load on each. '
              'Volume adds itself up.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.muted,
                fontSize: 13,
                height: 1.35,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _AddExerciseButton(onAdd: onAdd),
          ],
        ),
      ),
    );
  }
}

class _AddExerciseButton extends StatelessWidget {
  const _AddExerciseButton({required this.onAdd});

  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Material(
      color: palette.brandSoft,
      borderRadius: BorderRadius.circular(AppRadius.field),
      child: InkWell(
        onTap: onAdd,
        borderRadius: BorderRadius.circular(AppRadius.field),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.field),
            border: Border.all(color: palette.brandSoftStroke),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_rounded, size: 18, color: palette.brandText),
              const SizedBox(width: 8),
              Text(
                'Add exercise',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: palette.brandText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotesField extends StatelessWidget {
  const _NotesField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return GlassWell(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: TextField(
        controller: controller,
        maxLines: 3,
        textCapitalization: TextCapitalization.sentences,
        style: TextStyle(color: palette.text, height: 1.4, fontSize: 14),
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: 'Notes — how did it feel?',
          hintStyle: TextStyle(color: palette.muted, fontSize: 14),
        ),
      ),
    );
  }
}

/// The backdrop for the shared card, as one row rather than a section.
///
/// It matters — it decides what the post looks like — but it is not what the
/// screen is for, and the old form gave it a whole block above the fold's worth
/// of attention. Chosen, it shows a thumbnail; unchosen, it says so.
class _PhotoRow extends StatelessWidget {
  const _PhotoRow({
    required this.imagePath,
    required this.onPick,
    required this.onRemove,
  });

  final String? imagePath;
  final ValueChanged<ImageSource>? onPick;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final path = imagePath;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.field),
        border: Border.all(color: palette.stroke),
      ),
      child: Row(
        children: [
          if (path == null)
            Icon(Icons.image_outlined, size: 20, color: palette.muted)
          else
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 34,
                height: 34,
                child: _BackgroundThumb(path: path),
              ),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              path == null ? 'Card photo' : 'Photo added',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: palette.text,
              ),
            ),
          ),
          if (path == null) ...[
            // Two discs rather than [BackgroundPickerRow]: that widget is a
            // full-width pair of labelled buttons built for a section of its
            // own, and it splits its width with Expanded — which cannot be a
            // non-flex child of this row at all.
            _PhotoAction(
              icon: Icons.photo_library_rounded,
              tooltip: 'Choose from gallery',
              onTap: onPick == null ? null : () => onPick!(ImageSource.gallery),
            ),
            const SizedBox(width: 8),
            _PhotoAction(
              icon: Icons.photo_camera_rounded,
              tooltip: 'Take a photo',
              onTap: onPick == null ? null : () => onPick!(ImageSource.camera),
            ),
          ] else
            TextButton(
              onPressed: onRemove,
              child: Text(
                'Remove',
                style: TextStyle(
                  color: palette.danger,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PhotoAction extends StatelessWidget {
  const _PhotoAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: palette.surfaceHigh,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(icon, size: 18, color: palette.text),
          ),
        ),
      ),
    );
  }
}

/// The picked file, drawn from disk.
///
/// On web `image_picker` hands back a `blob:` URL rather than a real path, so
/// `File` cannot open it — [Image.network] is what reads a blob.
class _BackgroundThumb extends StatelessWidget {
  const _BackgroundThumb({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Image.network(path, fit: BoxFit.cover);
    }
    return Image.file(File(path), fit: BoxFit.cover);
  }
}

/// Share and Save, pinned so the screen always has an end.
class _SaveBar extends StatelessWidget {
  const _SaveBar({
    required this.shareToFeed,
    required this.hasPhoto,
    required this.isSaving,
    required this.onShareChanged,
    required this.onSave,
  });

  final bool shareToFeed;
  final bool hasPhoto;
  final bool isSaving;
  final ValueChanged<bool> onShareChanged;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return KeyboardSafeBottomBar(
      child: Container(
        padding:
            const EdgeInsets.fromLTRB(AppSpacing.md, 12, AppSpacing.md, 12),
        decoration: BoxDecoration(
          color: palette.surface,
          border: Border(top: BorderSide(color: palette.stroke)),
        ),
        child: Row(
          children: [
            Switch(
              value: shareToFeed,
              onChanged: isSaving ? null : onShareChanged,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Share to feed',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: palette.text,
                    ),
                  ),
                  Text(
                    shareToFeed
                        ? (hasPhoto ? 'With your photo' : 'As a log sheet')
                        : 'Saved to your log only',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: palette.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _SaveButton(isSaving: isSaving, onSave: onSave),
          ],
        ),
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.isSaving, required this.onSave});

  final bool isSaving;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.palette.brand,
      borderRadius: BorderRadius.circular(AppRadius.field),
      child: InkWell(
        onTap: onSave,
        borderRadius: BorderRadius.circular(AppRadius.field),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isSaving)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(AppColors.onBrand),
                  ),
                )
              else
                const Icon(
                  Icons.check_rounded,
                  size: 18,
                  color: AppColors.onBrand,
                ),
              const SizedBox(width: 8),
              Text(
                isSaving ? 'Saving' : 'Save',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.onBrand,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: message == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: palette.danger.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadius.field),
                  border: Border.all(
                    color: palette.danger.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      size: 18,
                      color: palette.danger,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        message!,
                        style: TextStyle(color: palette.danger),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
