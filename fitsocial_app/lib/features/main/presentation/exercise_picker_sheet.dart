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
  const PickedExercise({required this.name, this.id});

  final String name;

  /// Null for a typed name that is not in the library.
  final String? id;
}

/// Opens the exercise picker.
///
/// Searches the bundled library and the user's own exercises together, and can
/// save a typed name as a new custom exercise. Returns null on dismissal.
Future<PickedExercise?> showExercisePicker(BuildContext context) {
  return showModalBottomSheet<PickedExercise>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    isScrollControlled: true,
    builder: (sheetContext) => const _ExercisePickerSheet(),
  );
}

class _ExercisePickerSheet extends ConsumerStatefulWidget {
  const _ExercisePickerSheet();

  @override
  ConsumerState<_ExercisePickerSheet> createState() =>
      _ExercisePickerSheetState();
}

class _ExercisePickerSheetState extends ConsumerState<_ExercisePickerSheet> {
  final _query = TextEditingController();

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
      PickedExercise(name: saved.name, id: customExerciseId(saved.id)),
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
    final results = ExerciseLibrary.search(typed, extra: extra);
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
              Text(
                'Add exercise',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: palette.text,
                ),
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
                    hintText: 'Search, e.g. incline dumbbell',
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
                        onTap: () => Navigator.of(context)
                            .pop(PickedExercise(name: typed)),
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
                              name: exercise.name, id: exercise.id),
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
