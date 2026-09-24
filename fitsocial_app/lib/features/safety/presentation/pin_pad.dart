import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/app_palette.dart';
import '../domain/panic_pins.dart';

/// A four-digit PIN entry: dots above a numeric keypad.
///
/// Its own keypad rather than a text field with the system keyboard. The
/// keyboard slides up over half the screen, differs between phones, and on
/// the panic screen would push the alert status out of view at the moment it
/// matters. Big targets, in the same place every time.
///
/// Calls [onComplete] with the four digits and clears itself. Bumping
/// [shakeSignal] plays a short shake: the panic screen bumps it on every
/// wrong PIN, which is the whole of the feedback a wrong PIN gets.
class PinPad extends StatefulWidget {
  const PinPad({
    required this.onComplete,
    this.shakeSignal = 0,
    this.foreground,
    this.enabled = true,
    super.key,
  });

  final ValueChanged<String> onComplete;
  final int shakeSignal;

  /// Digit and dot colour. Defaults to the palette's text colour.
  final Color? foreground;
  final bool enabled;

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> with SingleTickerProviderStateMixin {
  String _digits = '';
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );

  @override
  void didUpdateWidget(covariant PinPad oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.shakeSignal != oldWidget.shakeSignal) _shake.forward(from: 0);
  }

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  void _press(String digit) {
    if (!widget.enabled || _digits.length >= 4) return;
    HapticFeedback.selectionClick();
    setState(() => _digits += digit);
    if (_digits.length == 4) {
      final pin = _digits;
      // Cleared first, so a rebuild triggered by the callback shows an empty
      // row ready for the next attempt.
      setState(() => _digits = '');
      widget.onComplete(pin);
    }
  }

  void _backspace() {
    if (_digits.isEmpty) return;
    setState(() => _digits = _digits.substring(0, _digits.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final fg = widget.foreground ?? context.palette.text;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _shake,
          builder: (context, child) => Transform.translate(
            offset: Offset(
                math.sin(_shake.value * math.pi * 6) * 12 * (1 - _shake.value),
                0),
            child: child,
          ),
          child: Semantics(
            label: '${_digits.length} of 4 digits entered',
            liveRegion: true,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 4; i++)
                  Container(
                    width: 16,
                    height: 16,
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < _digits.length ? fg : Colors.transparent,
                      border: Border.all(color: fg, width: 2),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
          ['', '0', '<'],
        ])
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final key in row)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: key.isEmpty
                      ? const SizedBox(width: 72, height: 72)
                      : _Key(
                          label: key,
                          foreground: fg,
                          enabled: widget.enabled,
                          onTap: key == '<' ? _backspace : () => _press(key),
                        ),
                ),
            ],
          ),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({
    required this.label,
    required this.foreground,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final Color foreground;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isBack = label == '<';
    return Semantics(
      button: true,
      label: isBack ? 'Delete' : label,
      child: Material(
        color: foreground.withValues(alpha: isBack ? 0 : 0.10),
        shape: CircleBorder(
          side: BorderSide(color: foreground.withValues(alpha: 0.25)),
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? onTap : null,
          child: SizedBox(
            width: 72,
            height: 72,
            child: Center(
              child: isBack
                  ? Icon(Icons.backspace_outlined, color: foreground, size: 24)
                  : Text(
                      label,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 28,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Human wording for a refused PIN pair at setup.
String pinSetupErrorText(PinSetupError error) {
  switch (error) {
    case PinSetupError.safeNotFourDigits:
    case PinSetupError.duressNotFourDigits:
      return 'Use four digits.';
    case PinSetupError.safeConfirmationMismatch:
    case PinSetupError.duressConfirmationMismatch:
      return "Those didn't match. Try again.";
    case PinSetupError.duressSameAsSafe:
      return 'Must differ from your safe PIN.';
  }
}
