import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../app/theme/app_palette.dart';
import '../../features/main/domain/muscle_heat.dart';

export '../../features/main/domain/muscle_heat.dart' show HeatScale;

/// Which side of the body to draw.
enum BodySides { front, back, both }

/// The fill for a heat [level], from tokens so both themes work: the empty
/// level sits just off the surface, and each step moves towards the brand,
/// then past it — lighter on dark, deeper on cream.
Color heatColor(int level, AppPalette p) => switch (level) {
      <= 0 => Color.alphaBlend(
          p.overlay.withValues(alpha: p.isDark ? 0.06 : 0.08),
          p.surfaceHigh,
        ),
      1 => Color.lerp(p.surfaceHigh, p.brand, 0.22)!,
      2 => Color.lerp(p.surfaceHigh, p.brand, 0.55)!,
      3 => p.brand,
      _ => p.isDark
          ? Color.lerp(p.brand, const Color(0xFFFFFFFF), 0.45)!
          : Color.lerp(p.brand, const Color(0xFF1A120B), 0.35)!,
    };

/// One shape on the figure. [muscle] is null for the parts that are not
/// painted — head, neck, hands, knees, feet.
class BodyRegion {
  const BodyRegion(this.muscle, this.path);

  final String? muscle;
  final Path path;
}

/// The figure, front and back, in a 160 × 330 box.
///
/// Original geometric artwork — pills and rounded rectangles, not a trace of
/// any anatomy illustration. A detailed figure later needs commissioned art or
/// a CC0 source with its licence recorded in the repo.
class BodyMapGeometry {
  const BodyMapGeometry._();

  static const Size box = Size(160, 330);

  static Path _ellipse(double cx, double cy, double rx, double ry) => Path()
    ..addOval(Rect.fromCenter(
      center: Offset(cx, cy),
      width: rx * 2,
      height: ry * 2,
    ));

  static Path _circle(double cx, double cy, double r) => _ellipse(cx, cy, r, r);

  static Path _rrect(double x, double y, double w, double h, double r) => Path()
    ..addRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(x, y, w, h),
      Radius.circular(r),
    ));

  static List<BodyRegion> _frame() => [
        BodyRegion(null, _circle(80, 22, 15)),
        BodyRegion(null, _rrect(73, 36, 14, 12, 4)),
        BodyRegion(null, _circle(27, 170, 6)),
        BodyRegion(null, _circle(133, 170, 6)),
        BodyRegion(null, _circle(66, 240, 7)),
        BodyRegion(null, _circle(94, 240, 7)),
        BodyRegion(null, _ellipse(64, 318, 9, 5)),
        BodyRegion(null, _ellipse(96, 318, 9, 5)),
        BodyRegion('forearms', _ellipse(31, 137, 7, 20)),
        BodyRegion('forearms', _ellipse(129, 137, 7, 20)),
      ];

  /// In paint order; hit-testing walks it backwards.
  static final List<BodyRegion> front = [
    ..._frame(),
    BodyRegion(null, _rrect(60, 150, 40, 16, 8)),
    BodyRegion('shoulders', _ellipse(46, 62, 13, 11)),
    BodyRegion('shoulders', _ellipse(114, 62, 13, 11)),
    BodyRegion('chest', _rrect(54, 52, 25, 30, 9)),
    BodyRegion('chest', _rrect(81, 52, 25, 30, 9)),
    BodyRegion('biceps', _ellipse(38, 96, 8, 18)),
    BodyRegion('biceps', _ellipse(122, 96, 8, 18)),
    BodyRegion('core', _rrect(62, 86, 36, 60, 10)),
    BodyRegion('quads', _ellipse(68, 200, 12, 34)),
    BodyRegion('quads', _ellipse(92, 200, 12, 34)),
    BodyRegion('calves', _ellipse(65, 277, 8, 30)),
    BodyRegion('calves', _ellipse(95, 277, 8, 30)),
  ];

  static final List<BodyRegion> back = [
    ..._frame(),
    BodyRegion(
      'back',
      Path()
        ..moveTo(66, 44)
        ..lineTo(94, 44)
        ..lineTo(108, 58)
        ..lineTo(52, 58)
        ..close(),
    ),
    BodyRegion('back', _rrect(52, 60, 56, 52, 14)),
    BodyRegion('back', _rrect(64, 114, 32, 32, 8)),
    BodyRegion('shoulders', _ellipse(44, 62, 12, 11)),
    BodyRegion('shoulders', _ellipse(116, 62, 12, 11)),
    BodyRegion('triceps', _ellipse(38, 96, 8, 18)),
    BodyRegion('triceps', _ellipse(122, 96, 8, 18)),
    BodyRegion('glutes', _ellipse(70, 162, 12, 13)),
    BodyRegion('glutes', _ellipse(90, 162, 12, 13)),
    BodyRegion('hamstrings', _ellipse(68, 208, 11, 28)),
    BodyRegion('hamstrings', _ellipse(92, 208, 11, 28)),
    BodyRegion('calves', _ellipse(65, 278, 10, 30)),
    BodyRegion('calves', _ellipse(95, 278, 10, 30)),
  ];

  /// The muscle under [point], in box coordinates, or null for empty space
  /// and the unpainted parts.
  static String? hitTest(List<BodyRegion> regions, Offset point) {
    for (final region in regions.reversed) {
      if (region.path.contains(point)) return region.muscle;
    }
    return null;
  }
}

