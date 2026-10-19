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
import '../../auth/domain/body_metrics.dart';
import '../application/routine_actions.dart';
import '../application/workout_library_providers.dart';
import '../data/workout_preferences_store.dart';
import '../domain/exercise_library.dart';
import '../domain/routine.dart';
import '../domain/workout_models.dart';
import 'exercise_picker_sheet.dart';
import 'routine_sheets.dart';
import 'workout_tool_sheets.dart';

/// Builds or edits a routine: the plan, not the workout.
///
/// The live session's card in "target mode" — no tick, no RPE, no PREVIOUS —
/// because what is typed here is what a set aims for, and it shows as the
/// hint in that set's row every time the routine is started.
///
/// [routineId] opens a saved routine; [draft] opens an unsaved one, which is
/// how "Save as routine" from a past workout arrives. Neither is a new one.
class RoutineBuilderScreen extends ConsumerStatefulWidget {
  const RoutineBuilderScreen({this.routineId, this.draft, super.key});

  final String? routineId;
  final Routine? draft;

  @override
  ConsumerState<RoutineBuilderScreen> createState() =>
      _RoutineBuilderScreenState();
}

class _RoutineBuilderScreenState extends ConsumerState<RoutineBuilderScreen> {
  final _name = TextEditingController();
  final _notes = TextEditingController();
  final List<_EditExercise> _exercises = [];
  int _nextKey = 0;

