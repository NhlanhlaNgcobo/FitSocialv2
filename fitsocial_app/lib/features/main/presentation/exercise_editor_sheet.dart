import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/glass_well.dart';
import '../../../shared/widgets/keyboard_safe_bottom_bar.dart';
import '../../../shared/widgets/liquid_glass.dart';
import '../../../shared/widgets/primary_button.dart';
import '../domain/app_models.dart';

/// What came back from the editor: a row to keep, or a row to drop.
class ExerciseEditorResult {
  const ExerciseEditorResult.saved(ExerciseEntry this.entry) : removed = false;

  const ExerciseEditorResult.removed()
      : entry = null,
        removed = true;

  final ExerciseEntry? entry;
  final bool removed;
}

/// Opens the editor for one row of the training log.
///
/// A sheet rather than four inputs inline in the table, and the reason is
/// width. The table is the *read* view — name, sets, reps, load in four
/// columns, which is what makes the log scannable. Four editable fields across
/// a 360dp phone is around 40dp each: too narrow to label, too narrow to tap
/// accurately, and it puts the row under the keyboard the moment it is
/// focused. The sheet gives each number a label and a full-width target, and
/// the table goes on reading as a table.
///
/// Returns null when the sheet was dismissed without a decision.
Future<ExerciseEditorResult?> showExerciseEditor(
  BuildContext context, {
  ExerciseEntry? initial,
}) {
  return showModalBottomSheet<ExerciseEditorResult>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    // The sheet holds text fields, so it has to be able to grow out from under
    // the keyboard rather than being clipped at half the screen.
    isScrollControlled: true,
    builder: (sheetContext) => _ExerciseEditorSheet(initial: initial),
  );
}

class _ExerciseEditorSheet extends StatefulWidget {
  const _ExerciseEditorSheet({required this.initial});

  final ExerciseEntry? initial;

  @override
  State<_ExerciseEditorSheet> createState() => _ExerciseEditorSheetState();
}

class _ExerciseEditorSheetState extends State<_ExerciseEditorSheet> {
  late final TextEditingController _name;
  late final TextEditingController _sets;
  late final TextEditingController _reps;
  late final TextEditingController _weight;

  String? _error;

  bool get _isEditing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _name = TextEditingController(text: initial?.name ?? '');
    // Zero reads as "not filled in" on this form, so it starts blank rather
    // than making the user clear a 0 before typing.
    _sets = TextEditingController(text: _number(initial?.sets));
    _reps = TextEditingController(text: _number(initial?.reps));
    _weight = TextEditingController(text: _decimal(initial?.weightKg));
  }

  static String _number(int? value) =>
      value == null || value == 0 ? '' : '$value';

  /// `60.0` → `60`, `22.5` → `22.5`. The field should hand back what the user
  /// typed, not a normalised double.
  static String _decimal(double? value) {
    if (value == null || value == 0) return '';
    final text = value.toStringAsFixed(1);
    return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
  }

  @override
  void dispose() {
    _name.dispose();
    _sets.dispose();
    _reps.dispose();
    _weight.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give the exercise a name.');
      return;
    }

    Navigator.of(context).pop(
      ExerciseEditorResult.saved(
        ExerciseEntry(
          name: name,
          sets: int.tryParse(_sets.text.trim()) ?? 0,
          reps: int.tryParse(_reps.text.trim()) ?? 0,
          // Null rather than zero for a blank field: an unweighted exercise is
          // not an exercise lifted with no weight, and the card draws the two
          // differently — see [ExerciseEntry.weightKg].
          weightKg: double.tryParse(_weight.text.trim().replaceAll(',', '.')),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return KeyboardSafeBottomBar(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: LiquidGlass(
          lens: true,
          borderRadius: BorderRadius.circular(28),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: palette.stroke),
              boxShadow: [
                BoxShadow(
                  color: palette.navShadow,
                  blurRadius: 32,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
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
                const SizedBox(height: 20),
                Text(
                  _isEditing ? 'Edit exercise' : 'Add exercise',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: palette.text,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                _FieldLabel('Exercise', palette: palette),
                GlassWell(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: _name,
                    autofocus: !_isEditing,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    style: TextStyle(
                      color: palette.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: 'e.g. Bench press',
                      hintStyle: TextStyle(color: palette.muted),
                      contentPadding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    onChanged: (_) {
                      if (_error != null) setState(() => _error = null);
                    },
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _NumberField(
                        label: 'Sets',
                        controller: _sets,
                        hint: '0',
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _NumberField(
                        label: 'Reps',
                        controller: _reps,
                        hint: '0',
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _NumberField(
                        label: 'Weight (kg)',
                        controller: _weight,
                        hint: '—',
                        decimal: true,
                      ),
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
                const SizedBox(height: AppSpacing.lg),
                PrimaryButton(
                  icon: Icons.check_rounded,
                  label: _isEditing ? 'Save exercise' : 'Add exercise',
                  onPressed: _save,
                ),
                if (_isEditing)
                  Center(
                    child: TextButton(
                      onPressed: () => Navigator.of(context)
                          .pop(const ExerciseEditorResult.removed()),
                      child: Text(
                        'Remove from workout',
                        style: TextStyle(
                          color: palette.danger,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text, {required this.palette});

  final String text;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 7),
      child: Text(
        text.toUpperCase(),
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
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.label,
    required this.controller,
    required this.hint,
    this.decimal = false,
  });

  final String label;
  final TextEditingController controller;
  final String hint;

  /// Weight takes half plates; sets and reps do not.
  final bool decimal;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label, palette: palette),
        GlassWell(
          child: TextField(
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
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: hint,
              hintStyle: TextStyle(
                color: palette.muted,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }
}