/// A front and back body figure, each muscle group shaded by its sets.
///
/// Static when [onTap] is null (cards, the exported image); otherwise a tap
/// on a muscle calls [onTap] with its group.
class MuscleHeatmap extends StatefulWidget {
  const MuscleHeatmap({
    required this.sets,
    required this.scale,
    this.sides = BodySides.both,
    this.selected,
    this.onTap,
    this.height = 330,
    this.forceDarkPalette = false,
    this.valueLabel,
    super.key,
  });

  /// Muscle group → credited sets (sets a week, averaged, for 30 days).
  final Map<String, double> sets;
  final HeatScale scale;
  final BodySides sides;
  final String? selected;
  final ValueChanged<String>? onTap;

  /// The figure's height; each side is drawn 160:330.
  final double height;

  /// Dark colours whatever the theme, for a card over a photo — a photo looks
  /// the same in both themes.
  final bool forceDarkPalette;

  /// What a number is, for screen readers: "sets this week". Defaults by
  /// [scale].
  final String? valueLabel;

  @override
  State<MuscleHeatmap> createState() => _MuscleHeatmapState();
}

class _MuscleHeatmapState extends State<MuscleHeatmap>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
    value: 1,
  );

  /// The fills being faded from, per muscle.
  Map<String, Color> _from = const {};

  /// The fills last drawn, so a change fades from where it was.
  Map<String, Color> _shown = const {};

  @override
  void didUpdateWidget(MuscleHeatmap old) {
    super.didUpdateWidget(old);
    if (!_sameSets(old.sets, widget.sets) || old.scale != widget.scale) {
      _from = _shown;
      if (MediaQuery.disableAnimationsOf(context)) {
        _fade.value = 1;
      } else {
        _fade.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  static bool _sameSets(Map<String, double> a, Map<String, double> b) {
    if (a.length != b.length) return false;
    for (final MapEntry(:key, :value) in a.entries) {
      if (b[key] != value) return false;
    }
    return true;
  }

  String _describe(String muscle) {
    final n = widget.sets[muscle] ?? 0;
    final unit = widget.valueLabel ??
        (widget.scale == HeatScale.weekly
            ? 'sets this week'
            : 'sets this workout');
    final status = widget.scale == HeatScale.weekly
        ? switch (targetStatus(n)) {
            TargetStatus.under => '',
            TargetStatus.inTarget => ', in target',
            TargetStatus.above => ', above target',
          }
        : '';
    return '${muscleLabel(muscle)}, ${formatSets(n)} $unit$status';
  }

  String _summary() {
    final trained = [
      for (final m in paintedMuscles)
        if ((widget.sets[m] ?? 0) > 0) m,
    ]..sort((a, b) => widget.sets[b]!.compareTo(widget.sets[a]!));
    if (trained.isEmpty) return 'Body map: no muscles trained';
    final most = trained.take(3).join(', ');
    final least = trained.length > 3
        ? '. Least trained: ${trained.reversed.take(2).join(', ')}'
        : '';
    return 'Body map. Most trained: $most$least';
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.forceDarkPalette ? AppPalette.dark : context.palette;
    final target = {
      for (final m in paintedMuscles)
        m: heatColor(heatLevel(widget.sets[m] ?? 0, widget.scale), palette),
    };
    final width =
        widget.height * BodyMapGeometry.box.width / BodyMapGeometry.box.height;

    Widget figure(List<BodyRegion> regions) {
      final paint = AnimatedBuilder(
        animation: _fade,
        builder: (context, _) {
          final t = Curves.easeOut.transform(_fade.value);
          final colors = {
            for (final MapEntry(:key, :value) in target.entries)
              key: Color.lerp(_from[key] ?? value, value, t)!,
          };
          _shown = colors;
          return CustomPaint(
            size: Size(width, widget.height),
            painter: _BodyPainter(
              regions: regions,
              colors: colors,
              base: palette.surface,
              stroke: palette.stroke,
              selectedStroke: palette.text,
              selected: widget.selected,
              describe: _describe,
              onTap: widget.onTap,
            ),
          );
        },
      );
      final onTap = widget.onTap;
      if (onTap == null) return paint;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (details) {
          final scale = widget.height / BodyMapGeometry.box.height;
          final hit = BodyMapGeometry.hitTest(
            regions,
            details.localPosition / scale,
          );
          if (hit != null) onTap(hit);
        },
        child: paint,
      );
    }

    Widget labelled(String label, List<BodyRegion> regions) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            figure(regions),
            const SizedBox(height: 6),
            ExcludeSemantics(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  color: palette.muted,
                ),
              ),
            ),
          ],
        );

    final body = switch (widget.sides) {
      BodySides.front => figure(BodyMapGeometry.front),
      BodySides.back => figure(BodyMapGeometry.back),
      BodySides.both => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            labelled('FRONT', BodyMapGeometry.front),
            SizedBox(width: widget.height * 0.06),
            labelled('BACK', BodyMapGeometry.back),
          ],
        ),
    };
    return Semantics(container: true, label: _summary(), child: body);
  }
}

