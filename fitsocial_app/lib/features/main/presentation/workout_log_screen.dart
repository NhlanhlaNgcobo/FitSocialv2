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
import '../application/active_workout_controller.dart';
import '../application/activity_actions.dart';
import '../application/content_providers.dart';
import '../domain/app_models.dart';
import '../domain/workout_math.dart';
import 'exercise_picker_sheet.dart';
import 'tag_people_sheet.dart';

/// The training log.
///
/// Built around the person logging their fourth session of the week rather than
/// their first ever. Three things follow from that:
///
///  * **Repeat before entry.** A chip across the top refills the entire form
///    from a session already logged, so the common case is one tap and Save.
///  * **The exercises are the screen.** A card per lift, picked from the
///    exercise library, with its sets, reps and load typed straight into it —
///    not one sets/reps pair standing in for a whole session. Volume, sets and
///    reps are then read *out* of the cards rather than typed, because they
///    are facts about them.
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

  final List<_LogRow> _rows = [];
  int _nextRowId = 0;

  bool _shareToFeed = true;
  List<TaggedUser> _taggedUsers = const [];
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
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  int get _durationMinutes => parseTypedInt(_durationController.text) ?? 0;

  int get _calories => parseTypedInt(_caloriesController.text) ?? 0;

  List<ExerciseEntry> get _exercises => [for (final row in _rows) row.toEntry()];

  int get _totalSets => _exercises.fold<int>(0, (sum, e) => sum + e.sets);

  int get _totalReps =>
      _exercises.fold<int>(0, (sum, e) => sum + e.sets * e.reps);

  /// Sets × reps × load, over every row that carries all three.
  ///
  /// The figure the whole screen is arranged around, and the reason weight is
  /// on the cards at all: it is the one number that says how hard the session
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
        exercises: _exercises,
        notes: _notesController.text.trim(),
        shareToFeed: _shareToFeed,
        backgroundImagePath: _backgroundPath,
        loggedAt: _loggedAt,
        taggedUsers: _shareToFeed ? _taggedUsers : const [],
      );

  /// Whether there is a card worth saving yet. A photo or a lift is enough;
  /// a title on its own is not a workout anyone would put on their wall.
  bool get _hasCard => _rows.isNotEmpty || _backgroundPath != null;

  _LogRow _rowFrom(ExerciseEntry entry) => _LogRow(
        _nextRowId++,
        name: entry.name,
        exerciseId: entry.exerciseId,
        sets: entry.sets,
        reps: entry.reps,
        weightKg: entry.weightKg,
      );

  void _replaceRows(Iterable<ExerciseEntry> entries) {
    for (final row in _rows) {
      row.dispose();
    }
    _rows
      ..clear()
      ..addAll(entries.map(_rowFrom));
  }

  /// Fills the whole form from a session already logged.
  void _repeat(RecentWorkout workout) {
    setState(() {
      _titleController.text = workout.title;
      _durationController.text =
          workout.durationMinutes > 0 ? '${workout.durationMinutes}' : '';
      _caloriesController.text =
          workout.calories > 0 ? '${workout.calories}' : '';
      _replaceRows(workout.exercises);
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
  /// no idea what was lifted, and the cards are left as they are — a repeat
  /// chip may already have filled them, and this must not wipe that out.
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

  /// Starts a live session — or opens the one already running, which is never
  /// replaced from here — on top of this screen, so backing out of it lands
  /// back on the log.
  Future<void> _startLiveWorkout() async {
    await ref.read(activeWorkoutProvider.notifier).ensureStarted();
    if (mounted) context.push('/workout-session');
  }

  /// Picks a movement from the library and adds it as a card, filled in with
  /// what was logged for it last time — or 3 × 10 for one never logged, a
  /// starting point to adjust rather than a blank to fill.
  Future<void> _addExercise() async {
    final picked = await showExercisePicker(context);
    if (picked == null || !mounted) return;
    final last = _lastLogged(picked.name, picked.id);
    setState(() {
      _rows.add(_LogRow(
        _nextRowId++,
        name: picked.name,
        exerciseId: picked.id,
        sets: last?.sets ?? 3,
        reps: last?.reps ?? 10,
        weightKg: last?.weightKg,
      ));
      _errorMessage = null;
    });
  }

  /// The most recent logged entry for this movement with numbers on it, or
  /// null when there is none or the history has not loaded.
  ExerciseEntry? _lastLogged(String name, String? exerciseId) {
    final history = ref.read(workoutHistoryProvider).valueOrNull;
    if (history == null) return null;
    final key = exerciseKeyFor(name: name, exerciseId: exerciseId);
    for (final workout in history) {
      for (final entry in workout) {
        if (exerciseKey(entry) == key && entry.sets > 0 && entry.reps > 0) {
          return entry;
        }
      }
    }
    return null;
  }

  void _removeExercise(int index) {
    setState(() => _rows.removeAt(index).dispose());
  }

  /// [to] is already the item's final position: `onReorderItem`, unlike the
  /// deprecated `onReorder`, accounts for the item being lifted out.
  void _reorderExercise(int from, int to) {
    setState(() => _rows.insert(to, _rows.removeAt(from)));
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
    // Watched so it is loaded by the time an exercise is picked: a new card is
    // filled in from the last time that movement was logged.
    ref.watch(workoutHistoryProvider);

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
                _LiveWorkoutCard(
                  inProgress: ref.watch(activeWorkoutProvider) != null,
                  onTap: _isSaving ? null : _startLiveWorkout,
                ),
                const SizedBox(height: AppSpacing.md),
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
                _ExerciseCards(
                  rows: _rows,
                  onAdd: _isSaving ? null : _addExercise,
                  onRemove: _isSaving ? null : _removeExercise,
                  onReorder: _reorderExercise,
                  onChanged: () => setState(() {}),
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
                if (_shareToFeed) ...[
                  const SizedBox(height: AppSpacing.md),
                  TagPeopleRow(
                    tagged: _taggedUsers,
                    onTap: _isSaving ? null : _pickTaggedPeople,
                  ),
                ],
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

/// The other way to log a workout: live, set by set, with a clock. First on
/// the screen because it is a choice made before anything below is filled in.
/// Says "Resume" while a session is running, since that is what a tap does.
class _LiveWorkoutCard extends StatelessWidget {
  const _LiveWorkoutCard({required this.inProgress, required this.onTap});

  final bool inProgress;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return LiquidGlass(
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
              border: Border.all(
                color: inProgress ? palette.brand : palette.brandSoftStroke,
              ),
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
                  child: Icon(
                    Icons.timer_rounded,
                    color: palette.brand,
                    size: 22,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        inProgress ? 'Resume your workout' : 'Start a workout',
                        style: TextStyle(
                          color: palette.text,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        inProgress
                            ? 'Pick up where you left off'
                            : 'Log it live, set by set, with a timer and '
                                'rest between sets',
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
                  Icons.chevron_right_rounded,
                  color: palette.muted,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
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

/// Duration and calories are typed; volume and sets are read off the cards.
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
                    hint: totalReps > 0 ? '$totalReps reps' : 'From your exercises',
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

/// One exercise on the log, being filled in. Holds its own controllers so the
/// numbers typed into it survive a reorder.
class _LogRow {
  _LogRow(
    this.id, {
    required this.name,
    this.exerciseId,
    int sets = 0,
    int reps = 0,
    double? weightKg,
  })  : sets = TextEditingController(text: sets > 0 ? '$sets' : ''),
        reps = TextEditingController(text: reps > 0 ? '$reps' : ''),
        weight = TextEditingController(
          text: weightKg == null || weightKg <= 0 ? '' : _trimmed(weightKg),
        );

  /// Identifies the row for reordering; unrelated to the exercise.
  final int id;
  final String name;

  /// The library or custom exercise it was picked as. Null for a free-text
  /// name, and for rows repeated from workouts logged before the library.
  final String? exerciseId;

  final TextEditingController sets;
  final TextEditingController reps;
  final TextEditingController weight;

  int get setCount => (parseTypedInt(sets.text) ?? 0).clamp(0, 99);
  int get repCount => (parseTypedInt(reps.text) ?? 0).clamp(0, 999);

  double? get weightKg {
    final kg = parseTypedDouble(weight.text);
    return kg == null || kg <= 0 ? null : kg;
  }

  /// A blank field is "not filled in", saved as nothing rather than invented.
  ExerciseEntry toEntry() => ExerciseEntry(
        name: name,
        exerciseId: exerciseId,
        sets: setCount,
        reps: repCount,
        weightKg: weightKg,
      );

  void dispose() {
    sets.dispose();
    reps.dispose();
    weight.dispose();
  }

  /// `60.0` → `60`, `22.5` → `22.5`.
  static String _trimmed(double value) {
    final text = value.toStringAsFixed(2);
    return text
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }
}

/// The log itself: a card per exercise, with its sets, reps and load typed in
/// place, dragged to reorder.
class _ExerciseCards extends StatelessWidget {
  const _ExerciseCards({
    required this.rows,
    required this.onAdd,
    required this.onRemove,
    required this.onReorder,
    required this.onChanged,
  });

  final List<_LogRow> rows;
  final VoidCallback? onAdd;
  final ValueChanged<int>? onRemove;
  final void Function(int from, int to) onReorder;
  final VoidCallback onChanged;

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
              if (rows.isNotEmpty)
                Text(
                  '${rows.length}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: palette.muted,
                  ),
                ),
            ],
          ),
        ),
        if (rows.isEmpty)
          _EmptyTable(onAdd: onAdd)
        else ...[
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorderItem: onReorder,
            children: [
              for (var i = 0; i < rows.length; i++)
                Padding(
                  key: ValueKey(rows[i].id),
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: _ExerciseCard(
                    row: rows[i],
                    index: i,
                    onRemove: onRemove == null ? null : () => onRemove!(i),
                    onChanged: onChanged,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          _AddExerciseButton(onAdd: onAdd),
        ],
      ],
    );
  }
}

class _ExerciseCard extends StatelessWidget {
  const _ExerciseCard({
    required this.row,
    required this.index,
    required this.onRemove,
    required this.onChanged,
  });

  final _LogRow row;
  final int index;
  final VoidCallback? onRemove;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    Widget number(
      String label,
      TextEditingController controller, {
      bool decimal = false,
    }) {
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 4),
              child: Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  color: palette.muted,
                ),
              ),
            ),
            TextField(
              controller: controller,
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
                hintText: '—',
                hintStyle: TextStyle(color: palette.muted),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
              onChanged: (_) => onChanged(),
            ),
          ],
        ),
      );
    }

    return GlassWell(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      child: Column(
        children: [
          Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(Icons.drag_handle_rounded, color: palette.muted),
                ),
              ),
              Expanded(
                child: Text(
                  row.name,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: palette.brandText,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Remove ${row.name}',
                icon: Icon(Icons.close_rounded, color: palette.muted),
                onPressed: onRemove,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                number('Sets', row.sets),
                const SizedBox(width: 12),
                number('Reps', row.reps),
                const SizedBox(width: 12),
                number('Weight (kg)', row.weight, decimal: true),
              ],
            ),
          ),
        ],
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
              'Pick the lifts you did from the library, with the load on '
              'each. Volume adds itself up.',
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