  /// The routine being edited, once loaded. Null for a new or draft one.
  Routine? _original;
  String? _folder;
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    Routine? routine = widget.draft;
    final id = widget.routineId;
    if (id != null && id.isNotEmpty) {
      try {
        final all = await ref.read(routinesProvider.future);
        routine = all.where((r) => r.id == id).firstOrNull;
      } catch (_) {
        routine = null;
      }
      if (routine == null && mounted) {
        setState(() {
          _loading = false;
          _error = 'This routine could not be found.';
        });
        return;
      }
      _original = routine;
    }
    if (!mounted) return;
    setState(() {
      if (routine != null) {
        _name.text = routine.name;
        _notes.text = routine.notes;
        _folder = routine.folder;
        _exercises.addAll(routine.exercises.map(_fromRoutine));
      }
      _loading = false;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    for (final e in _exercises) {
      e.dispose();
    }
    super.dispose();
  }

  _Units get _units => _Units(
        imperial: ref.read(bodyMetricsProvider).valueOrNull?.units ==
            MeasurementUnits.imperial,
      );

  _EditExercise _fromRoutine(RoutineExercise e) {
    final type = e.trackingType ?? _typeFor(e.exerciseId);
    final range = e.sets.any((s) => s.target.repsMax != null);
    return _EditExercise(
      key: _nextKey++,
      name: e.name,
      exerciseId: e.exerciseId,
      trackingType: type,
      supersetGroup: e.supersetGroup,
      restSeconds: e.restSeconds,
      notes: e.notes,
      useRange: range,
      sets: [
        for (final s in e.sets)
          _EditSet.fromTarget(type, s.type, s.target, _units),
      ],
    );
  }

  TrackingType _typeFor(String? exerciseId) => ExerciseLibrary.trackingTypeFor(
        exerciseId,
        custom: ref.read(customExercisesProvider).valueOrNull ?? const [],
      );

  void _changed() => setState(() => _dirty = true);

  Future<void> _addExercises() async {
    final picked = await showExercisesPicker(context);
    if (picked == null || !mounted) return;
    final group = picked.asSuperset && picked.exercises.length > 1
        ? 'g${_nextKey++}'
        : null;
    setState(() {
      for (final p in picked.exercises) {
        _exercises.add(_EditExercise(
          key: _nextKey++,
          name: p.name,
          exerciseId: p.id,
          trackingType: _typeFor(p.id),
          supersetGroup: group,
          sets: [_EditSet(), _EditSet(), _EditSet()],
        ));
      }
      _dirty = true;
      _error = null;
    });
  }

  Future<void> _onMenu(_EditExercise e, _ExerciseAction action) async {
    final index = _exercises.indexOf(e);
    switch (action) {
      case _ExerciseAction.rest:
        final picked = await showRestOverridePicker(
          context,
          exerciseName: e.name,
          current: e.restSeconds,
          defaultSeconds: 90,
          choices: WorkoutPreferences.restChoices,
        );
        if (picked == null) return;
        e.restSeconds = picked.seconds;
        _changed();
      case _ExerciseAction.repRange:
        e.useRange = !e.useRange;
        _changed();
      case _ExerciseAction.supersetNext:
        if (index + 1 >= _exercises.length) return;
        final next = _exercises[index + 1];
        final group = e.supersetGroup ?? next.supersetGroup ?? 'g${_nextKey++}';
        e.supersetGroup = group;
        next.supersetGroup = group;
        _changed();
      case _ExerciseAction.unlink:
        final group = e.supersetGroup;
        e.supersetGroup = null;
        // A superset of one is just an exercise.
        final left = _exercises.where((x) => x.supersetGroup == group);
        if (left.length == 1) left.single.supersetGroup = null;
        _changed();
      case _ExerciseAction.replace:
        final picked = await showExercisePicker(context);
        if (picked == null || !mounted) return;
        setState(() {
          final replacement = _EditExercise(
            key: _nextKey++,
            name: picked.name,
            exerciseId: picked.id,
            trackingType: _typeFor(picked.id),
            supersetGroup: e.supersetGroup,
            restSeconds: e.restSeconds,
            notes: e.notes.text,
            useRange: e.useRange,
            // The set count and types carry over; the numbers do not.
            sets: [for (final s in e.sets) _EditSet(type: s.type)],
          );
          _exercises[index] = replacement;
          e.dispose();
          _dirty = true;
        });
      case _ExerciseAction.moveUp:
        if (index <= 0) return;
        setState(() {
          _exercises.insert(index - 1, _exercises.removeAt(index));
          _dirty = true;
        });
      case _ExerciseAction.moveDown:
        if (index + 1 >= _exercises.length) return;
        setState(() {
          _exercises.insert(index + 1, _exercises.removeAt(index));
          _dirty = true;
        });
      case _ExerciseAction.remove:
        setState(() {
          _exercises.removeAt(index).dispose();
          final group = e.supersetGroup;
          final left = _exercises.where((x) => x.supersetGroup == group);
          if (group != null && left.length == 1) {
            left.single.supersetGroup = null;
          }
          _dirty = true;
        });
    }
  }

  Future<void> _pickFolder() async {
    final all = ref.read(routinesProvider).valueOrNull ?? const <Routine>[];
    final choice = await showRoutineFolderPicker(
      context,
      folders: {for (final r in all) r.folderLabel}.toList()..sort(),
      current: _folder,
    );
    if (choice == null || !mounted) return;
    setState(() {
      _folder = choice.folder;
      _dirty = true;
    });
  }

  Routine _build() {
    final units = _units;
    final base = _original ??
        Routine(
          id: '',
          name: '',
          // A new routine goes to the end of its folder.
          position: _nextPosition(
            ref.read(routinesProvider).valueOrNull ?? const [],
            _folder,
          ),
        );
    return base.copyWith(
      name: _name.text.trim(),
      folder: _folder,
      clearFolder: _folder == null,
      notes: _notes.text.trim(),
      exercises: [
        for (final e in _exercises)
          RoutineExercise(
            name: e.name,
            exerciseId: e.exerciseId,
            trackingType: e.trackingType,
            supersetGroup: e.supersetGroup,
            restSeconds: e.restSeconds,
            notes: e.notes.text.trim(),
            sets: [
              for (final s in e.sets)
                RoutineSet(
                  type: s.type,
                  target: s.toTarget(e.trackingType, e.useRange, units),
                ),
            ],
          ),
      ],
    );
  }

  static int _nextPosition(List<Routine> all, String? folder) {
    final inFolder = all.where((r) => r.folder == folder);
    return inFolder.isEmpty
        ? 0
        : inFolder.map((r) => r.position).reduce((a, b) => a > b ? a : b) + 1;
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Give the routine a name.');
      return;
    }
    if (_exercises.isEmpty) {
      setState(() => _error = 'Add at least one exercise.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await ref.read(routineActionsProvider).save(_build());
      if (!mounted) return;
      showQuickToast(context, 'Saved ${saved.name}.', tone: ToastTone.success);
      context.pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save the routine. Try again.';
      });
    }
  }

  Future<bool> _confirmLeave() async {
    if (!_dirty || _saving) return true;
    return confirmDestructiveAction(
      context,
      title: 'Leave without saving?',
      message: 'The changes to this routine will be lost.',
      confirmLabel: 'Discard changes',
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    // Watched, so a units change in Settings redraws the column labels.
    ref.watch(bodyMetricsProvider);
    final units = _units;
    final letters = <String, String>{};
    for (final e in _exercises) {
      final group = e.supersetGroup;
      if (group != null &&
          _exercises.where((x) => x.supersetGroup == group).length > 1) {
        letters.putIfAbsent(
            group, () => String.fromCharCode(65 + letters.length));
      }
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && context.mounted) context.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_original == null ? 'New routine' : 'Edit routine'),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
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
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      onChanged: (_) => _dirty = true,
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: 'Routine name, e.g. Push Day',
                        hintStyle: TextStyle(color: palette.muted),
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ActionChip(
                      avatar: Icon(Icons.folder_outlined,
                          size: 18, color: palette.muted),
                      label: Text(_folder ?? Routine.defaultFolder),
                      onPressed: _pickFolder,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  GlassWell(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      controller: _notes,
                      minLines: 1,
                      maxLines: 4,
                      onChanged: (_) => _dirty = true,
                      style: TextStyle(color: palette.text, fontSize: 14),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: 'Notes for the whole routine (optional)',
                        hintStyle: TextStyle(color: palette.muted),
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  for (var i = 0; i < _exercises.length; i++)
                    Padding(
                      key: ValueKey(_exercises[i].key),
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: _ExerciseEditor(
                        exercise: _exercises[i],
                        units: units,
                        supersetLabel: letters[_exercises[i].supersetGroup],
                        isFirst: i == 0,
                        isLast: i == _exercises.length - 1,
                        onChanged: _changed,
                        onMenu: (action) => _onMenu(_exercises[i], action),
                      ),
                    ),
                  OutlinedButton.icon(
                    onPressed: _addExercises,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add exercises'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      foregroundColor: palette.brandText,
                      side: BorderSide(color: palette.brandSoftStroke),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                  ),
                ],
              ),
        bottomNavigationBar: _loading
            ? null
            : KeyboardSafeBottomBar(
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
                            style:
                                TextStyle(color: palette.danger, fontSize: 13),
                          ),
                        ),
                      PrimaryButton(
                        icon: Icons.check_rounded,
                        label: _saving ? 'Saving…' : 'Save routine',
                        onPressed: _saving ? null : _save,
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

enum _ExerciseAction {
  rest,
  repRange,
  supersetNext,
  unlink,
  replace,
  moveUp,
  moveDown,
  remove,
}

class _Units {
  const _Units({this.imperial = false});

  static const _kgPerLb = 0.45359237;

  final bool imperial;

  String get label => imperial ? 'LB' : 'KG';

  double toDisplay(double kg) => imperial ? kg / _kgPerLb : kg;

  double toKg(double value) => imperial ? value * _kgPerLb : value;
}

/// One exercise being planned. Mutable, with its own controllers, so what is
/// typed survives the card being rebuilt or moved.
class _EditExercise {
  _EditExercise({
    required this.key,
    required this.name,
    required this.trackingType,
    required this.sets,
    this.exerciseId,
    this.supersetGroup,
    this.restSeconds,
    String notes = '',
    this.useRange = false,
  }) : notes = TextEditingController(text: notes);

  final int key;
  final String name;
  final String? exerciseId;
  final TrackingType trackingType;
  String? supersetGroup;
  int? restSeconds;
  final TextEditingController notes;

  /// Reps as a range ("8–12") rather than one number.
  bool useRange;

  final List<_EditSet> sets;

  void dispose() {
    notes.dispose();
    for (final s in sets) {
      s.dispose();
    }
  }
}

/// One planned set: its type, and up to three typed fields whose meaning
/// depends on the exercise's tracking type — see [_columnsFor].
class _EditSet {
  _EditSet(
      {this.type = SetType.normal, String a = '', String b = '', String c = ''})
      : a = TextEditingController(text: a),
        b = TextEditingController(text: b),
        c = TextEditingController(text: c);

  /// The typed fields for [t] under [tracking] — the exact inverse of
  /// [toTarget], so opening a routine and saving it again changes nothing.
  factory _EditSet.fromTarget(
    TrackingType tracking,
    SetType type,
    SetTarget t,
    _Units units,
  ) {
    String n(num? v) {
      if (v == null || v <= 0) return '';
      final d = v.toDouble();
      if (d == d.roundToDouble()) return '${d.round()}';
      return d
          .toStringAsFixed(2)
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'.$'), '');
    }

    String time(int? s) {
      if (s == null || s <= 0) return '';
      return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
    }

    final kg = n(t.weightKg == null ? null : units.toDisplay(t.weightKg!));
    final reps = n(t.repsMin ?? t.reps);
    final top = n(t.repsMax);
    return switch (tracking) {
      TrackingType.weightReps ||
      TrackingType.weightedBodyweight ||
      TrackingType.assistedBodyweight =>
        _EditSet(type: type, a: kg, b: reps, c: top),
      TrackingType.bodyweightReps => _EditSet(type: type, b: reps, c: top),
      TrackingType.duration => _EditSet(type: type, a: time(t.durationSeconds)),
      TrackingType.weightDuration =>
        _EditSet(type: type, a: kg, b: time(t.durationSeconds)),
      TrackingType.cardio => _EditSet(
          type: type,
          a: n(t.durationSeconds == null ? null : t.durationSeconds! / 60),
          b: n(t.distanceKm),
        ),
    };
  }

  SetType type;
  final TextEditingController a;
  final TextEditingController b;
  final TextEditingController c;

  SetTarget toTarget(TrackingType type, bool range, _Units units) {
    double? kg(String text) {
      final v = parseTypedDouble(text);
      return v == null || v <= 0 ? null : units.toKg(v);
    }

    int? whole(String text) {
      final v = parseTypedInt(text);
      return v == null || v <= 0 ? null : v;
    }

    int? seconds(String text) {
      final parts = text.trim().split(':');
      if (text.trim().isEmpty || parts.length > 3) return null;
      var total = 0;
      for (final p in parts) {
        final n = int.tryParse(p.isEmpty ? '0' : p);
        if (n == null) return null;
        total = total * 60 + n;
      }
      return total > 0 ? total : null;
    }

    SetTarget reps(double? weightKg) {
      final low = whole(b.text);
      final high = whole(c.text);
      if (range && high != null && low != null && high > low) {
        return SetTarget(weightKg: weightKg, repsMin: low, repsMax: high);
      }
      return SetTarget(weightKg: weightKg, reps: low);
    }

    return switch (type) {
      TrackingType.weightReps ||
      TrackingType.weightedBodyweight ||
      TrackingType.assistedBodyweight =>
        reps(kg(a.text)),
      TrackingType.bodyweightReps => reps(null),
      TrackingType.duration => SetTarget(durationSeconds: seconds(a.text)),
      TrackingType.weightDuration =>
        SetTarget(weightKg: kg(a.text), durationSeconds: seconds(b.text)),
      TrackingType.cardio => SetTarget(
          durationSeconds: switch (parseTypedDouble(a.text)) {
            final m? when m > 0 => (m * 60).round(),
            _ => null,
          },
          distanceKm: switch (parseTypedDouble(b.text)) {
            final km? when km > 0 => km,
            _ => null,
          },
        ),
    };
  }

  void dispose() {
    a.dispose();
    b.dispose();
    c.dispose();
  }
}

