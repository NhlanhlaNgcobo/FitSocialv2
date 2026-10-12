import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/app_palette.dart';
import '../../../shared/input/typed_number.dart';
import '../../../shared/widgets/glass_well.dart';
import '../../../shared/widgets/keyboard_safe_bottom_bar.dart';
import '../../../shared/widgets/liquid_glass.dart';
import '../../../shared/widgets/primary_button.dart';
import '../domain/active_workout.dart';
import '../domain/workout_math.dart';

/// The small sheets the workout screen opens without leaving the session:
/// plate maths, a warm-up ramp, an RPE rating, an exercise's own rest, and
/// the exercise to superset with.
///
/// All in kilograms, like the rest of the workout screens.

/// "1:30", "0:45" or "Off".
String formatRest(int seconds) {
  if (seconds <= 0) return 'Off';
  final s = seconds.remainder(60).toString().padLeft(2, '0');
  return '${seconds ~/ 60}:$s';
}

/// "62.5" or "60" — no trailing ".0".
String formatKgValue(double kg) {
  if (kg == kg.roundToDouble()) return kg.round().toString();
  final fixed = kg.toStringAsFixed(2);
  return fixed.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}

Future<T?> _showToolSheet<T>(BuildContext context, WidgetBuilder builder) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    isScrollControlled: true,
    builder: builder,
  );
}

/// The glass frame every sheet here sits in: handle, title, optional subtitle.
class _ToolSheet extends StatelessWidget {
  const _ToolSheet({
    required this.title,
    required this.children,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;

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
                    title,
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: palette.text,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      style: TextStyle(fontSize: 14, color: palette.muted),
                    ),
                  ],
                  const SizedBox(height: 14),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Widget _label(BuildContext context, String text) => Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 7, top: 12),
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

/// A single kilogram field in a well.
class _KgField extends StatelessWidget {
  const _KgField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return GlassWell(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
        style: TextStyle(
          color: palette.text,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: '0',
          hintStyle: TextStyle(color: palette.muted),
          suffixText: 'kg',
          suffixStyle: TextStyle(color: palette.muted, fontSize: 16),
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
        onChanged: onChanged,
      ),
    );
  }
}

// --- Plate calculator --------------------------------------------------------

/// Which plates go on each side of the bar for a target load.
Future<void> showPlateCalculator(
  BuildContext context, {
  double initialKg = 0,
}) {
  return _showToolSheet<void>(
    context,
    (_) => _PlateCalculatorSheet(initialKg: initialKg),
  );
}

class _PlateCalculatorSheet extends StatefulWidget {
  const _PlateCalculatorSheet({required this.initialKg});

  final double initialKg;

  @override
  State<_PlateCalculatorSheet> createState() => _PlateCalculatorSheetState();
}

class _PlateCalculatorSheetState extends State<_PlateCalculatorSheet> {
  late final TextEditingController _target;
  double _bar = barOptionsKg.first;

  @override
  void initState() {
    super.initState();
    _target = TextEditingController(
      text: widget.initialKg > 0 ? formatKgValue(widget.initialKg) : '',
    );
  }

  @override
  void dispose() {
    _target.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final target = parseTypedDouble(_target.text) ?? 0;
    final breakdown = target > 0
        ? platesPerSide(target, bar: _bar, plates: standardPlatesKg)
        : null;

    final String summary;
    if (breakdown == null) {
      summary = 'Type the weight you want on the bar.';
    } else if (breakdown.belowBar) {
      summary = 'That is lighter than the ${formatKgValue(_bar)} kg bar.';
    } else if (breakdown.perSide.isEmpty) {
      summary = 'Just the empty bar.';
    } else if (breakdown.shortfall > 0.0005) {
      summary = 'Closest is ${formatKgValue(breakdown.loaded)} kg, '
          '${formatKgValue(breakdown.shortfall)} kg short.';
    } else {
      summary = 'Per side, on a ${formatKgValue(_bar)} kg bar.';
    }

    return _ToolSheet(
      title: 'Plate calculator',
      children: [
        _label(context, 'Target'),
        _KgField(controller: _target, onChanged: (_) => setState(() {})),
        _label(context, 'Bar'),
        Wrap(
          spacing: 8,
          children: [
            for (final bar in barOptionsKg)
              ChoiceChip(
                label: Text('${formatKgValue(bar)} kg'),
                selected: _bar == bar,
                onSelected: (_) => setState(() => _bar = bar),
              ),
          ],
        ),
        const SizedBox(height: 18),
        if (breakdown != null && breakdown.perSide.isNotEmpty) ...[
          PlateDiagram(plates: breakdown.perSide),
          const SizedBox(height: 10),
          Text(
            breakdown.perSide.map(formatKgValue).join('  ·  '),
            key: const ValueKey('plates-per-side'),
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: palette.text,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 4),
        ],
        Text(summary, style: TextStyle(fontSize: 14, color: palette.muted)),
      ],
    );
  }
}

