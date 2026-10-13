import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_palette.dart';
import '../../../shared/widgets/glass_well.dart';
import '../../../shared/widgets/liquid_glass.dart';
import '../application/content_providers.dart';
import '../application/workout_library_providers.dart';
import '../domain/workout_math.dart';
import '../../../shared/widgets/primary_button.dart';
import '../domain/exercise_library.dart';
import '../domain/workout_models.dart';
import 'custom_exercise_sheet.dart';

/// What the picker returns: a library entry, or a name the user typed.
class PickedExercise {
  const PickedExercise({required this.name, this.id, this.equipment});

  final String name;

  /// Null for a typed name that is not in the library.
  final String? id;

  /// What it is done on, where known. `cardio` for a typed name added while
  /// the picker was showing cardio only — "Concept2" typed there is a machine
  /// to log a time on, not a lift.
  final String? equipment;

  bool get isCardio => equipment == 'cardio';
}

/// Opens the exercise picker.
///
/// Searches the bundled library and the user's own exercises together, and can
/// save a typed name as a new custom exercise. Returns null on dismissal.
///
/// [cardioOnly] opens it showing cardio machines and activities alone, for
/// the way in from the run screen; the filter can be switched off in the sheet.
///
/// [enhanced] adds the v2 logger's Recent section and muscle and equipment
/// filters.
Future<PickedExercise?> showExercisePicker(
  BuildContext context, {
  bool cardioOnly = false,
  bool enhanced = false,
}) async {
  final picked = await showModalBottomSheet<PickedExercises>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    isScrollControlled: true,
    builder: (sheetContext) =>
        _ExercisePickerSheet(cardioOnly: cardioOnly, enhanced: enhanced),
  );
  return picked?.exercises.firstOrNull;
}

/// Several exercises picked at once, and whether to add them as a superset.
class PickedExercises {
  const PickedExercises(this.exercises, {this.asSuperset = false});

  final List<PickedExercise> exercises;
  final bool asSuperset;
}

/// The picker with Recent, filters and multi-select: tick several, then
/// "Add (n)" or "Add as superset". Null on dismissal.
Future<PickedExercises?> showExercisesPicker(BuildContext context) {
  return showModalBottomSheet<PickedExercises>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    isScrollControlled: true,
    builder: (sheetContext) =>
        const _ExercisePickerSheet(enhanced: true, multiSelect: true),
  );
}

class _ExercisePickerSheet extends ConsumerStatefulWidget {
  const _ExercisePickerSheet({
    this.cardioOnly = false,
    this.enhanced = false,
    this.multiSelect = false,
  });

  final bool cardioOnly;
  final bool enhanced;
  final bool multiSelect;

  @override
  ConsumerState<_ExercisePickerSheet> createState() =>
      _ExercisePickerSheetState();
}

class _ExercisePickerSheetState extends ConsumerState<_ExercisePickerSheet> {
  final _query = TextEditingController();

  /// Showing cardio alone. A chip at the top turns it on and off, so a rower
  /// or a stair climber is two taps away rather than a search for a word the
  /// user has to guess.
  late bool _cardioOnly = widget.cardioOnly;

  String? _muscle;
  String? _equipment;

  /// Ticked rows, in the order they were ticked, when picking several.
  final List<PickedExercise> _selected = [];

  void _pick(PickedExercise exercise) {
    if (!widget.multiSelect) {
      Navigator.of(context).pop(PickedExercises([exercise]));
      return;
    }
    setState(() {
      final at = _selected
          .indexWhere((p) => p.id == exercise.id && p.name == exercise.name);
      if (at >= 0) {
        _selected.removeAt(at);
      } else {
        _selected.add(exercise);
      }
    });
  }

  bool _isSelected(LibraryExercise e) => _selected.any((p) => p.id == e.id);

  /// A long list is the whole point of a library, but drawing every row of it
  /// into a sheet is not.
  static const _maxRows = 80;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _saveAsCustom(String name) async {
    final saved = await showCustomExerciseSheet(context, initialName: name);
    if (saved == null || !mounted) return;
    _query.clear();
    _pick(
      PickedExercise(
        name: saved.name,
        id: customExerciseId(saved.id),
        equipment: saved.equipment,
      ),
    );
  }

  /// The movements logged most recently, newest first, as library rows.
  List<LibraryExercise> _recent(List<LibraryExercise> pool) {
    final history = ref.watch(workoutHistoryItemsProvider).valueOrNull;
    if (history == null) return const [];
    final byId = {for (final e in pool) e.id: e};
    final out = <LibraryExercise>[];
    for (final workout in history) {
      for (final entry in workout.exercises) {
        final row = byId[exerciseKey(entry)];
        if (row != null && !out.contains(row)) out.add(row);
        if (out.length == 6) return out;
      }
    }
    return out;
  }

