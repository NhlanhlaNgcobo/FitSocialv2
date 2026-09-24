import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/quick_toast.dart';
import '../../main/application/content_providers.dart'
    show currentUserIdProvider;
import '../application/safety_providers.dart';
import '../data/safety_repositories.dart';
import '../domain/panic_pins.dart';
import '../domain/safety_models.dart';
import 'pin_pad.dart';

enum _Step { safe, safeConfirm, duress, duressConfirm }

/// Sets the two panic PINs. See spec A.5.
///
/// One PIN at a time, each entered twice, on the same keypad the panic screen
/// uses — so the first time the user meets it is not the moment they need it.
class PinSetupScreen extends ConsumerStatefulWidget {
  const PinSetupScreen({super.key});

  @override
  ConsumerState<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends ConsumerState<PinSetupScreen> {
  _Step _step = _Step.safe;
  String _safe = '';
  String _safeConfirm = '';
  String _duress = '';
  String? _error;
  int _shake = 0;
  bool _saving = false;

  void _entered(String pin) {
    var ready = false;
    setState(() {
      _error = null;
      switch (_step) {
        case _Step.safe:
          _safe = pin;
          _step = _Step.safeConfirm;
        case _Step.safeConfirm:
          if (pin != _safe) {
            _refuse(PinSetupError.safeConfirmationMismatch, back: _Step.safe);
            return;
          }
          _safeConfirm = pin;
          _step = _Step.duress;
        case _Step.duress:
          if (pin == _safe) {
            _refuse(PinSetupError.duressSameAsSafe, back: _Step.duress);
            return;
          }
          _duress = pin;
          _step = _Step.duressConfirm;
        case _Step.duressConfirm:
          final problem = validatePanicPins(
            safePin: _safe,
            safeConfirm: _safeConfirm,
            duressPin: _duress,
            duressConfirm: pin,
          );
          if (problem != null) {
            _refuse(problem, back: _Step.duress);
            return;
          }
          ready = true;
      }
    });
    if (ready) _save();
  }

  void _refuse(PinSetupError error, {required _Step back}) {
    _error = pinSetupErrorText(error);
    _shake++;
    _step = back;
  }

  Future<void> _save() async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    setState(() => _saving = true);
    final overlay = Overlay.of(context, rootOverlay: true);
    try {
      final current = ref.read(safetySettingsProvider).valueOrNull ??
          SafetySettings.defaults;
      final next =
          PanicPins.withPins(current, safePin: _safe, duressPin: _duress);
      await ref.read(safetyRepositoryProvider).saveSettings(uid, next);
      if (!mounted) return;
      showQuickToastOn(overlay, 'PINs saved', icon: Icons.check_rounded);
      context.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error =
            'Could not save your PINs. Check your connection and try again.';
        _step = _Step.safe;
      });
    }
  }

  ({String title, String body}) get _copy {
    switch (_step) {
      case _Step.safe:
        return (
          title: 'Choose your safe PIN',
          body: 'Four digits. Entering it ends your alert, stops sharing your '
              'location and tells your contacts you are safe.',
        );
      case _Step.safeConfirm:
        return (title: 'Enter your safe PIN again', body: 'To make sure.');
      case _Step.duress:
        return (
          title: 'Choose your duress PIN',
          body: 'Use this if you are forced to cancel. Your screen shows the '
              'alert has ended, but your contacts are told you were forced, '
              'and your location keeps being shared with them.',
        );
      case _Step.duressConfirm:
        return (title: 'Enter your duress PIN again', body: 'To make sure.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final copy = _copy;
    final stepIndex = _Step.values.indexOf(_step);

    return Scaffold(
      appBar: AppBar(title: const Text('Panic PINs')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.xl,
          ),
          children: [
            Semantics(
              label: 'Step ${stepIndex + 1} of 4',
              child: Row(
                children: [
                  for (var i = 0; i < 4; i++)
                    Expanded(
                      child: Container(
                        height: 4,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color:
                              i <= stepIndex ? palette.brand : palette.stroke,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              copy.title,
              style: TextStyle(
                color: palette.text,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              copy.body,
              style: TextStyle(color: palette.muted, fontSize: 15, height: 1.4),
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              height: 22,
              child: _error == null
                  ? null
                  : Semantics(
                      liveRegion: true,
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: palette.danger,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: AppSpacing.md),
            Center(
              child: PinPad(
                onComplete: _entered,
                shakeSignal: _shake,
                enabled: !_saving,
              ),
            ),
            if (_saving) ...[
              const SizedBox(height: AppSpacing.md),
              const Center(child: CircularProgressIndicator()),
            ],
          ],
        ),
      ),
    );
  }
}
