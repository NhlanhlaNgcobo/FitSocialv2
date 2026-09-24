import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/app_palette.dart';

/// A full-screen 3 · 2 · 1 · GO before an activity starts recording.
///
/// Resolves true once GO has shown, false if the person tapped to cancel — the
/// phone goes into a pocket or an armband during these seconds, and changing
/// your mind should cost nothing.
Future<bool> showStartCountdown(BuildContext context, {int seconds = 3}) async {
  final started = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.82),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (_, __, ___) => _StartCountdown(seconds: seconds),
  );
  return started ?? false;
}

class _StartCountdown extends StatefulWidget {
  const _StartCountdown({required this.seconds});

  final int seconds;

  @override
  State<_StartCountdown> createState() => _StartCountdownState();
}

class _StartCountdownState extends State<_StartCountdown>
    with SingleTickerProviderStateMixin {
  late int _remaining = widget.seconds;
  Timer? _timer;

  /// Replays the pop on every tick.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_remaining == 0) {
        _timer?.cancel();
        Navigator.of(context).pop(true);
        return;
      }
      setState(() => _remaining--);
      _tick();
    });
  }

  void _tick() {
    _pulse.forward(from: 0);
    // A heavier thump on GO, so it can be felt through a pocket.
    if (_remaining == 0) {
      HapticFeedback.heavyImpact();
    } else {
      HapticFeedback.selectionClick();
    }
  }

  void _cancel() {
    _timer?.cancel();
    Navigator.of(context).pop(false);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final label = _remaining == 0 ? 'GO' : '$_remaining';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _cancel,
      child: Material(
        type: MaterialType.transparency,
        child: SafeArea(
          child: Stack(
            children: [
              Center(
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, _) {
                    final t = Curves.easeOutCubic.transform(_pulse.value);
                    return Opacity(
                      opacity: (1.4 - t).clamp(0.0, 1.0),
                      child: Transform.scale(
                        scale: 1.35 - 0.35 * t,
                        child: Text(
                          label,
                          style: TextStyle(
                            color: _remaining == 0
                                ? palette.brand
                                : Colors.white,
                            fontSize: 140,
                            fontWeight: FontWeight.w900,
                            height: 1,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: EdgeInsets.only(bottom: 32),
                  child: Text(
                    'Tap anywhere to cancel',
                    style: TextStyle(color: Colors.white70, fontSize: 13.5),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
