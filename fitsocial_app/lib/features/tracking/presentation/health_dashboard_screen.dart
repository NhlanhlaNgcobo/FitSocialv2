import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/dark_card.dart';
import '../../../shared/widgets/primary_button.dart';
import '../application/tracking_providers.dart';
import '../data/ble_heart_rate_service.dart';
import '../data/health_service.dart';
import '../../music/presentation/music_island_action.dart';

/// Health & Devices: today's metrics from Health Connect (which watches
/// like Galaxy/Pixel/Fitbit sync into), the phone's live step counter,
/// and Bluetooth heart-rate device pairing.
class HealthDashboardScreen extends ConsumerStatefulWidget {
  const HealthDashboardScreen({super.key});

  @override
  ConsumerState<HealthDashboardScreen> createState() =>
      _HealthDashboardScreenState();
}

class _HealthDashboardScreenState extends ConsumerState<HealthDashboardScreen> {
  List<HeartRateDevice> _devices = [];
  bool _isScanning = false;
  bool _isConnecting = false;
  String? _connectedName;
  String? _bleMessage;
  StreamSubscription<List<HeartRateDevice>>? _scanSub;

  @override
  void dispose() {
    _scanSub?.cancel();
    super.dispose();
  }

  Future<void> _scan() async {
    final ble = ref.read(bleHeartRateServiceProvider);
    setState(() {
      _bleMessage = null;
      _devices = [];
    });

    if (!await ble.isSupported()) {
      setState(() => _bleMessage = 'Bluetooth LE is not available here.');
      return;
    }
    if (!await ble.requestPermissions()) {
      setState(() => _bleMessage = 'Bluetooth permission denied.');
      return;
    }

    setState(() => _isScanning = true);
    _scanSub?.cancel();
    _scanSub = ble.scan().listen(
          (devices) => setState(() => _devices = devices),
          onError: (Object e) => setState(() {
            _bleMessage = 'Scan failed: $e';
            _isScanning = false;
          }),
          onDone: () => setState(() => _isScanning = false),
        );
  }

