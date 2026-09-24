import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/quick_toast.dart';
import '../application/safety_providers.dart';
import '../domain/safety_models.dart';
import 'pin_pad.dart';
import 'safety_widgets.dart';

/// Whether the app may read location right now. Re-read when the screen
/// returns, since the user may have changed it in system settings.
final _locationPermissionProvider =
    FutureProvider.autoDispose<LocationPermission>((ref) {
  return Geolocator.checkPermission();
});

/// Safety home: the silent alert button, contacts, PINs and location. The
/// entry point from spec A.9.
class SafetyScreen extends ConsumerWidget {
  const SafetyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final settings = ref.watch(safetySettingsProvider).valueOrNull ??
        SafetySettings.defaults;
    final appContacts =
        ref.watch(safetyContactsProvider).valueOrNull ?? const [];
    final emailContacts =
        ref.watch(emailSafetyContactsProvider).valueOrNull ?? const [];
    final incoming = ref.watch(safetyContactOfProvider).valueOrNull ?? const [];
    final used = ref.watch(usedSafetySlotsProvider);
    final ready = appContacts.where((c) => c.isAccepted).length +
        emailContacts.where((c) => c.isConfirmed).length;
    final waiting =
        incoming.where((c) => c.status == SafetyContactStatus.pending).length;
    final permission = ref.watch(_locationPermissionProvider).valueOrNull;
    final locationOk = permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;

    return Scaffold(
      appBar: AppBar(title: const Text('Safety')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.xl,
        ),
        children: [
          _PanicButton(
            onPressed: () {
              // A second press while an alert is running just reopens it.
              ref.read(panicControllerProvider.notifier).trigger();
              context.push('/safety/panic');
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          SafetyNote(
            ready == 0
                ? 'You have no confirmed contacts yet, so nobody would be '
                    'alerted.'
                : 'The alert goes to your $ready confirmed '
                    'contact${ready == 1 ? '' : 's'} the moment you press, '
                    'with your live location until you enter your safe PIN. '
                    'Nothing sounds or flashes on your phone.',
            icon: ready == 0
                ? Icons.warning_amber_rounded
                : Icons.info_outline_rounded,
          ),
          const SizedBox(height: AppSpacing.lg),
          const SafetySectionLabel('Setup'),
          SafetyCard(
            children: [
              SafetyRow(
                icon: Icons.group_rounded,
                title: 'Safety contacts',
                subtitle: waiting > 0
                    ? '$used of $maxAcceptedSafetyContacts · $waiting request'
                        '${waiting == 1 ? '' : 's'} waiting for you'
                    : '$used of $maxAcceptedSafetyContacts · $ready ready',
                onTap: () => context.push('/safety/contacts'),
              ),
              SafetyRow(
                icon: Icons.pin_rounded,
                title: 'Panic PINs',
                subtitle: settings.hasPins
                    ? 'Safe PIN and duress PIN set'
                    : 'Not set · anyone can end your alert',
                accent: settings.hasPins ? safetyTeal : palette.danger,
                onTap: () => context.push('/safety/pins'),
              ),
              SafetyRow(
                icon: Icons.my_location_rounded,
                title: 'Location',
                subtitle: locationOk
                    ? 'Allowed while using the app'
                    : 'Off · alerts go without your position',
                accent: locationOk ? safetyTeal : palette.danger,
                onTap: locationOk
                    ? null
                    : () async {
                        final result = await Geolocator.requestPermission();
                        if (result == LocationPermission.deniedForever) {
                          await Geolocator.openAppSettings();
                        }
                        ref.invalidate(_locationPermissionProvider);
                      },
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          const SafetySectionLabel('After an alert'),
          SafetyCard(
            children: [
              SafetyRow(
                icon: Icons.verified_user_rounded,
                title: "I'm safe now",
                subtitle: 'End any alert that is still running',
                onTap: () => showEndAlertSheet(context),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          const SafetySectionLabel('What this does not do'),
          const SafetyCard(
            children: [
              Padding(
                padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: _Limits(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Limits extends StatelessWidget {
  const _Limits();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final style = TextStyle(color: palette.text, fontSize: 14, height: 1.45);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in const [
          'It only reaches your confirmed contacts: FitSocial users with '
              'notifications on, and people who confirmed by email.',
          'It does not sound an alarm or flash on your phone, so it never '
              'draws attention to you.',
          'It does not call the police, an ambulance or private security. In '
              'danger, call 10111 or 112. Both are free without airtime.',
          'It cannot stop the phone being switched off, and location stops '
              'when the battery dies or signal is lost.',
          'Alert delivery is not guaranteed. SMS and WhatsApp are not '
              'available yet.',
        ])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('•  ', style: style),
                Expanded(child: Text(line, style: style)),
              ],
            ),
          ),
      ],
    );
  }
}

class _PanicButton extends StatelessWidget {
  const _PanicButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Send silent alert. Sends immediately.',
      child: Material(
        color: const Color(0xFFB3261E),
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.card),
          onTap: onPressed,
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 28, horizontal: 20),
            child: Column(
              children: [
                Icon(Icons.sos_rounded, color: Colors.white, size: 48),
                SizedBox(height: AppSpacing.sm),
                Text(
                  'Send silent alert',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Sends straight away. Nothing sounds on your phone.',
                  style: TextStyle(color: Color(0xDDFFFFFF)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "I'm safe now": ends any open alert, including one left running by the
/// duress PIN. Always offered, whether or not anything is running — showing
/// it only during an alert would tell whoever holds the phone that one is.
Future<void> showEndAlertSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _EndAlertSheet(),
  );
}

class _EndAlertSheet extends ConsumerStatefulWidget {
  const _EndAlertSheet();

  @override
  ConsumerState<_EndAlertSheet> createState() => _EndAlertSheetState();
}

class _EndAlertSheetState extends ConsumerState<_EndAlertSheet> {
  int _shake = 0;
  bool _busy = false;

  Future<void> _entered(String pin) async {
    setState(() => _busy = true);
    final overlay = Overlay.of(context, rootOverlay: true);
    final ok =
        await ref.read(panicControllerProvider.notifier).endOpenEvents(pin);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _shake++;
      });
      return;
    }
    Navigator.of(context).pop();
    // Same words for the safe and the duress PIN.
    showQuickToastOn(overlay, 'Done', icon: Icons.check_rounded);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final hasPins =
        ref.watch(safetySettingsProvider).valueOrNull?.hasPins ?? false;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "I'm safe now",
              style: TextStyle(
                color: palette.text,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              hasPins
                  ? 'Enter your safe PIN to end any alert and stop sharing '
                      'your location.'
                  : 'End any alert and stop sharing your location.',
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.muted),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (hasPins)
              PinPad(onComplete: _entered, shakeSignal: _shake, enabled: !_busy)
            else
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : () => _entered(''),
                  child: const Text("I'm safe"),
                ),
              ),
            if (!hasPins) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                pinSetupHint,
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.muted, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

const pinSetupHint =
    'Set your PINs in Safety so nobody else can end your alerts.';