/// Which typed fields a tracking type plans with, in order: (field, label).
List<(_Field, String)> _columnsFor(
  TrackingType type, {
  required bool range,
  required _Units units,
}) {
  final repsCols = range
      ? [(_Field.b, 'MIN REPS'), (_Field.c, 'MAX REPS')]
      : [(_Field.b, 'REPS')];
  return switch (type) {
    TrackingType.weightReps => [(_Field.a, units.label), ...repsCols],
    TrackingType.weightedBodyweight => [
        (_Field.a, '+${units.label}'),
        ...repsCols
      ],
    TrackingType.assistedBodyweight => [
        (_Field.a, '−${units.label}'),
        ...repsCols
      ],
    TrackingType.bodyweightReps => repsCols,
    TrackingType.duration => [(_Field.a, 'TIME')],
    TrackingType.weightDuration => [
        (_Field.a, units.label),
        (_Field.b, 'TIME')
      ],
    TrackingType.cardio => [(_Field.a, 'MIN'), (_Field.b, 'KM')],
  };
}

enum _Field { a, b, c }

class _ExerciseEditor extends StatelessWidget {
  const _ExerciseEditor({
    required this.exercise,
    required this.units,
    required this.supersetLabel,
    required this.isFirst,
    required this.isLast,
    required this.onChanged,
    required this.onMenu,
  });

