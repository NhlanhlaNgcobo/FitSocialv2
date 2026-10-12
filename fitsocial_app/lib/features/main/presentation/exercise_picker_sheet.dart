import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_palette.dart';
import '../../../shared/widgets/glass_well.dart';
import '../../../shared/widgets/liquid_glass.dart';
import '../application/workout_library_providers.dart';
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
Future<PickedExercise?> showExercisePicker(
  BuildContext context, {
  bool cardioOnly = false,
}) {
  return showModalBottomSheet<PickedExercise>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    isScrollControlled: true,
    builder: (sheetContext) => _ExercisePickerSheet(cardioOnly: cardioOnly),
  );
}

class _ExercisePickerSheet extends ConsumerStatefulWidget {
  const _ExercisePickerSheet({this.cardioOnly = false});

  final bool cardioOnly;

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
    Navigator.of(context).pop(
      PickedExercise(
        name: saved.name,
        id: customExerciseId(saved.id),
        equipment: saved.equipment,
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
        .toList();
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
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
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
                        onTap: () => Navigator.of(context).pop(
                          PickedExercise(
                            name: typed,
                            equipment: _cardioOnly ? 'cardio' : null,
                          ),
                        ),
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
                    for (final exercise in shown)
                      ListTile(
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
                        onTap: () => Navigator.of(context).pop(
                          PickedExercise(
                            name: exercise.name,
                            id: exercise.id,
                            equipment: exercise.equipment,
                          ),
                        ),
                      ),
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
            ],
          ),
        ),
      ),
    );
  }
}