/// "7.5", "14".
String formatSets(double sets) {
  final rounded = (sets * 10).round() / 10;
  return rounded == rounded.roundToDouble()
      ? '${rounded.round()}'
      : rounded.toStringAsFixed(1);
}

class _BodyPainter extends CustomPainter {
  _BodyPainter({
    required this.regions,
    required this.colors,
    required this.base,
    required this.stroke,
    required this.selectedStroke,
    required this.selected,
    required this.describe,
    required this.onTap,
  });

  final List<BodyRegion> regions;
  final Map<String, Color> colors;
  final Color base;
  final Color stroke;
  final Color selectedStroke;
  final String? selected;
  final String Function(String muscle) describe;
  final ValueChanged<String>? onTap;

  double _scale(Size size) => size.height / BodyMapGeometry.box.height;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = _scale(size);
    canvas.save();
    canvas.scale(scale);
    final fill = Paint()..style = PaintingStyle.fill;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1 / scale
      ..color = stroke;
    for (final region in regions) {
      fill.color = region.muscle == null ? base : colors[region.muscle] ?? base;
      canvas.drawPath(region.path, fill);
      canvas.drawPath(region.path, line);
    }
    // The selection last, so no neighbour paints over its outline.
    if (selected != null) {
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5 / scale
        ..color = selectedStroke;
      for (final region in regions) {
        if (region.muscle == selected) canvas.drawPath(region.path, ring);
      }
    }
    canvas.restore();
  }

  /// One node per muscle on this side, covering all its shapes, so a screen
  /// reader can find and read each one without seeing colour.
  @override
  SemanticsBuilderCallback get semanticsBuilder => (size) {
        final scale = _scale(size);
        final bounds = <String, Rect>{};
        for (final region in regions) {
          final muscle = region.muscle;
          if (muscle == null) continue;
          final rect = region.path.getBounds();
          bounds[muscle] = bounds[muscle]?.expandToInclude(rect) ?? rect;
        }
        return [
          for (final MapEntry(key: muscle, value: rect) in bounds.entries)
            CustomPainterSemantics(
              key: ValueKey('muscle-$muscle'),
              rect: Rect.fromLTRB(
                rect.left * scale,
                rect.top * scale,
                rect.right * scale,
                rect.bottom * scale,
              ),
              properties: SemanticsProperties(
                label: describe(muscle),
                selected: muscle == selected,
                button: onTap != null,
                onTap: onTap == null ? null : () => onTap!(muscle),
                textDirection: TextDirection.ltr,
              ),
            ),
        ];
      };

  @override
  bool shouldRepaint(_BodyPainter old) =>
      old.selected != selected ||
      old.base != base ||
      old.stroke != stroke ||
      !_sameColors(old.colors, colors);

  /// The labels carry the numbers, which can change within a shade.
  @override
  bool shouldRebuildSemantics(_BodyPainter old) => true;

  static bool _sameColors(Map<String, Color> a, Map<String, Color> b) {
    if (a.length != b.length) return false;
    for (final MapEntry(:key, :value) in a.entries) {
      if (b[key] != value) return false;
    }
    return true;
  }
}
