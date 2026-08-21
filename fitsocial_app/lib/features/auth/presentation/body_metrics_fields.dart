import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../domain/body_metrics.dart';
import '../../../shared/widgets/liquid_glass.dart';

/// The height, weight and units inputs, with whatever they currently add up to.
///
/// Lives here rather than inside the BMI screen because three screens need the
/// same inputs — the calculator, profile setup, and profile editing — and three
/// copies of a two-unit form is three places for the conversions to drift.
///
/// Reports upward through [onChanged] and holds no opinion about saving. Each
/// host decides when that happens.
class BodyMetricsFields extends StatefulWidget {
  const BodyMetricsFields({
    required this.initial,
    required this.onChanged,
    this.showReadout = true,
    this.enabled = true,
    super.key,
  });

  final BodyMetrics initial;
  final ValueChanged<BodyMetrics> onChanged;

  /// Whether to draw the BMI readout above the fields. Profile setup turns it
  /// down to a single line; the calculator shows the full scale.
  final bool showReadout;

  final bool enabled;

  @override
  State<BodyMetricsFields> createState() => _BodyMetricsFieldsState();
}

class _BodyMetricsFieldsState extends State<BodyMetricsFields> {
  /// Metric height, and the whole-feet half of an imperial one.
  final _heightController = TextEditingController();

  /// The inches left over. Unused in metric.
  final _inchesController = TextEditingController();
  final _weightController = TextEditingController();

  late MeasurementUnits _units;

  @override
  void initState() {
    super.initState();
    _units = widget.initial.units;
    _writeFields(
      heightCm: widget.initial.heightCm,
      weightKg: widget.initial.weightKg,
    );
    for (final controller in [
      _heightController,
      _inchesController,
      _weightController,
    ]) {
      controller.addListener(_report);
    }
  }

  @override
  void didUpdateWidget(BodyMetricsFields oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Seeded values can arrive after the first build — the stored metrics are
    // loaded asynchronously. Only adopt them while the user has typed nothing,
    // so a late load never overwrites what they are in the middle of entering.
    final wasEmpty = oldWidget.initial.isEmpty && current.isEmpty;
    if (wasEmpty && !widget.initial.isEmpty) {
      _units = widget.initial.units;
      _writeFields(
        heightCm: widget.initial.heightCm,
        weightKg: widget.initial.weightKg,
      );
    }
  }

  @override
  void dispose() {
    _heightController.dispose();
    _inchesController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  /// What the fields currently say, in storage units.
  BodyMetrics get current => BodyMetrics(
        heightCm: _readHeightCm(),
        weightKg: _readWeightKg(),
        units: _units,
      );

  void _report() {
    setState(() {});
    widget.onChanged(current);
  }

  double? _readHeightCm() {
    if (_units == MeasurementUnits.metric) {
      // Reads "1.75" as metres and "175" as centimetres — people type both,
      // and the two ranges cannot overlap for a human.
      return metricHeightToCm(_heightController.text);
    }
    final feet = parseMeasurement(_heightController.text);
    if (feet == null) return null;
    // Inches may be blank on a round height — "6 ft" is a thing people type.
    final inches = parseMeasurement(_inchesController.text) ?? 0;
    return feetAndInchesToCm(feet, inches);
  }

  double? _readWeightKg() {
    final entered = parseMeasurement(_weightController.text);
    if (entered == null) return null;
    return _units == MeasurementUnits.metric ? entered : poundsToKg(entered);
  }

  /// Rewrites the fields into [units] without changing what they mean.
  void _switchUnits(MeasurementUnits units) {
    if (units == _units) return;

    // Read in the *old* units before the switch, so the conversion has
    // something true to convert.
    final heightCm = _readHeightCm();
    final weightKg = _readWeightKg();

    setState(() {
      _units = units;
      _writeFields(heightCm: heightCm, weightKg: weightKg);
    });
    widget.onChanged(current);
  }

  void _writeFields({double? heightCm, double? weightKg}) {
    if (heightCm == null) {
      _heightController.clear();
      _inchesController.clear();
    } else if (_units == MeasurementUnits.metric) {
      _heightController.text = _trimZeros(heightCm);
      _inchesController.clear();
    } else {
      final split = cmToFeetAndInches(heightCm);
      _heightController.text = '${split.feet}';
      // Kept to a decimal rather than rounded to whole inches. A whole inch is
      // 2.54 cm, and dropping that much height moves the BMI by about 0.1 —
      // small, but the user watching it change as they toggle units reads it
      // as the app losing track. _trimZeros still shows a round 9 as "9".
      _inchesController.text = _trimZeros(split.inches);
    }

    if (weightKg == null) {
      _weightController.clear();
    } else {
      _weightController.text = _trimZeros(
        _units == MeasurementUnits.metric ? weightKg : kgToPounds(weightKg),
      );
    }
  }

  /// "70" rather than "70.0", but "70.5" kept.
  static String _trimZeros(double value) {
    final rounded = value.toStringAsFixed(1);
    return rounded.endsWith('.0')
        ? rounded.substring(0, rounded.length - 2)
        : rounded;
  }

  @override
  Widget build(BuildContext context) {
    final metrics = current;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showReadout) ...[
          BmiReadout(metrics: metrics),
          const SizedBox(height: AppSpacing.lg),
        ],
        _UnitsToggle(
          units: _units,
          enabled: widget.enabled,
          onChanged: _switchUnits,
        ),
        const SizedBox(height: AppSpacing.lg),
        _HeightFields(
          units: _units,
          enabled: widget.enabled,
          primary: _heightController,
          inches: _inchesController,
        ),
        const SizedBox(height: AppSpacing.md),
        _MeasurementField(
          controller: _weightController,
          enabled: widget.enabled,
          label: 'Weight',
          suffix: _units.weightLabel,
        ),
        // Compact hosts still get an answer, just a smaller one: the BMI once
        // there is one, and otherwise the reason there isn't. Silence here is
        // what made a filled-in form look broken.
        if (!widget.showReadout && !metrics.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: metrics.issue == null
                ? BmiInlineResult(metrics: metrics)
                : _IssueLine(issue: metrics.issue!),
          ),
      ],
    );
  }
}