/// One side of a loaded bar: the sleeve, then plates heaviest-first from the
/// collar outwards, each as tall as its weight suggests.
class PlateDiagram extends StatelessWidget {
  const PlateDiagram({required this.plates, super.key});

  final List<double> plates;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    double height(double kg) => 26 + 46 * (kg / standardPlatesKg.first);

    return SizedBox(
      height: 76,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(width: 34, height: 10, color: palette.stroke),
          Container(width: 6, height: 26, color: palette.muted),
          for (final plate in plates)
            Container(
              width: plate >= 10 ? 14 : 10,
              height: height(plate),
              margin: const EdgeInsets.only(left: 2),
              decoration: BoxDecoration(
                color: palette.brand.withValues(
                  alpha: 0.35 + 0.65 * (plate / standardPlatesKg.first),
                ),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          Expanded(
            child: Container(height: 10, color: palette.stroke),
          ),
        ],
      ),
    );
  }
}

// --- Warm-up sets ------------------------------------------------------------

/// A ramp of warm-up sets up to a working weight. Returns the sets to add, or
/// null when dismissed.
Future<List<WarmupSet>?> showWarmupSheet(
  BuildContext context, {
  required String exerciseName,
  required double workingKg,
  String? equipment,
}) {
  return _showToolSheet<List<WarmupSet>>(
    context,
    (_) => _WarmupSheet(
      exerciseName: exerciseName,
      workingKg: workingKg,
      equipment: equipment,
    ),
  );
}

class _WarmupSheet extends StatefulWidget {
  const _WarmupSheet({
    required this.exerciseName,
    required this.workingKg,
    required this.equipment,
  });

  final String exerciseName;
  final double workingKg;
  final String? equipment;

  @override
  State<_WarmupSheet> createState() => _WarmupSheetState();
}

class _WarmupSheetState extends State<_WarmupSheet> {
  late final TextEditingController _target;

  @override
  void initState() {
    super.initState();
    _target = TextEditingController(
      text: widget.workingKg > 0 ? formatKgValue(widget.workingKg) : '',
    );
  }

