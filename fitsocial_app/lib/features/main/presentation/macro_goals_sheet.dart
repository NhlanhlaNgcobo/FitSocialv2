import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/primary_button.dart';
import '../application/content_providers.dart';
import '../data/content_repository.dart';
import '../domain/meal_tracking.dart';
import '../../../shared/widgets/liquid_glass.dart';

/// Opens the daily macro targets editor.
Future<void> showMacroGoalsSheet(BuildContext context, WidgetRef ref) async {
  final current = await ref.read(macroGoalsProvider.future);
  final calculated = await ref.read(calculatedMacroGoalsProvider.future);
  if (!context.mounted) return;

  final result = await showModalBottomSheet<_SheetResult>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _MacroGoalsSheet(initial: current, calculated: calculated),
  );
  if (result == null) return;

  final repository = ref.read(contentRepositoryProvider);
  final goals = result.goals;
  // Saving targets that were calculated, untouched, must not store them as
  // the user's own: they would stop following the body they were worked out
  // from, the first time somebody opened the sheet to flip the step switch.
  final keepsCalculated = !current.isCustom && _sameTargets(goals, current);
  if (result.useCalculated || keepsCalculated) {
    await repository.clearCustomMacroGoals(stepBonus: goals.stepBonus);
  } else {
    await repository.setMacroGoals(goals);
  }
  ref.invalidate(macroGoalsProvider);
}

bool _sameTargets(MacroGoals a, MacroGoals b) =>
    MacroKind.values.every((kind) => a.of(kind) == b.of(kind));

/// What the sheet closed with: targets to save, or a request to go back to
/// the calculated ones.
class _SheetResult {
  const _SheetResult(this.goals, {this.useCalculated = false});

  final MacroGoals goals;
  final bool useCalculated;
}

class _MacroGoalsSheet extends StatefulWidget {
  const _MacroGoalsSheet({required this.initial, required this.calculated});

  final MacroGoals initial;

  /// The targets worked out from body and plan; null while an input is
  /// missing, which is when there is nothing to go back to.
  final MacroGoals? calculated;

  @override
  State<_MacroGoalsSheet> createState() => _MacroGoalsSheetState();
}

class _MacroGoalsSheetState extends State<_MacroGoalsSheet> {
  late bool _stepBonus = widget.initial.stepBonus;

  late final Map<MacroKind, TextEditingController> _controllers = {
    for (final kind in MacroKind.values)
      kind: TextEditingController(text: '${widget.initial.of(kind)}'),
  };

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// A target that was cleared or mistyped falls back to what it was rather
  /// than to zero — a zero goal makes every bar read 0% and every percentage
  /// meaningless.
  int _read(MacroKind kind) {
    final typed = int.tryParse(_controllers[kind]!.text.trim());
    if (typed == null || typed <= 0) return widget.initial.of(kind);
    return typed;
  }

  void _save() {
    Navigator.of(context).pop(
      _SheetResult(
        MacroGoals(
          calories: _read(MacroKind.calories),
          protein: _read(MacroKind.protein),
          carbs: _read(MacroKind.carbs),
          fat: _read(MacroKind.fat),
          stepBonus: _stepBonus,
        ),
      ),
    );
  }

  void _useCalculated() {
    Navigator.of(context).pop(
      _SheetResult(
        widget.calculated!.copyWith(stepBonus: _stepBonus),
        useCalculated: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final calculated = widget.calculated;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: LiquidGlass(
        // Over the screen it was opened from, so there is real content to bend.
        lens: true,
        // A sheet always has a page behind it, which makes it the one
        // surface in the app guaranteed something worth bending.
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: palette.stroke),
          ),
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Daily targets',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: palette.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'A week or a month is measured against these, multiplied by '
                    'the days in the period.',
                    style: TextStyle(
                      color: palette.muted,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                  if (widget.initial.isCustom && calculated != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    _CalculatedOffer(
                      calculated: calculated,
                      onUse: _useCalculated,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  for (final kind in MacroKind.values) ...[
                    _GoalField(
                      label: kind.label,
                      unit: kind.unit,
                      controller: _controllers[kind]!,
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: _stepBonus,
                    onChanged: (value) => setState(() => _stepBonus = value),
                    title: Text(
                      'Add calories for steps',
                      style: TextStyle(
                        color: palette.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      'Walking past ${formatMacroValue(StepCalories.baselineSteps)} '
                      'steps raises the calorie target for that day.',
                      style: TextStyle(color: palette.muted, fontSize: 12.5),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  PrimaryButton(label: 'Save targets', onPressed: _save),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown only to someone whose own targets are overriding the calculated
/// ones: what the calculation says, and the way back to it. Without this a
/// target typed in once stays forever, however far the body behind it moves.
class _CalculatedOffer extends StatelessWidget {
  const _CalculatedOffer({required this.calculated, required this.onUse});

  final MacroGoals calculated;
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: palette.brandSoft,
        borderRadius: BorderRadius.circular(AppRadius.nested),
        border: Border.all(color: palette.brandSoftStroke),
      ),
      // Stacked rather than side by side: the button's label is too long to
      // share a phone's width with the sentence it answers.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'These are your own. Calculated for you: '
            '${formatMacroValue(calculated.calories)} kcal a day.',
            style: TextStyle(
              color: palette.text,
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
          TextButton(
            onPressed: onUse,
            style: TextButton.styleFrom(
              foregroundColor: palette.brandText,
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
            child: const Text(
              'Use calculated target',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _GoalField extends StatelessWidget {
  const _GoalField({
    required this.label,
    required this.unit,
    required this.controller,
  });

  final String label;
  final String unit;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: palette.text,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        SizedBox(
          width: 130,
          child: TextField(
            controller: controller,
            textAlign: TextAlign.end,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              suffixText: unit,
              isDense: true,
              // No fill: this field is inside the sheet's own pane, and an
              // opaque one here is a box inside a box. The pane drops it for
              // everything under it -- setting it explicitly would override
              // that and put the slab back.
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.nested),
                borderSide: BorderSide(color: palette.stroke),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.nested),
                borderSide: BorderSide(color: palette.stroke),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