/// The BMI as one line — for hosts that want the answer without the scale.
class BmiInlineResult extends StatelessWidget {
  const BmiInlineResult({required this.metrics, super.key});

  final BodyMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final category = metrics.category;
    final label = metrics.bmiLabel;
    if (category == null || label == null) return const SizedBox.shrink();

    final color = bmiBandColor(category, palette);

    return Row(
      children: [
        Icon(Icons.monitor_heart_outlined, size: 18, color: color),
        const SizedBox(width: AppSpacing.sm),
        Text(
          'BMI $label',
          style: TextStyle(color: palette.text, fontWeight: FontWeight.w800),
        ),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              category.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The colour each BMI band is drawn in, on the scale and on the category pill.
///
/// Healthy is the app's success green and the extremes step outward from it.
/// Underweight and overweight share a colour deliberately: they are equally far
/// from the middle, and giving one a harsher colour than the other would be the
/// screen taking a view it has no business taking.
Color bmiBandColor(BmiCategory category, AppPalette palette) {
  return switch (category) {
    BmiCategory.underweight => const Color(0xFF5B9FD4),
    BmiCategory.healthy => palette.success,
    BmiCategory.overweight => const Color(0xFFF5C451),
    BmiCategory.obese => palette.danger,
  };
}

/// The number, its category, and where it sits on the scale — or, when there
/// is no number, what is stopping there being one.
class BmiReadout extends StatelessWidget {
  const BmiReadout({required this.metrics, super.key});

  final BodyMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final bmi = metrics.bmi;
    final category = metrics.category;

    if (bmi == null || category == null) {
      final issue = metrics.issue;
      // An untouched form gets the invitation. A form with something in it
      // gets the reason — telling a user who has typed their height and weight
      // to "enter your height and weight" is the bug this replaced.
      final showIssue = !metrics.isEmpty && issue != null;

      return _ReadoutShell(
        child: Column(
          children: [
            Icon(
              showIssue
                  ? Icons.error_outline_rounded
                  : Icons.straighten_rounded,
              size: 40,
              color: showIssue ? palette.danger : palette.muted,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              showIssue ? 'No BMI yet' : 'Enter your height and weight',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: palette.text,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              showIssue ? issue.message : 'Your BMI appears here as you type.',
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.muted, height: 1.35),
            ),
          ],
        ),
      );
    }

    final color = bmiBandColor(category, palette);
    final range = metrics.healthyWeightRange;

    return _ReadoutShell(
      child: Column(
        children: [
          Text(
            bmi.toStringAsFixed(1),
            style: TextStyle(
              fontSize: 56,
              height: 1,
              fontWeight: FontWeight.w900,
              color: palette.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'BODY MASS INDEX',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 1.6,
              fontWeight: FontWeight.w700,
              color: palette.muted,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              category.label,
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          BmiScale(bmi: bmi),
          if (range != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              'A healthy weight for your height is '
              '${range.lowKg.toStringAsFixed(0)}–${range.highKg.toStringAsFixed(0)} kg.',
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.muted, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReadoutShell extends StatelessWidget {
  const _ReadoutShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return LiquidGlass(
      // Painted by the lens rather than by a fill of its own: a pane
      // over the app backdrop, like every other card.
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: palette.stroke),
        ),
        child: child,
      ),
    );
  }
}

class _IssueLine extends StatelessWidget {
  const _IssueLine({required this.issue});

  final BodyMetricsIssue issue;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.error_outline_rounded, size: 16, color: palette.danger),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            issue.message,
            style: TextStyle(color: palette.danger, fontSize: 13, height: 1.35),
          ),
        ),
      ],
    );
  }
}