  final _EditExercise exercise;
  final _Units units;
  final String? supersetLabel;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onChanged;
  final ValueChanged<_ExerciseAction> onMenu;

  bool get _hasReps => switch (exercise.trackingType) {
        TrackingType.duration ||
        TrackingType.weightDuration ||
        TrackingType.cardio =>
          false,
        _ => true,
      };

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final columns = _columnsFor(
      exercise.trackingType,
      range: exercise.useRange && _hasReps,
      units: units,
    );
    final rest = exercise.restSeconds;
    final inSuperset = supersetLabel != null;

    TextStyle head() => TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          color: palette.muted,
        );

    var working = 0;
    final labels = [
      for (final s in exercise.sets)
        switch (s.type) {
          SetType.warmup => 'W',
          SetType.dropset => 'D',
          SetType.failure => 'F',
          SetType.normal => '${++working}',
        },
    ];

    final card = GlassWell(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (inSuperset || rest != null)
            Wrap(
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
                onSelected: onMenu,
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: _ExerciseAction.rest,
                    child: Text(rest == null
                        ? 'Rest timer'
                        : 'Rest timer (${formatRest(rest)})'),
                  ),
                  if (_hasReps)
                    PopupMenuItem(
                      value: _ExerciseAction.repRange,
                      child: Text(exercise.useRange
                          ? 'Use a single rep target'
                          : 'Use a rep range'),
                    ),
                  if (!isLast)
                    const PopupMenuItem(
                      value: _ExerciseAction.supersetNext,
                      child: Text('Superset with the next'),
                    ),
                  if (inSuperset)
                    const PopupMenuItem(
                      value: _ExerciseAction.unlink,
                      child: Text('Remove from superset'),
                    ),
                  const PopupMenuItem(
                    value: _ExerciseAction.replace,
                    child: Text('Replace exercise'),
                  ),
                  if (!isFirst)
                    const PopupMenuItem(
                      value: _ExerciseAction.moveUp,
                      child: Text('Move up'),
                    ),
                  if (!isLast)
                    const PopupMenuItem(
                      value: _ExerciseAction.moveDown,
                      child: Text('Move down'),
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
            padding: const EdgeInsets.only(right: 8, bottom: 6),
            child: TextField(
              controller: exercise.notes,
              minLines: 1,
              maxLines: 3,
              onChanged: (_) => onChanged(),
              style: TextStyle(color: palette.text, fontSize: 13.5),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Standing note, shown every session',
                hintStyle: TextStyle(color: palette.muted, fontSize: 13.5),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8, bottom: 4),
            child: Row(
              children: [
                SizedBox(width: 44, child: Text('SET', style: head())),
                for (final (_, label) in columns) ...[
                  Expanded(child: Center(child: Text(label, style: head()))),
                  const SizedBox(width: 8),
                ],
                const SizedBox(width: 36),
              ],
            ),
          ),
          for (var i = 0; i < exercise.sets.length; i++)
            _SetEditorRow(
              key: ObjectKey(exercise.sets[i]),
              set: exercise.sets[i],
              label: labels[i],
              columns: columns,
              onChanged: onChanged,
              onType: () async {
                final choice = await showSetTypeSheet(
                  context,
                  current: exercise.sets[i].type,
                );
                switch (choice) {
                  case SetTypePicked(:final type):
                    exercise.sets[i].type = type;
                    onChanged();
                  case SetRemoved():
                    exercise.sets.removeAt(i).dispose();
                    onChanged();
                  case null:
                    break;
                }
              },
              onRemove: exercise.sets.length <= 1
                  ? null
                  : () {
                      exercise.sets.removeAt(i).dispose();
                      onChanged();
                    },
            ),
          Center(
            child: TextButton.icon(
              onPressed: () {
                final last = exercise.sets.isEmpty ? null : exercise.sets.last;
                // The next set is usually the last one again.
                exercise.sets.add(_EditSet(
                  type: last == null || last.type == SetType.warmup
                      ? SetType.normal
                      : last.type,
                  a: last?.a.text ?? '',
                  b: last?.b.text ?? '',
                  c: last?.c.text ?? '',
                ));
                onChanged();
              },
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add set'),
              style: TextButton.styleFrom(foregroundColor: palette.brandText),
            ),
          ),
        ],
      ),
    );

    if (!inSuperset) return card;
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

