import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../shared/widgets/liquid_glass.dart';

/// The controls a Pulse screen floats over its canvas, shared between the
/// composer and the share screens so the three read as one place: the text
/// tool and the backdrop wheel down the right edge, and the Share pill.

/// The way into the text tool from the top bar: "Aa", as every story
/// composer draws it.
class PulseTextToolButton extends StatelessWidget {
  const PulseTextToolButton({required this.onTap, super.key});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      tooltip: 'Add text',
      icon: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0x66000000),
          border: Border.all(color: const Color(0x4DFFFFFF)),
        ),
        child: const Text(
          'Aa',
          style: TextStyle(
            color: AppColors.onMedia,
            fontSize: 14,
            fontWeight: FontWeight.w800,
            height: 1,
          ),
        ),
      ),
    );
  }
}

/// Sits under "Aa" on a text card and walks the backdrop through the set.
///
/// Filled with a colour wheel rather than the current gradient: the card
/// behind it is already showing what is picked, and a swatch that matched it
/// would vanish into it. The wheel says what the tap does — change the colour
/// — which is the only thing the button needs to say.
class PulseBackgroundButton extends StatelessWidget {
  const PulseBackgroundButton({required this.onTap, super.key});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      tooltip: 'Change background',
      icon: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0x4DFFFFFF)),
          gradient: const SweepGradient(
            colors: [
              Color(0xFFFF6B1A),
              Color(0xFFFFD166),
              Color(0xFF3DDC97),
              Color(0xFF3A86FF),
              Color(0xFF9B5DE5),
              Color(0xFFFF4D6D),
              Color(0xFFFF6B1A),
            ],
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x40000000),
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        // A dark centre turns the disc into a ring: it reads as a wheel to
        // spin rather than a flat rainbow badge.
        child: Center(
          child: Container(
            width: 14,
            height: 14,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xCC000000),
            ),
          ),
        ),
      ),
    );
  }
}

/// The one thing a Pulse screen exists to do, drawn the same on every one
/// of them: the composer, and the share screens for a post and a track.
///
/// A small pill of the app's glass rather than a slab of brand orange: it
/// sits over the canvas as a control, and the canvas is the point. The orange
/// is kept for the bolt and the word, which is enough to say "go" over any
/// photo; while there is nothing to send the pill goes smoked and the accent
/// dims.
class PulseShareButton extends StatefulWidget {
  const PulseShareButton({required this.onPressed, super.key});

  /// Null while the Pulse is not ready to go out.
  final VoidCallback? onPressed;

  static const double _height = 40;
  static const BorderRadius _radius =
      BorderRadius.all(Radius.circular(_height / 2));

  @override
  State<PulseShareButton> createState() => _PulseShareButtonState();
}

class _PulseShareButtonState extends State<PulseShareButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final accent = enabled ? AppColors.orangeBright : AppColors.onMediaMuted;

    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Share Pulse',
      child: GestureDetector(
        onTap: widget.onPressed,
        onTapDown: enabled ? (_) => _setPressed(true) : null,
        onTapCancel: () => _setPressed(false),
        onTapUp: (_) => _setPressed(false),
        child: AnimatedScale(
          scale: _pressed ? 0.95 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: LiquidGlass(
            borderRadius: PulseShareButton._radius,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              height: PulseShareButton._height,
              padding: const EdgeInsets.fromLTRB(14, 0, 18, 0),
              decoration: BoxDecoration(
                borderRadius: PulseShareButton._radius,
                // A lit hairline is what gives the glass an edge over a
                // photo; it dims with the accent when there is nothing to send.
                border: Border.all(
                  color: enabled
                      ? AppColors.onMedia.withValues(alpha: 0.32)
                      : AppColors.onMedia.withValues(alpha: 0.14),
                ),
                color: enabled ? null : const Color(0x66000000),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.bolt_rounded, size: 17, color: accent),
                  const SizedBox(width: 5),
                  Text(
                    'Share Pulse',
                    style: TextStyle(
                      color: enabled ? AppColors.onMedia : accent,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                    ),
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
