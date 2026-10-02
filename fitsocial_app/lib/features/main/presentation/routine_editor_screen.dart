import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/input/typed_number.dart';
import '../../../shared/widgets/glass_well.dart';
import '../../../shared/widgets/keyboard_safe_bottom_bar.dart';
import '../../../shared/widgets/primary_button.dart';
import '../application/workout_library_providers.dart';
import '../application/workout_preferences.dart';
import '../data/content_repository.dart';
import '../data/workout_preferences_store.dart';
import '../domain/workout_models.dart';
import 'exercise_picker_sheet.dart';
import 'workout_tool_sheets.dart';

/// Create or edit a routine: a name, and an ordered list of exercises with a
/// target number of sets, reps and load for each.
///
/// Weight is in kilograms, like the rest of the workout screens.
class RoutineEditorScreen extends ConsumerStatefulWidget {
  const RoutineEditorScreen({this.initial, super.key});

  /// The routine being edited; null for a new one.
  final WorkoutRoutine? initial;

  @override
  ConsumerState<RoutineEditorScreen> createState() =>
      _RoutineEditorScreenState();
}

/// One exercise being edited. Holds its own controllers so the numbers typed
/// into it survive a reorder.
class _Row {
  _Row(this.id, this.source)
      : restSeconds = source.restSeconds,
        supersetGroup = source.supersetGroup,
        sets = TextEditingController(text: '${source.targetSets}'),
        reps = TextEditingController(text: '${source.targetReps}'),
        weight = TextEditingController(
          text: source.targetWeightKg == null
              ? ''
              : _plain(source.targetWeightKg!),
        );

  /// Identifies the row for reordering; unrelated to the exercise.
  final int id;

  /// The exercise as it was picked or loaded: its name and library id.
  final RoutineExercise source;

  /// This exercise's own rest; null for the user's default.
  int? restSeconds;

  /// Shared with the neighbouring exercises it is supersetted with.
  String? supersetGroup;
  final TextEditingController sets;
  final TextEditingController reps;
  final TextEditingController weight;

  void dispose() {
    sets.dispose();
    reps.dispose();
    weight.dispose();
  }

  RoutineExercise toExercise() {
    final targetSets = (parseTypedInt(sets.text) ?? 3).clamp(1, 20);
    final targetReps = (parseTypedInt(reps.text) ?? 10).clamp(1, 999);
    final kg = parseTypedDouble(weight.text);
    return RoutineExercise(
      exerciseId: source.exerciseId,
      name: source.name,
      targetSets: targetSets,
      targetReps: targetReps,
      targetWeightKg: kg == null || kg <= 0 ? null : kg,
      restSeconds: restSeconds,
      supersetGroup: supersetGroup,
    );
  }

  static String _plain(double kg) =>
      kg == kg.roundToDouble() ? '${kg.round()}' : '$kg';
}

class _RoutineEditorScreenState extends ConsumerState<RoutineEditorScreen> {
  late final TextEditingController _name;
  final List<_Row> _rows = [];
  int _nextId = 0;
  bool _saving = false;
  String? _error;