  @override
  void dispose() {
    _target.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final kit = warmupKit(widget.equipment);
    final target = parseTypedDouble(_target.text) ?? 0;
    final ramp = target > 0
        ? warmupRamp(target, bar: kit.bar, increment: kit.increment)
        : const <WarmupSet>[];

    return _ToolSheet(
      title: 'Warm-up sets',
      subtitle: widget.exerciseName,
      children: [
        _label(context, 'Working weight'),
        _KgField(controller: _target, onChanged: (_) => setState(() {})),
        const SizedBox(height: 14),
        if (ramp.isEmpty)
          Text(
            target <= 0
                ? 'Type the weight of your first working set.'
                : 'That is light enough to start on — no warm-up needed.',
            style: TextStyle(fontSize: 14, color: palette.muted),
          )
        else
          GlassWell(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Column(
              children: [
                for (final set in ramp)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 32,
                          child: Text(
                            'W',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: palette.muted,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            '${formatKgValue(set.weight)} kg',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: palette.text,
                            ),
                          ),
                        ),
                        Text(
                          '× ${set.reps}',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: palette.text,
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 44,
                          child: Text(
                            '${(set.weight / target * 100).round()}%',
                            textAlign: TextAlign.right,
                            style: TextStyle(color: palette.muted),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 20),
        PrimaryButton(
          icon: Icons.add_rounded,
          label: 'Add warm-up sets',
          onPressed: ramp.isEmpty ? null : () => Navigator.of(context).pop(ramp),
        ),
      ],
    );
  }
}

// --- RPE ---------------------------------------------------------------------

/// The ratings offered: 6 to 10 in half steps.
const rpeChoices = [6.0, 6.5, 7.0, 7.5, 8.0, 8.5, 9.0, 9.5, 10.0];

String _rpeMeaning(double rpe) => switch (rpe) {
      >= 10 => 'Nothing left',
      >= 9.5 => 'Maybe more weight, no more reps',
      >= 9 => '1 rep left',
      >= 8.5 => '1 or 2 reps left',
      >= 8 => '2 reps left',
      >= 7.5 => '2 or 3 reps left',
      >= 7 => '3 reps left',
      _ => '4 or more reps left',
    };

/// "8", "8.5".
String formatRpe(double rpe) =>
    rpe == rpe.roundToDouble() ? '${rpe.round()}' : '$rpe';

/// Picks an RPE. Resolves to `(rpe: value)`, `(rpe: null)` to clear it, or null
/// when dismissed.
Future<({double? rpe})?> showRpePicker(
  BuildContext context, {
  double? current,
}) {
  return _showToolSheet<({double? rpe})>(
    context,
    (sheetContext) {
      final palette = sheetContext.palette;
      return _ToolSheet(
        title: 'How hard was it?',
        subtitle: 'Rate of perceived exertion',
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final rpe in rpeChoices)
                ChoiceChip(
                  label: Text(formatRpe(rpe)),
                  selected: current == rpe,
                  onSelected: (_) =>
                      Navigator.of(sheetContext).pop((rpe: rpe)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            current == null
                ? '10 is nothing left in the tank; 8 is two reps left.'
                : '${formatRpe(current)}: ${_rpeMeaning(current)}.',
            style: TextStyle(fontSize: 14, color: palette.muted),
          ),
          if (current != null) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(sheetContext).pop((rpe: null)),
              child: const Text('Clear rating'),
            ),
          ],
        ],
      );
    },
  );
}

// --- Rest per exercise -------------------------------------------------------

/// Picks this exercise's own rest. Resolves to `(seconds: n)`, `(seconds:
/// null)` to go back to the default, or null when dismissed.
Future<({int? seconds})?> showRestOverridePicker(
  BuildContext context, {
  required String exerciseName,
  required int? current,
  required int defaultSeconds,
  required List<int> choices,
}) {
  return _showToolSheet<({int? seconds})>(
    context,
    (sheetContext) => _ToolSheet(
      title: 'Rest timer',
      subtitle: exerciseName,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: Text('Default (${formatRest(defaultSeconds)})'),
              selected: current == null,
              onSelected: (_) =>
                  Navigator.of(sheetContext).pop((seconds: null)),
            ),
            for (final seconds in choices)
              ChoiceChip(
                label: Text(formatRest(seconds)),
                selected: current == seconds,
                onSelected: (_) =>
                    Navigator.of(sheetContext).pop((seconds: seconds)),
              ),
          ],
        ),
      ],
    ),
  );
}

// --- Superset ----------------------------------------------------------------

/// Picks the exercise to superset with. Resolves to its key, or null.
Future<String?> showSupersetPicker(
  BuildContext context, {
  required String exerciseName,
  required List<ActiveExercise> candidates,
}) {
  return _showToolSheet<String>(
    context,
    (sheetContext) {
      final palette = sheetContext.palette;
      return _ToolSheet(
        title: 'Superset with…',
        subtitle: 'Done back to back with $exerciseName, resting only after '
            'the last of them.',
        children: [
          if (candidates.isEmpty)
            Text(
              'Add another exercise first.',
              style: TextStyle(fontSize: 14, color: palette.muted),
            )
          else
            GlassWell(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final e in candidates)
                    ListTile(
                      title: Text(
                        e.name,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: palette.text,
                        ),
                      ),
                      trailing: e.supersetGroup == null
                          ? null
                          : Text(
                              'In a superset',
                              style: TextStyle(color: palette.muted),
                            ),
                      onTap: () => Navigator.of(sheetContext).pop(e.key),
                    ),
                ],
              ),
            ),
        ],
      );
    },
  );
}
