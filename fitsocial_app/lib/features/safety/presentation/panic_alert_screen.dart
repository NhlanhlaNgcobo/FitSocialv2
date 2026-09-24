import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/quick_toast.dart';
import '../../../shared/widgets/run_route_map.dart';
import '../../auth/application/app_session.dart';
import '../../main/application/content_providers.dart'
    show currentUserIdProvider;
import '../application/safety_providers.dart';
import '../data/safety_repositories.dart';
import '../domain/safety_alerts.dart';
import 'safety_widgets.dart';

const _alarmRed = Color(0xFFB3261E);

/// What a FitSocial safety contact sees when they open an alert. See spec
/// A.6. Email contacts see the same information on the web page served by
/// functions/safety_email.js.
///
/// One moving pin with its age, never a trail: the backend keeps only the
/// latest position, and the screen must not imply more than it has.
class PanicAlertScreen extends ConsumerStatefulWidget {
  const PanicAlertScreen({required this.eventId, super.key});

  final String eventId;

  @override
  ConsumerState<PanicAlertScreen> createState() => _PanicAlertScreenState();
}

class _PanicAlertScreenState extends ConsumerState<PanicAlertScreen> {
  Timer? _tick;
  bool _responding = false;

  @override
  void initState() {
    super.initState();
    // Keeps "updated 40 seconds ago" honest between position writes.
    _tick = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _respond() async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    final name =
        ref.read(appSessionProvider).profile?.displayName ?? 'A contact';
    final overlay = Overlay.of(context, rootOverlay: true);
    setState(() => _responding = true);
    try {
      await ref.read(panicAlertRepositoryProvider).acknowledge(
            eventId: widget.eventId,
            userId: uid,
            displayName: name,
          );
    } catch (_) {
      showQuickToastOn(
        overlay,
        "Couldn't send that. Check your connection.",
        icon: Icons.error_outline_rounded,
        tone: ToastTone.danger,
      );
    } finally {
      if (mounted) setState(() => _responding = false);
    }
  }

  /// Automatic dialling of emergency services is not allowed on either
  /// platform, so this opens the dialler with the number filled in.
  Future<void> _callEmergency() async {
    final number = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                'Both numbers are free, even without airtime.',
                textAlign: TextAlign.center,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.local_police_rounded),
              title: const Text('Police · 10111'),
              onTap: () => Navigator.of(sheet).pop('10111'),
            ),
            ListTile(
              leading: const Icon(Icons.emergency_rounded),
              title: const Text('Emergency from a cellphone · 112'),
              onTap: () => Navigator.of(sheet).pop('112'),
            ),
            ListTile(
              leading: const Icon(Icons.local_hospital_rounded),
              title: const Text('Ambulance · 10177'),
              onTap: () => Navigator.of(sheet).pop('10177'),
            ),
          ],
        ),
      ),
    );
    if (number == null) return;
    await launchUrl(Uri(scheme: 'tel', path: number));
  }

  Future<void> _openMaps(double lat, double lng) async {
    await launchUrl(
      Uri.https('www.google.com', '/maps/search/', {
        'api': '1',
        'query': '$lat,$lng',
      }),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final alertAsync = ref.watch(panicAlertProvider(widget.eventId));
    final acks =
        ref.watch(panicAcknowledgementsProvider(widget.eventId)).valueOrNull ??
            const [];
    final me = ref.watch(currentUserIdProvider);
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(title: const Text('Safety alert')),
      body: alertAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const _Message(
          "You can't see this alert. It may not have been sent to you.",
        ),
        data: (alert) {
          if (alert == null) {
            return const _Message('This alert no longer exists.');
          }
          final name = alert.userName;
          final live = alert.current;
          final lat = live?.lat ?? alert.position?.lat;
          final lng = live?.lng ?? alert.position?.lng;
          final updatedAt = live?.updatedAt ?? alert.raisedAt;
          final accuracy = live?.accuracy ?? alert.position?.accuracy;
          final responding = acks.any((a) => a.uid == me);

          return ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.xl,
            ),
            children: [
              _Banner(alert: alert),
              if (alert.isOpen) ...[
                const SizedBox(height: AppSpacing.md),
                if (lat != null && lng != null) ...[
                  RunRouteMap(
                    route: [LatLng(lat, lng)],
                    mode: RunRouteMapMode.spectator,
                    currentMarkerTitle: name,
                    height: 300,
                    showBadge: false,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      'Location updated ${agoLabel(updatedAt, now)}'
                      '${accuracy == null ? '' : ' · accurate to about '
                          '${accuracy.round()} m'}',
                      style: TextStyle(color: palette.muted),
                    ),
                  ),
                ] else
                  Text(
                    "$name's phone hasn't shared a position. Their location "
                    'may be switched off.',
                    style: TextStyle(color: palette.muted),
                  ),
                const SizedBox(height: AppSpacing.md),
                SafetyCard(
                  children: [
                    SafetyRow(
                      icon: Icons.schedule_rounded,
                      title: 'Alert raised ${agoLabel(alert.raisedAt, now)}',
                    ),
                    if (alert.latestBattery != null)
                      SafetyRow(
                        icon: Icons.battery_std_rounded,
                        title: 'Battery ${alert.latestBattery}%',
                      ),
                    SafetyRow(
                      icon: Icons.groups_rounded,
                      title: acks.isEmpty
                          ? 'Nobody has responded yet'
                          : 'Responding: '
                              '${acks.map((a) => a.displayName).join(', ')}',
                      subtitle: alert.alerted.isEmpty
                          ? null
                          : 'Alerted: '
                              '${alert.alerted.map((c) => c.displayName).join(', ')}',
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  height: 56,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: responding ? safetyTeal : _alarmRed,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: responding || _responding ? null : _respond,
                    icon: Icon(
                      responding
                          ? Icons.check_rounded
                          : Icons.directions_run_rounded,
                    ),
                    label: Text(
                      responding
                          ? '$name knows you are responding'
                          : "I'm responding",
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                SizedBox(
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: _callEmergency,
                    icon: const Icon(Icons.call_rounded),
                    label: const Text('Call emergency services'),
                  ),
                ),
                if (lat != null && lng != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  SizedBox(
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: () => _openMaps(lat, lng),
                      icon: const Icon(Icons.navigation_rounded),
                      label: const Text('Directions in Google Maps'),
                    ),
                  ),
                ],
                const SafetyNote(
                  'Calling someone needs airtime. Emergency numbers are free.',
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.alert});

  final PanicAlert alert;

  @override
  Widget build(BuildContext context) {
    final name = alert.userName;
    final (title, body, color) = switch (alert.status) {
      PanicEventStatus.active => (
          '$name needs help',
          'They raised an emergency alert.',
          _alarmRed,
        ),
      PanicEventStatus.duress => (
          "$name's alert was cancelled under pressure",
          'They used their duress code, so they may have been forced to. The '
              'alert is still active.',
          _alarmRed,
        ),
      PanicEventStatus.resolved => (
          '$name is safe',
          'They ended the alert. Their location is no longer shared.',
          safetyTeal,
        ),
    };
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(body, style: const TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: context.palette.muted, fontSize: 16),
        ),
      ),
    );
  }
}