  bool get _isEditing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initial?.name ?? '');
    for (final exercise in widget.initial?.exercises ?? const []) {
      _rows.add(_Row(_nextId++, exercise));
    }
  }

  @override
  void dispose() {
    _name.dispose();
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  Future<void> _addExercise() async {
    final picked = await showExercisePicker(context);
    if (picked == null || !mounted) return;
    setState(() {
      _rows.add(_Row(
        _nextId++,
        RoutineExercise(name: picked.name, exerciseId: picked.id),
      ));
      _error = null;
    });
  }

  void _removeAt(int index) {
    setState(() {
      _rows.removeAt(index).dispose();
      _tidySupersets();
    });
  }

  /// [to] is already the item's final position: `onReorderItem`, unlike the
  /// deprecated `onReorder`, accounts for the item being lifted out.
  void _reorder(int from, int to) {
    setState(() {
      _rows.insert(to, _rows.removeAt(from));
      _tidySupersets();
    });
  }

  String _newGroup() => 's${DateTime.now().microsecondsSinceEpoch}_${_nextId++}';

  /// A superset here is a run of neighbouring exercises. Whatever a reorder or
  /// a removal has left on its own goes back to being a plain exercise, and a
  /// run split in two becomes two supersets.
  void _tidySupersets() {
    final seen = <String>{};
    for (var i = 0; i < _rows.length; i++) {
      final group = _rows[i].supersetGroup;
      if (group == null) continue;
      final continues = i > 0 && _rows[i - 1].supersetGroup == group;
      if (!continues && !seen.add(group)) {
        final fresh = _newGroup();
        for (var j = i;
            j < _rows.length && _rows[j].supersetGroup == group;
            j++) {
          _rows[j].supersetGroup = fresh;
        }
        seen.add(fresh);
      }
    }
    for (var i = 0; i < _rows.length; i++) {
      final group = _rows[i].supersetGroup;
      if (group == null) continue;
      final before = i > 0 && _rows[i - 1].supersetGroup == group;
      final after =
          i + 1 < _rows.length && _rows[i + 1].supersetGroup == group;
      if (!before && !after) _rows[i].supersetGroup = null;
    }
  }

  /// Ties the exercise at [index] to the one after it, merging any superset
  /// either is already in.
  void _linkWithNext(int index) {
    if (index + 1 >= _rows.length) return;
    setState(() {
      final group = _rows[index].supersetGroup ?? _newGroup();
      final old = _rows[index + 1].supersetGroup;
      for (final row in _rows) {
        if (old != null && row.supersetGroup == old) row.supersetGroup = group;
      }
      _rows[index].supersetGroup = group;
      _rows[index + 1].supersetGroup = group;
    });
  }

  /// Unties the exercise at [index] from the one after it.
  void _unlinkFromNext(int index) {
    if (index + 1 >= _rows.length) return;
    setState(() {
      final group = _rows[index].supersetGroup;
      final fresh = _newGroup();
      for (var j = index + 1;
          j < _rows.length && _rows[j].supersetGroup == group;
          j++) {
        _rows[j].supersetGroup = fresh;
      }
      _tidySupersets();
    });
  }

  Future<void> _pickRest(_Row row) async {
    final picked = await showRestOverridePicker(
      context,
      exerciseName: row.source.name,
      current: row.restSeconds,
      defaultSeconds: ref.read(workoutPreferencesProvider).restSeconds,
      choices: WorkoutPreferences.restChoices,
    );
    if (picked == null || !mounted) return;
    setState(() => row.restSeconds = picked.seconds);
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give the routine a name.');
      return;
    }
    if (_rows.isEmpty) {
      setState(() => _error = 'Add at least one exercise.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(contentRepositoryProvider).saveRoutine(
            WorkoutRoutine(
              id: widget.initial?.id ?? '',
              name: name,
              exercises: [for (final row in _rows) row.toExercise()],
            ),
          );
      ref.invalidate(routinesProvider);
      if (mounted) context.pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save the routine. $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit routine' : 'New routine')),
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
              controller: _name,
              textCapitalization: TextCapitalization.words,
              style: TextStyle(
                color: palette.text,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: 'Routine name, e.g. Push day',
                hintStyle: TextStyle(color: palette.muted),
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorderItem: _reorder,
            children: [
              for (var i = 0; i < _rows.length; i++)
                Padding(
                  key: ValueKey(_rows[i].id),
                  // The superset link between two cards is their spacing.
                  padding: EdgeInsets.only(
                    bottom: i + 1 < _rows.length ? 0 : AppSpacing.sm,
                  ),
                  child: Column(
                    children: [
                      _RowCard(
                        row: _rows[i],
                        index: i,
                        onRemove: () => _removeAt(i),
                        onPickRest: () => _pickRest(_rows[i]),
                      ),
                      if (i + 1 < _rows.length)
                        _SupersetLink(
                          linked: _rows[i].supersetGroup != null &&
                              _rows[i].supersetGroup ==
                                  _rows[i + 1].supersetGroup,
                          onLink: () => _linkWithNext(i),
                          onUnlink: () => _unlinkFromNext(i),
                        ),
                    ],
                  ),
                ),
            ],
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
        ],
      ),
      bottomNavigationBar: KeyboardSafeBottomBar(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
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
              PrimaryButton(
                icon: Icons.check_rounded,
                label: _saving ? 'Saving…' : 'Save routine',
                onPressed: _saving ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The joint between two routine exercises: a link that ties them into a
/// superset, or shows that they are and unties them.
class _SupersetLink extends StatelessWidget {
  const _SupersetLink({
    required this.linked,
    required this.onLink,
    required this.onUnlink,
  });

  final bool linked;
  final VoidCallback onLink;
  final VoidCallback onUnlink;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Center(
      child: TextButton.icon(
        onPressed: linked ? onUnlink : onLink,
        icon: Icon(
          linked ? Icons.link_rounded : Icons.add_link_rounded,
          size: 18,
        ),
        label: Text(linked ? 'Superset (tap to unlink)' : 'Superset'),
        style: TextButton.styleFrom(
          foregroundColor: linked ? palette.brandText : palette.muted,
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }
}

class _RowCard extends StatelessWidget {
  const _RowCard({
    required this.row,
    required this.index,
    required this.onRemove,
    required this.onPickRest,
  });

  final _Row row;
  final int index;
  final VoidCallback onRemove;
  final VoidCallback onPickRest;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    Widget number(String label, TextEditingController c, {bool decimal = false}) {
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
                hintText: '—',
                hintStyle: TextStyle(color: palette.muted),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
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
                  row.source.name,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: palette.brandText,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Remove ${row.source.name}',
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
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onPickRest,
              icon: const Icon(Icons.timer_outlined, size: 18),
              label: Text(
                row.restSeconds == null
                    ? 'Rest: default'
                    : 'Rest: ${formatRest(row.restSeconds!)}',
              ),
              style: TextButton.styleFrom(
                foregroundColor: palette.muted,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
