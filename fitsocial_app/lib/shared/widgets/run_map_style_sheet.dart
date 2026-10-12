import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_palette.dart';
import '../../app/theme/app_spacing.dart';
import 'liquid_glass.dart';
import 'run_map_style.dart';
import 'run_route_map.dart';

/// Opens the sheet where the runner picks how run maps look.
///
/// Changes apply as they are tapped — the map behind the sheet restyles while
/// it is still open — so there is no save button to forget.
Future<void> showRunMapStyleSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _RunMapStyleSheet(),
  );
}

/// The round "layers" control that opens [showRunMapStyleSheet], made of the
/// same plate as everything else floating on a map.
class RunMapStyleButton extends StatelessWidget {
  const RunMapStyleButton({this.size = 36, this.iconSize = 18, super.key});

  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Tooltip(
      message: 'Map style',
      child: Material(
        color: RunMapPlate.fill(context),
        shape: CircleBorder(
          side: BorderSide(color: palette.stroke.withValues(alpha: 0.6)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => showRunMapStyleSheet(context),
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(
              Icons.layers_rounded,
              size: iconSize,
              color: palette.text,
            ),
          ),
        ),
      ),
    );
  }
}

class _RunMapStyleSheet extends StatelessWidget {
  const _RunMapStyleSheet();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return SafeArea(
      top: false,
      child: LiquidGlass(
        // Painted rather than a lens: the sheet usually opens over a map, a
        // platform view with no backdrop for a lens to bend.
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: ValueListenableBuilder<RunMapPrefs>(
          valueListenable: RunMapPrefs.current,
          builder: (context, prefs, _) => Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              12,
              AppSpacing.md,
              AppSpacing.md,
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
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Map style',
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: AppSpacing.sm,
                  crossAxisSpacing: AppSpacing.sm,
                  childAspectRatio: 0.82,
                  children: [
                    for (final style in RunMapStyle.values)
                      _StyleTile(
                        style: style,
                        selected: prefs.style == style,
                        onTap: () =>
                            RunMapPrefs.save(prefs.copyWith(style: style)),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                _Toggle(
                  title: 'Colour route by pace',
                  subtitle: 'Yellow where you were fast, red where you '
                      'slowed. Shows on runs recorded from now on.',
                  value: prefs.paceColours,
                  onChanged: (value) =>
                      RunMapPrefs.save(prefs.copyWith(paceColours: value)),
                ),
                _Toggle(
                  title: '3D follow camera',
                  subtitle: 'On a live run the map tilts and turns the way '
                      'you are heading.',
                  value: prefs.tilt3d,
                  onChanged: (value) =>
                      RunMapPrefs.save(prefs.copyWith(tilt3d: value)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StyleTile extends StatelessWidget {
  const _StyleTile({
    required this.style,
    required this.selected,
    required this.onTap,
  });

  final RunMapStyle style;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final shown = style.resolve(appIsDark: palette.isDark);

    return Semantics(
      button: true,
      selected: selected,
      label: '${style.label} map style. ${style.blurb}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected ? AppColors.orangeBright : palette.stroke,
                    width: selected ? 2 : 1,
                  ),
                ),
                padding: const EdgeInsets.all(2),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: CustomPaint(
                    painter:
                        _SwatchPainter(shown, auto: style == RunMapStyle.auto),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              style.label,
              style: TextStyle(
                color: selected ? AppColors.orangeBright : palette.text,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A thumbnail of a style: its ground, a few streets, a park or the sea, and
/// the route across it — enough to tell the styles apart at a glance without a
/// live map per tile.
class _SwatchPainter extends CustomPainter {
  _SwatchPainter(this.style, {required this.auto});

  /// Already resolved, so never [RunMapStyle.auto].
  final RunMapStyle style;

  /// Whether the tile stands for Auto, which gets a split ground — half dark,
  /// half light — to say it follows the theme.
  final bool auto;

  @override
  void paint(Canvas canvas, Size size) {
    final (ground, road, park, water) = switch (style) {
      RunMapStyle.midnight => (
          const Color(0xFF0A0A0A),
          const Color(0xFF2B2B2B),
          const Color(0xFF0D1A10),
          const Color(0xFF0A1820),
        ),
      RunMapStyle.ember => (
          const Color(0xFF140B07),
          const Color(0xFF5A2E14),
          const Color(0xFF1A1A0B),
          const Color(0xFF07090D),
        ),
      RunMapStyle.paper => (
          const Color(0xFFEFEAE1),
          const Color(0xFFFFFFFF),
          const Color(0xFFE2E8D5),
          const Color(0xFFCFDFE4),
        ),
      RunMapStyle.satellite => (
          const Color(0xFF3B4A2C),
          const Color(0xFF9A968C),
          const Color(0xFF2C3D1F),
          const Color(0xFF1E3442),
        ),
      RunMapStyle.terrain => (
          const Color(0xFFE8E4D3),
          const Color(0xFFFFFFFF),
          const Color(0xFFC6DDB0),
          const Color(0xFFA8CBE0),
        ),
      RunMapStyle.auto => throw StateError('Swatch takes a resolved style'),
    };

    final w = size.width;
    final h = size.height;
    canvas.drawRect(Offset.zero & size, Paint()..color = ground);
    if (auto) {
      canvas.drawPath(
        Path()
          ..moveTo(w, 0)
          ..lineTo(w, h)
          ..lineTo(0, h)
          ..close(),
        Paint()
          ..color = style == RunMapStyle.midnight
              ? const Color(0xFFEFEAE1)
              : const Color(0xFF0A0A0A),
      );
    }

    if (style == RunMapStyle.satellite) {
      // Fields and rooftops: a patchwork, the way imagery reads from above.
      final patch = Paint()..color = const Color(0xFF55603C);
      canvas
        ..drawRect(Rect.fromLTWH(w * 0.05, h * 0.55, w * 0.3, h * 0.2), patch)
        ..drawRect(Rect.fromLTWH(w * 0.6, h * 0.08, w * 0.3, h * 0.22), patch);
    }
    canvas
      ..drawOval(
        Rect.fromLTWH(w * 0.55, h * 0.55, w * 0.55, h * 0.5),
        Paint()..color = park,
      )
      ..drawRect(
          Rect.fromLTWH(0, 0, w * 0.28, h * 0.32), Paint()..color = water);

    final roadPaint = Paint()
      ..color = road
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    canvas
      ..drawLine(Offset(0, h * 0.42), Offset(w, h * 0.36), roadPaint)
      ..drawLine(Offset(w * 0.42, 0), Offset(w * 0.5, h), roadPaint)
      ..drawLine(
          Offset(w * 0.1, h), Offset(w, h * 0.7), roadPaint..strokeWidth = 2);

    final route = Path()
      ..moveTo(w * 0.15, h * 0.82)
      ..cubicTo(w * 0.3, h * 0.45, w * 0.55, h * 0.75, w * 0.85, h * 0.22);
    if (style.isDarkGround) {
      canvas.drawPath(
        route,
        Paint()
          ..color = AppColors.orangeBright.withValues(alpha: 0.3)
          ..strokeWidth = 8
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke,
      );
    }
    canvas.drawPath(
      route,
      Paint()
        ..color = style.isDarkGround ? AppColors.orangeBright : AppColors.orange
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_SwatchPainter old) =>
      old.style != style || old.auto != auto;
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: value,
      onChanged: onChanged,
      activeThumbColor: AppColors.onBrand,
      activeTrackColor: AppColors.orangeBright,
      title: Text(
        title,
        style: TextStyle(color: palette.text, fontWeight: FontWeight.w700),
      ),
      subtitle: Text(subtitle, style: TextStyle(color: palette.muted)),
    );
  }
}