  Widget _row(LibraryExercise exercise) {
    final palette = context.palette;
    final selected = widget.multiSelect && _isSelected(exercise);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        exercise.name,
        style: TextStyle(
          color: palette.text,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        '${exercise.muscles.join(', ')} · ${exercise.equipment}'
        '${exercise.id.startsWith('custom-') ? ' · custom' : ''}',
        style: TextStyle(color: palette.muted),
      ),
      trailing: widget.multiSelect
          ? Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected ? palette.brand : palette.muted,
            )
          : null,
      selected: selected,
      onTap: () => _pick(
        PickedExercise(
          name: exercise.name,
          id: exercise.id,
          equipment: exercise.equipment,
        ),
      ),
    );
  }

  Widget _chips(
    List<String> values,
    String? current,
    ValueChanged<String?> onPick,
  ) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final v in values)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilterChip(
                label: Text(v),
                selected: current == v,
                showCheckmark: false,
                onSelected: (on) => setState(() => onPick(on ? v : null)),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final typed = _query.text.trim();
    // A failed or still-loading read costs the custom list and nothing else:
    // the library is bundled and has to work regardless.
    final custom = ref.watch(customExercisesProvider).valueOrNull ??
        const <CustomExercise>[];
    final extra = [
      for (final c in custom)
        LibraryExercise(
          id: customExerciseId(c.id),
          name: c.name,
          muscles: c.muscles,
          equipment: c.equipment,
        ),
    ];
    final results = ExerciseLibrary.search(typed, extra: extra)
        .where((e) => !_cardioOnly || e.equipment == 'cardio')
        .where((e) => _muscle == null || e.muscles.contains(_muscle))
        .where((e) => _equipment == null || e.equipment == _equipment)
        .toList();
    final filtering = typed.isNotEmpty ||
        _muscle != null ||
        _equipment != null ||
        _cardioOnly;
    final recent = widget.enhanced && !filtering
        ? _recent([...extra, ...ExerciseLibrary.all])
        : const <LibraryExercise>[];
    final shown = results.take(_maxRows).toList();
    final exactMatch =
        results.any((e) => e.name.toLowerCase() == typed.toLowerCase());
    final height = MediaQuery.sizeOf(context).height;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(12, 0, 12, 12 + keyboard),
      child: LiquidGlass(
        lens: true,
        borderRadius: BorderRadius.circular(28),
        child: Container(
          width: double.infinity,
          height: height * 0.78,
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: palette.stroke),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: palette.stroke,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _cardioOnly ? 'Add cardio' : 'Add exercise',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: palette.text,
                      ),
                    ),
                  ),
                  FilterChip(
                    label: const Text('Cardio machines'),
                    avatar: Icon(
                      Icons.directions_bike_rounded,
                      size: 16,
                      color: _cardioOnly ? palette.brandText : palette.muted,
                    ),
                    selected: _cardioOnly,
                    showCheckmark: false,
                    onSelected: (value) => setState(() => _cardioOnly = value),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              GlassWell(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _query,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    icon: Icon(Icons.search_rounded, color: palette.muted),
                    hintText: _cardioOnly
                        ? 'Search, e.g. rower or stairs'
                        : 'Search, e.g. incline dumbbell',
                    hintStyle: TextStyle(color: palette.muted),
                    contentPadding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              if (widget.enhanced) ...[
                const SizedBox(height: 8),
                _chips(
                  [
                    for (final m in ExerciseLibrary.muscleGroups)
                      if (m != 'cardio') m,
                  ],
                  _muscle,
                  (v) => _muscle = v,
                ),
                _chips(
                  [
                    for (final e in ExerciseLibrary.equipmentTypes)
                      if (e != 'cardio') e,
                  ],
                  _equipment,
                  (v) => _equipment = v,
                ),
              ],
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    if (recent.isNotEmpty) ...[
                      _sectionLabel('Recent'),
                      for (final exercise in recent) _row(exercise),
                      _sectionLabel('All exercises'),
                    ],
                    // Offered first, so a name that is not in the library is
                    // never a dead end.
                    if (typed.isNotEmpty && !exactMatch)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.add_circle_outline_rounded,
                            color: palette.brand),
                        title: Text(
                          'Add "$typed"',
                          style: TextStyle(
                            color: palette.text,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: Text(
                          'Use your own name for it',
                          style: TextStyle(color: palette.muted),
                        ),
                        onTap: () {
                          _query.clear();
                          _pick(
                            PickedExercise(
                              name: typed,
                              equipment: _cardioOnly ? 'cardio' : null,
                            ),
                          );
                        },
                      ),
                    if (typed.isNotEmpty && !exactMatch)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.bookmark_add_outlined,
                            color: palette.brand),
                        title: Text(
                          'Save "$typed" as a custom exercise',
                          style: TextStyle(
                            color: palette.text,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: Text(
                          'Keep it for next time',
                          style: TextStyle(color: palette.muted),
                        ),
                        onTap: () => _saveAsCustom(typed),
                      ),
                    for (final exercise in shown) _row(exercise),
                    if (results.length > _maxRows)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'Keep typing to narrow ${results.length} matches.',
                          style: TextStyle(color: palette.muted, fontSize: 13),
                        ),
                      ),
                  ],
                ),
              ),
              if (widget.multiSelect && _selected.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      if (_selected.length > 1) ...[
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(
                              PickedExercises(
                                [..._selected],
                                asSuperset: true,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(56),
                              foregroundColor: palette.brandText,
                              side: BorderSide(color: palette.brandSoftStroke),
                            ),
                            child: const Text('Add as superset'),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: PrimaryButton(
                          label: 'Add (${_selected.length})',
                          onPressed: () => Navigator.of(context)
                              .pop(PickedExercises([..._selected])),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 2),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
            color: context.palette.muted,
          ),
        ),
      );
}
