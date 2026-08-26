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
  if (!context.mounted) return;

  final saved = await showModalBottomSheet<MacroGoals>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _MacroGoalsSheet(initial: current),
  );
  if (saved == null) return;

  await ref.read(contentRepositoryProvider).setMacroGoals(saved);
  ref.invalidate(macroGoalsProvider);
}

class _MacroGoalsSheet extends StatefulWidget {
  const _MacroGoalsSheet({required this.initial});

  final MacroGoals initial;

  @override
  State<_MacroGoalsSheet> createState() => _MacroGoalsSheetState();
}

class _MacroGoalsSheetState extends State<_MacroGoalsSheet> {
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
      MacroGoals(
        calories: _read(MacroKind.calories),
        protein: _read(MacroKind.protein),
        carbs: _read(MacroKind.carbs),
        fat: _read(MacroKind.fat),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: LiquidGlass(
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
                  const SizedBox(height: AppSpacing.lg),
                  for (final kind in MacroKind.values) ...[
                    _GoalField(
                      label: kind.label,
                      unit: kind.unit,
                      controller: _controllers[kind]!,
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
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