class _SetEditorRow extends StatelessWidget {
  const _SetEditorRow({
    required this.set,
    required this.label,
    required this.columns,
    required this.onChanged,
    required this.onType,
    required this.onRemove,
    super.key,
  });

  final _EditSet set;
  final String label;
  final List<(_Field, String)> columns;
  final VoidCallback onChanged;
  final VoidCallback onType;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    TextEditingController controller(_Field f) => switch (f) {
          _Field.a => set.a,
          _Field.b => set.b,
          _Field.c => set.c,
        };

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: TextButton(
              onPressed: onType,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(44, 44),
                foregroundColor: switch (set.type) {
                  SetType.normal => palette.text,
                  SetType.warmup => palette.muted,
                  _ => palette.brandText,
                },
              ),
              child: Text(
                label,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
          ),
          for (final (field, name) in columns) ...[
            Expanded(
              child: TextField(
                controller: controller(field),
                textAlign: TextAlign.center,
                keyboardType: name == 'TIME'
                    ? TextInputType.datetime
                    : const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    name == 'TIME' ? RegExp(r'[0-9:]') : RegExp(r'[0-9.,]'),
                  ),
                ],
                onChanged: (_) => onChanged(),
                style: TextStyle(
                  color: palette.text,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: name == 'TIME' ? '0:00' : '—',
                  hintStyle: TextStyle(color: palette.muted),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          SizedBox(
            width: 36,
            child: IconButton(
              tooltip: 'Remove set',
              padding: EdgeInsets.zero,
              icon: Icon(Icons.close_rounded, size: 18, color: palette.muted),
              onPressed: onRemove,
            ),
          ),
        ],
      ),
    );
  }
}