  Future<void> _connect(HeartRateDevice device) async {
    final ble = ref.read(bleHeartRateServiceProvider);
    setState(() {
      _isConnecting = true;
      _bleMessage = null;
    });
    try {
      await ble.stopScan();
      await ble.connect(device.device);
      setState(() => _connectedName = device.name);
    } catch (e) {
      setState(() => _bleMessage = 'Connection failed: $e');
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final health = ref.watch(healthSummaryProvider);
    final sessionSteps = ref.watch(sessionStepsProvider).valueOrNull;
    final liveBpm = ref.watch(liveHeartRateProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Health & Devices'),
        actions: [
          const MusicIslandAction(),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(healthSummaryProvider),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          const _SectionLabel('TODAY · FROM HEALTH CONNECT'),
          const SizedBox(height: 8),
          health.when(
            loading: () => DarkCard(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: CircularProgressIndicator(
                    color: context.palette.brand,
                  ),
                ),
              ),
            ),
            error: (e, _) => _InfoCard(
              icon: Icons.error_outline_rounded,
              text: 'Could not read health data: $e',
            ),
            data: (summary) => !summary.available
                ? const _InfoCard(
                    icon: Icons.health_and_safety_outlined,
                    text:
                        'Health Connect is unavailable or permission was denied. '
                        'Install/enable Health Connect and grant access — your '
                        'smartwatch data (steps, heart rate, sleep) syncs '
                        'through it.',
                  )
                : DarkCard(
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _HealthMetric(
                              icon: Icons.directions_walk_rounded,
                              label: 'Steps',
                              value: summary.steps?.toString() ?? '--',
                            ),
                            _HealthMetric(
                              icon: Icons.favorite_rounded,
                              label: 'Heart rate',
                              value: summary.heartRateBpm != null
                                  ? '${summary.heartRateBpm!.round()} bpm'
                                  : '--',
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _HealthMetric(
                              icon: Icons.bedtime_rounded,
                              label: 'Sleep',
                              value: summary.sleep != null
                                  ? '${summary.sleep!.inHours}h '
                                      '${summary.sleep!.inMinutes.remainder(60)}m'
                                  : '--',
                            ),
                            _HealthMetric(
                              icon: Icons.local_fire_department_rounded,
                              label: 'Active kcal',
                              value: summary.activeCaloriesKcal
                                      ?.round()
                                      .toString() ??
                                  '--',
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),
                        _SyncNote(summary),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const _SectionLabel('LIVE · PHONE SENSORS'),
          const SizedBox(height: 8),
          DarkCard(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _HealthMetric(
                  icon: Icons.directions_run_rounded,
                  label: 'Session steps',
                  value: sessionSteps?.toString() ?? '0',
                ),
                _HealthMetric(
                  icon: Icons.monitor_heart_rounded,
                  label: 'Live BPM',
                  value: liveBpm?.toString() ?? '--',
                  accent: liveBpm != null,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const _SectionLabel('BLUETOOTH · HEART-RATE DEVICES'),
          const SizedBox(height: 8),
          if (_connectedName != null)
            _InfoCard(
              icon: Icons.bluetooth_connected_rounded,
              text: 'Connected to $_connectedName'
                  '${liveBpm != null ? ' — $liveBpm bpm' : ''}',
            ),
          PrimaryButton(
            label: _isScanning ? 'Scanning…' : 'Scan for Devices',
            icon: Icons.bluetooth_searching_rounded,
            onPressed: _isScanning ? null : _scan,
          ),
          const SizedBox(height: AppSpacing.sm),
          if (_bleMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                _bleMessage!,
                style: TextStyle(color: context.palette.brandText),
                textAlign: TextAlign.center,
              ),
            ),
          ..._devices.map(
            (d) => DarkCard(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.watch_rounded,
                  color: context.palette.brand,
                ),
                title: Text(
                  d.name,
                  style: TextStyle(color: palette.text),
                ),
                subtitle: Text(
                  '${d.id} · ${d.rssi} dBm',
                  style: TextStyle(color: palette.muted, fontSize: 12),
                ),
                trailing: TextButton(
                  onPressed: _isConnecting ? null : () => _connect(d),
                  child: Text(_isConnecting ? '…' : 'Connect'),
                ),
              ),
            ),
          ),
          if (_devices.isEmpty && !_isScanning)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Works with smartwatches and chest straps that broadcast '
                'the standard Bluetooth heart-rate profile.',
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.muted, fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }
}

/// Says where the numbers above came from, and when.
///
/// The card is a faithful read of Health Connect, but Health Connect is not
/// live: Samsung Health and the watch write into it in batches, so their own
/// screens can sit a few hundred steps ahead. Without a timestamp that gap
/// reads as "FitSocial is wrong". With one it reads as "FitSocial is a few
/// minutes behind", which is both true and something a refresh fixes.
class _SyncNote extends StatelessWidget {
  const _SyncNote(this.summary);

  final HealthSummary summary;

  static String _hhmm(DateTime t) {
    final local = t.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  void _explain(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Where this number comes from'),
        content: const Text(
          'FitSocial reads Health Connect — the shared store your watch and '
          'Samsung Health write into. It does not talk to your watch '
          'directly.\n\n'
          'Those apps write in batches rather than continuously, so their own '
          'screens can be ahead of what Health Connect holds. Open Samsung '
          'Health for a few seconds, then refresh here, and the count catches '
          'up.\n\n'
          'Challenge progress keeps the highest count seen during the day, so '
          'a reading that comes back low never erases walking already '
          'recorded.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final asOf = summary.stepsAsOf;
    final readAt = summary.readAt;

    final text = asOf != null
        ? 'via Health Connect · synced to ${_hhmm(asOf)}'
        : readAt != null
            ? 'via Health Connect · checked ${_hhmm(readAt)}'
            : 'via Health Connect';

    return InkWell(
      onTap: () => _explain(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.info_outline_rounded, size: 14, color: palette.muted),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.muted, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Text(
      text,
      style: TextStyle(
        color: palette.muted,
        fontSize: 12,
        letterSpacing: 1.5,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _HealthMetric extends StatelessWidget {
  const _HealthMetric({
    required this.icon,
    required this.label,
    required this.value,
    this.accent = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      children: [
        Icon(icon, color: accent ? palette.brand : palette.muted, size: 28),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: accent ? palette.brandText : palette.text,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(color: palette.muted, fontSize: 12),
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: DarkCard(
        child: Row(
          children: [
            Icon(icon, color: context.palette.brand),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                text,
                style: TextStyle(color: palette.muted, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
