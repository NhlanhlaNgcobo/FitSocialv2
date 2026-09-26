import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../application/panic_controller.dart';
import '../application/safety_providers.dart';

/// How long the button has to be held. Long enough that a pocket or a
/// careless thumb will not send an alert; short enough to do under stress.
const Duration holdToAlertDuration = Duration(seconds: 2);

/// Press and hold to send a silent alert.
///
/// A ring fills while the finger stays down; letting go early cancels with
/// nothing sent. On completion one firm vibration confirms it, the alert goes
/// out, and the alert screen opens.
///
/// [compact] is a plain icon for an app bar — the live run screen — where a
/// large red button would draw exactly the attention the alert is silent to
/// avoid. The full-size version is for the Safety screen.
class HoldToAlertButton extends ConsumerStatefulWidget {
  const HoldToAlertButton({this.compact = false, super.key});

  final bool compact;

  @override
  ConsumerState<HoldToAlertButton> createState() => _HoldToAlertButtonState();
}

class _HoldToAlertButtonState extends ConsumerState<HoldToAlertButton>
    with SingleTickerProviderStateMixin {
  // Deliberately not branched on reduce-motion: this ring is the hold's
  // progress, not a decoration of it — the two seconds it takes to fill *is*
  // the safeguard against a pocket or a careless thumb. Shortening or
  // simplifying it would remove information, not motion for its own sake.
  late final AnimationController _hold = AnimationController(
    vsync: this,
    duration: holdToAlertDuration,
  )..addStatusListener((status) {
      if (status == AnimationStatus.completed) _send();
    });

  @override
  void dispose() {
    _hold.dispose();
    super.dispose();
  }

  void _down() {
    final phase = ref.read(panicControllerProvider).phase;
    // An alert already running: a tap just shows it, no second alert.
    if (phase == PanicPhase.active || phase == PanicPhase.dispatching) {
      context.push('/safety/panic');
      return;
    }
    HapticFeedback.selectionClick();
    _hold.forward(from: 0);
  }

  void _up() {
    if (_hold.isAnimating && _hold.value < 1) _hold.reverse();
  }

  void _send() {
    HapticFeedback.heavyImpact();
    ref.read(panicControllerProvider.notifier).trigger();
    _hold.value = 0;
    context.push('/safety/panic');
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      button: true,
      label: 'Send silent alert. Press and hold for two seconds.',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _down(),
        onTapUp: (_) => _up(),
        onTapCancel: _up,
        child: AnimatedBuilder(
          animation: _hold,
          builder: (context, _) => widget.compact
              ? _Compact(progress: _hold.value, color: palette.text)
              : _Large(progress: _hold.value),
        ),
      ),
    );
  }
}

class _Compact extends StatelessWidget {
  const _Compact({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Hold to send alert',
      child: SizedBox(
        width: 44,
        height: 44,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (progress > 0)
              SizedBox(
                width: 34,
                height: 34,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 3,
                  color: color,
                ),
              ),
            Icon(Icons.shield_outlined, color: color, size: 22),
          ],
        ),
      ),
    );
  }
}

class _Large extends StatelessWidget {
  const _Large({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    const red = Color(0xFFB3261E);
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Stack(
        children: [
          Positioned.fill(child: Container(color: red)),
          // Fills left to right while held.
          Positioned.fill(
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: progress,
              child: Container(color: const Color(0xFF7A140F)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
            child: Center(
              child: Column(
                children: [
                  const Icon(Icons.sos_rounded, color: Colors.white, size: 48),
                  const SizedBox(height: AppSpacing.sm),
                  const Text(
                    'Send silent alert',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    progress > 0
                        ? 'Keep holding…'
                        : 'Press and hold for 2 seconds',
                    style: const TextStyle(color: Color(0xDDFFFFFF)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
