import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_palette.dart';
import '../../../shared/widgets/glass_well.dart';
import '../../../shared/widgets/keyboard_safe_bottom_bar.dart';
import '../../../shared/widgets/liquid_glass.dart';
import '../../../shared/widgets/primary_button.dart';
import '../application/workout_library_providers.dart';
import '../data/content_repository.dart';
import '../domain/exercise_library.dart';
import '../domain/workout_models.dart';

/// Opens the sheet that turns a name into a saved custom exercise.
///
/// Returns the saved exercise, with its document id, or null on dismissal.
Future<CustomExercise?> showCustomExerciseSheet(
  BuildContext context, {
  String initialName = '',
}) {
  return showModalBottomSheet<CustomExercise>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    isScrollControlled: true,
    builder: (sheetContext) => _CustomExerciseSheet(initialName: initialName),
  );
}

class _CustomExerciseSheet extends ConsumerStatefulWidget {
  const _CustomExerciseSheet({required this.initialName});

  final String initialName;

  @override
  ConsumerState<_CustomExerciseSheet> createState() =>
      _CustomExerciseSheetState();
}

class _CustomExerciseSheetState extends ConsumerState<_CustomExerciseSheet> {
  late final TextEditingController _name;
  final Set<String> _muscles = {};
  String _equipment = 'other';
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give the exercise a name.');
      return;
    }
    if (_muscles.isEmpty) {
      setState(() => _error = 'Pick at least one muscle group.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await ref.read(contentRepositoryProvider).saveCustomExercise(
            CustomExercise(
              id: '',
              name: name,
              // Library order, not tap order, so the same choices always
              // read the same.
              muscles: [
                for (final m in ExerciseLibrary.muscleGroups)
                  if (_muscles.contains(m)) m,
              ],
              equipment: _equipment,
            ),
          );
      ref.invalidate(customExercisesProvider);
      if (mounted) Navigator.of(context).pop(saved);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save it. $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    Widget label(String text) => Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 7, top: 12),
          child: Text(
            text.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              color: palette.muted,
            ),
          ),
        );

    return KeyboardSafeBottomBar(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: LiquidGlass(
          lens: true,
          borderRadius: BorderRadius.circular(28),
          child: Container(
            width: double.infinity,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.85,
            ),
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: palette.stroke),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
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
                    'New exercise',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: palette.text,
                    ),
                  ),
                  label('Name'),
                  GlassWell(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: 'e.g. Zottman curl',
                        hintStyle: TextStyle(color: palette.muted),
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                  label('Muscle groups'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final muscle in ExerciseLibrary.muscleGroups)
                        FilterChip(
                          label: Text(muscle),
                          selected: _muscles.contains(muscle),
                          onSelected: (on) => setState(() {
                            on ? _muscles.add(muscle) : _muscles.remove(muscle);
                          }),
                        ),
                    ],
                  ),
                  label('Equipment'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final equipment in ExerciseLibrary.equipmentTypes)
                        ChoiceChip(
                          label: Text(equipment),
                          selected: _equipment == equipment,
                          onSelected: (_) =>
                              setState(() => _equipment = equipment),
                        ),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(color: palette.danger, fontSize: 13),
                    ),
                  ],
                  const SizedBox(height: 20),
                  PrimaryButton(
                    icon: Icons.check_rounded,
                    label: _saving ? 'Saving…' : 'Save exercise',
                    onPressed: _saving ? null : _save,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
