import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../application/panic_controller.dart';
import '../application/safety_providers.dart';
import 'pin_pad.dart';

/// The screen behind the panic button. Deliberately quiet.
///
/// A panic is silent: no siren, no flashing, no red. Anything that draws the
/// eye could push someone who wants to stay unnoticed into violence, so this
/// looks like any other page of the app. It says whether the alert went out
/// and who is responding, and offers the PIN to end it.
///
/// Leaving the screen does not end anything. The alert and the live location
/// carry on until the safe PIN — here, or under "I'm safe now" in Safety.
///
/// The ended screen is the same for the safe and the duress PIN, because the
/// controller hands this widget the same state for both. It never learns which
/// was typed.
class PanicScreen extends ConsumerStatefulWidget {
  const PanicScreen({super.key});

  @override
  ConsumerState<PanicScreen> createState() => _PanicScreenState();
}

class _PanicScreenState extends ConsumerState<PanicScreen> {
  bool _enteringPin = false;

  void _leave() {
    final controller = ref.read(panicControllerProvider.notifier);
    if (ref.read(panicControllerProvider).phase == PanicPhase.stopped) {
      controller.dismiss();
    }
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(panicControllerProvider);
    final controller = ref.read(panicControllerProvider.notifier);

    // Opened with nothing running — a stale route after a restart.
    if (state.phase == PanicPhase.idle) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && context.canPop()) context.pop();
      });
    }

    return PopScope(
      // Leaving is always allowed; it ends nothing. Only the ended screen is
      // reset on the way out, so the next press starts clean.
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && state.phase == PanicPhase.stopped) controller.dismiss();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Alert')),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: switch (state.phase) {
              PanicPhase.idle => const SizedBox.shrink(),
              PanicPhase.dispatching => const _Sending(),
              PanicPhase.active => _enteringPin || !state.requiresPin
                  ? _EndAlert(
                      state: state,
                      onPin: controller.submitPin,
                      onEndWithoutPin: controller.endWithoutPin,
                      onBack: () => setState(() => _enteringPin = false),
                    )
                  : _Sent(
                      state: state,
                      onEnd: () => setState(() => _enteringPin = true),
                      onClose: _leave,
                    ),
              PanicPhase.stopped => _Ended(onDone: _leave),
            },
          ),
        ),
      ),
    );
  }
}

class _Sending extends StatelessWidget {
  const _Sending();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Sending…',
            style: TextStyle(
              color: context.palette.text,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _Sent extends StatelessWidget {
  const _Sent({
    required this.state,
    required this.onEnd,
    required this.onClose,
  });

  final PanicState state;
  final VoidCallback onEnd;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final acks = state.acknowledgements;
    return ListView(
      children: [
        Semantics(
          liveRegion: true,
          child: Text(
            deliveryLine(state),
            style: TextStyle(
              color: palette.text,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (state.alertedContacts != 0 &&
            state.delivery != PanicDelivery.failed)
          Text(
            'Your location is shared with them until you end the alert.',
            style: TextStyle(color: palette.muted, fontSize: 15),
          ),
        const SizedBox(height: AppSpacing.lg),
        if (acks.isEmpty)
          Text(
            state.alertedContacts == 0 ? '' : 'Nobody has responded yet.',
            style: TextStyle(color: palette.muted),
          )
        else
          for (final ack in acks)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(Icons.directions_run_rounded, color: palette.success),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      '${ack.displayName} is responding',
                      style: TextStyle(
                        color: palette.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        const SizedBox(height: AppSpacing.xl),
        SizedBox(
          height: 52,
          child:
              OutlinedButton(onPressed: onEnd, child: const Text('End alert')),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: 52,
          child: TextButton(
            onPressed: onClose,
            child: const Text('Close this screen'),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Closing this screen does not end the alert.',
          textAlign: TextAlign.center,
          style: TextStyle(color: palette.muted, fontSize: 13),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Accepted contacts only · Alert delivery is not guaranteed',
          textAlign: TextAlign.center,
          style: TextStyle(color: palette.muted, fontSize: 12),
        ),
      ],
    );
  }
}

class _EndAlert extends StatelessWidget {
  const _EndAlert({
    required this.state,
    required this.onPin,
    required this.onEndWithoutPin,
    required this.onBack,
  });

  final PanicState state;
  final ValueChanged<String> onPin;
  final VoidCallback onEndWithoutPin;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    if (!state.requiresPin) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            deliveryLine(state),
            style: TextStyle(
              color: palette.text,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Spacer(),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: onEndWithoutPin,
              child: const Text('End alert'),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Set a safe PIN and a duress PIN in Safety, so nobody else can '
            'end your alert.',
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.muted, fontSize: 13),
          ),
        ],
      );
    }
    return ListView(
      children: [
        Text(
          'Enter your PIN',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: palette.text,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Center(
          child: PinPad(onComplete: onPin, shakeSignal: state.rejectedPins),
        ),
        const SizedBox(height: AppSpacing.md),
        TextButton(onPressed: onBack, child: const Text('Back')),
      ],
    );
  }
}

/// What the screen may honestly say about delivery. It counts who the alert
/// was addressed to; it never claims anyone received it.
String deliveryLine(PanicState state) {
  final count = state.alertedContacts;
  if (state.delivery == PanicDelivery.failed) {
    return "Couldn't send your alert. Check your connection.";
  }
  if (count == 0) {
    return 'You have no confirmed contacts. This alert is recorded on this '
        'phone only.';
  }
  if (state.delivery == PanicDelivery.queued) {
    return 'Waiting for signal. Your alert sends as soon as you are online.';
  }
  if (count == null) return 'Sending…';
  return 'Alerting $count contact${count == 1 ? '' : 's'}';
}

class _Ended extends StatelessWidget {
  const _Ended({required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(),
        Icon(Icons.check_circle_outline_rounded,
            color: palette.muted, size: 64),
        const SizedBox(height: AppSpacing.md),
        Semantics(
          liveRegion: true,
          child: Text(
            'Alert ended',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: palette.text,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const Spacer(),
        SizedBox(
          height: 52,
          child: FilledButton(onPressed: onDone, child: const Text('Done')),
        ),
      ],
    );
  }
}