/// The four bands as one bar, with a marker at [bmi].
///
/// The bands are not drawn to scale — obese runs to infinity and would swallow
/// the bar. Each gets an equal quarter, and the marker is placed by
/// interpolating inside whichever band it falls in.
class BmiScale extends StatelessWidget {
  const BmiScale({required this.bmi, super.key});

  final double bmi;

  /// The top of the scale. Beyond this the marker pins to the right edge.
  static const double _ceiling = 40;

  double get _markerFraction {
    const bands = BmiCategory.values;
    final index = bands.indexOf(BmiCategory.of(bmi));
    final start = bands[index].lowerBound;
    final end =
        index + 1 < bands.length ? bands[index + 1].lowerBound : _ceiling;
    final within = ((bmi - start) / (end - start)).clamp(0.0, 1.0);
    return ((index + within) / bands.length).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        const markerSize = 14.0;

        return Column(
          children: [
            SizedBox(
              height: markerSize,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    // Centred on its point, and held inside the bar at both
                    // ends so an extreme BMI doesn't hang off the card.
                    left: (width * _markerFraction - markerSize / 2)
                        .clamp(0.0, width - markerSize),
                    child: Icon(
                      Icons.arrow_drop_down_rounded,
                      size: markerSize + 10,
                      color: palette.text,
                    ),
                  ),
                ],
              ),
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: Row(
                children: [
                  for (final band in BmiCategory.values)
                    Expanded(
                      child: Container(
                        height: 10,
                        color: bmiBandColor(band, palette),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final label in const ['15', '18.5', '25', '30', '40+'])
                  Text(
                    label,
                    style: TextStyle(color: palette.muted, fontSize: 11),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _UnitsToggle extends StatelessWidget {
  const _UnitsToggle({
    required this.units,
    required this.enabled,
    required this.onChanged,
  });

  final MeasurementUnits units;
  final bool enabled;
  final ValueChanged<MeasurementUnits> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Row(
      children: [
        for (final option in MeasurementUnits.values)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                right:
                    option == MeasurementUnits.values.first ? AppSpacing.sm : 0,
              ),
              child: GestureDetector(
                onTap: enabled ? () => onChanged(option) : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: option == units
                        ? palette.brandSoft
                        : palette.surfaceHigh,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: option == units
                          ? palette.brandSoftStroke
                          : palette.stroke,
                    ),
                  ),
                  child: Text(
                    option == MeasurementUnits.metric
                        ? 'Metric (cm/kg)'
                        : 'Imperial (ft/lb)',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color:
                          option == units ? palette.brandText : palette.muted,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// One field in metric, two in imperial.
class _HeightFields extends StatelessWidget {
  const _HeightFields({
    required this.units,
    required this.enabled,
    required this.primary,
    required this.inches,
  });

  final MeasurementUnits units;
  final bool enabled;
  final TextEditingController primary;
  final TextEditingController inches;

  @override
  Widget build(BuildContext context) {
    if (units == MeasurementUnits.metric) {
      return _MeasurementField(
        controller: primary,
        enabled: enabled,
        label: 'Height',
        suffix: 'cm',
      );
    }

    return Row(
      children: [
        Expanded(
          child: _MeasurementField(
            controller: primary,
            enabled: enabled,
            label: 'Height',
            suffix: 'ft',
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: _MeasurementField(
            controller: inches,
            enabled: enabled,
            label: '',
            suffix: 'in',
          ),
        ),
      ],
    );
  }
}

class _MeasurementField extends StatelessWidget {
  const _MeasurementField({
    required this.controller,
    required this.enabled,
    required this.label,
    required this.suffix,
  });

  final TextEditingController controller;
  final bool enabled;
  final String label;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // An empty label still reserves its line, so the inches field lines up
        // with the feet field beside it instead of riding higher.
        Text(
          label.isEmpty ? ' ' : label,
          style: TextStyle(
            color: palette.muted,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          enabled: enabled,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            // The comma is allowed through, not stripped. Keyboards in locales
            // that use a decimal comma put one on the decimal key, and
            // filtering it out silently turned "70,5" into "705".
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          ],
          decoration: InputDecoration(
            suffixText: suffix,
            filled: true,
            fillColor: palette.surfaceHigh,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: palette.stroke),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: palette.stroke),
            ),
          ),
        ),
      ],
    );
  }
}
