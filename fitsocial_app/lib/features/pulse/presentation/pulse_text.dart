import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../domain/pulse_text_style.dart';

/// Input styling with every scrap of Material chrome stripped off.
///
/// The app's global [InputDecorationTheme] fills its fields with a dark
/// surface and outlines them — orange once focused. That is right everywhere
/// else and completely wrong on a Pulse, where the text sits directly on the
/// photo or gradient with nothing around it. Setting `border` alone does not
/// undo it: a theme's `enabledBorder` and `focusedBorder` take precedence over
/// `border`, and `filled` has to be turned off by name. Hence all of it,
/// explicitly.
InputDecoration barePulseInput({String? hintText, TextStyle? hintStyle}) {
  return InputDecoration(
    filled: false,
    isCollapsed: true,
    contentPadding: EdgeInsets.zero,
    counterText: '',
    hintText: hintText,
    hintStyle: hintStyle,
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
    disabledBorder: InputBorder.none,
    errorBorder: InputBorder.none,
    focusedErrorBorder: InputBorder.none,
  );
}

/// Type scale for a written Pulse: big and loud when short, stepping down as
/// the message runs long so it always fits the frame.
double pulseTextSize(String text) {
  final length = text.trim().length;
  if (length > 200) return 20;
  if (length > 120) return 24;
  if (length > 60) return 30;
  if (length > 24) return 36;
  return 44;
}

/// A caption over a photo or clip.
///
/// Shared by the composer and the player so what someone writes is positioned
/// and weighted identically in both — no surprise on publish.
class PulseCaption extends StatelessWidget {
  const PulseCaption({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      // A black plate over the user's photo, in both themes — so what sits on
      // it is fixed too.
      decoration: BoxDecoration(
        color: const Color(0x99000000),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: AppColors.onMedia,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          height: 1.3,
        ),
      ),
    );
  }
}

/// The rounding on a text plate, relative to the type it holds.
double pulsePlateRadius(double fontSize) => fontSize * 0.28;

/// Padding inside a text plate, relative to the type it holds.
EdgeInsets pulsePlatePadding(double fontSize) => EdgeInsets.symmetric(
      horizontal: fontSize * 0.4,
      vertical: fontSize * 0.22,
    );

/// The widest a block of Pulse text may run inside a frame of [frameWidth].
double pulseTextMaxWidth(double frameWidth) => frameWidth - AppSpacing.lg * 2;

/// How wide [text] actually is when wrapped at [maxWidth]: its longest line.
///
/// Needed because a centred or right-aligned paragraph reports the whole
/// width it was offered as its own, so that the alignment has room to act —
/// which leaves a plate drawn round it spanning the screen. This measures the
/// lines themselves, with the same style and wrap width the paragraph will
/// lay out with, so the two agree.
double pulseTextContentWidth({
  required String text,
  required TextStyle style,
  required TextAlign textAlign,
  required TextDirection textDirection,
  required TextScaler textScaler,
  required double maxWidth,
}) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textAlign: textAlign,
    textDirection: textDirection,
    textScaler: textScaler,
  )..layout(maxWidth: maxWidth);
  var longest = 0.0;
  for (final line in painter.computeLineMetrics()) {
    if (line.width > longest) longest = line.width;
  }
  painter.dispose();
  // Half a pixel of slack for the rounding between measuring and laying out,
  // without which a line can wrap on its own last glyph.
  return (longest + 0.5).clamp(0.0, maxWidth);
}

/// A block of styled Pulse text: the letters in their face and colour, on
/// their plate if they have one. Nothing about *where* it sits — that is
/// [PulseTextLayer]'s job.
///
/// Shared by the composer's sticker, the photo rasteriser and the viewer, so
/// what someone wrote is drawn identically everywhere it appears.
class PulseTextBlock extends StatelessWidget {
  const PulseTextBlock({
    required this.text,
    required this.style,
    this.maxWidth,
    super.key,
  });

  final String text;
  final PulseTextStyle style;

  /// The widest the block may run before wrapping. Null lets the parent
  /// decide.
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final resolved = style.resolve(pulseTextSize(text));
    final fontSize = resolved.fontSize!;
    final plate = style.plate;
    final padding =
        plate == null ? EdgeInsets.zero : pulsePlatePadding(fontSize);

    Widget block = Text(
      text,
      textAlign: style.alignment.textAlign,
      style: resolved,
    );

    // Sized to the words, so a plate hugs them; see pulseTextContentWidth.
    final width = maxWidth;
    if (width != null) {
      block = SizedBox(
        width: pulseTextContentWidth(
          text: text,
          style: resolved,
          textAlign: style.alignment.textAlign,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxWidth: width - padding.horizontal,
        ),
        child: block,
      );
    }

    if (plate != null) {
      block = DecoratedBox(
        decoration: BoxDecoration(
          color: plate,
          borderRadius: BorderRadius.circular(pulsePlateRadius(fontSize)),
        ),
        child: Padding(padding: padding, child: block),
      );
    }
    return block;
  }
}

/// [PulseTextBlock], set down in a frame where its style says.
///
/// The frame is whatever this is given to fill — the composer's canvas or the
/// viewer's page — and the placement is read as fractions of it, so the same
/// style puts the text in the same place on both.
class PulseTextLayer extends StatelessWidget {
  const PulseTextLayer({
    required this.text,
    required this.style,
    this.child,
    super.key,
  });

  final String text;
  final PulseTextStyle style;

  /// Something to wrap the block in — the composer wraps it in its gesture
  /// handling, which needs the frame's size to turn finger travel into
  /// fractions. Applied inside the placement, so a wrapper moves with the
  /// text.
  final Widget Function(Widget block, Size frame)? child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final frame = constraints.biggest;
        Widget block = PulseTextBlock(
          text: text,
          style: style,
          maxWidth: pulseTextMaxWidth(frame.width),
        );
        final wrap = child;
        if (wrap != null) block = wrap(block, frame);

        return Center(
          child: Transform.translate(
            offset: Offset(
              (style.x - 0.5) * frame.width,
              (style.y - 0.5) * frame.height,
            ),
            child: Transform.rotate(angle: style.rotation, child: block),
          ),
        );
      },
    );
  }
}
