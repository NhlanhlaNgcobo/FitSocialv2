import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/dark_card.dart';
import '../../../shared/widgets/primary_button.dart';
import '../application/tracking_providers.dart';
import '../data/ble_heart_rate_service.dart';

/// Health & Devices: today's metrics from Health Connect (which watches
/// like Galaxy/Pixel/Fitbit sync into), the phone's live step counter,
/// and Bluetooth heart-rate device pairing.
class HealthDashboardScreen extends ConsumerStatefulWidget {
  const HealthDashboardScreen({super.key});

  @override
  ConsumerState<HealthDashboardScreen> createState() =>
      _HealthDashboardScreenState();
}

class _HealthDashboardScreenState
    extends ConsumerState<HealthDashboardScreen> {
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
            loading: () => const DarkCard(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(
                    color: AppColors.orangeBright,
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
                style: const TextStyle(color: AppColors.orangeBright),
                textAlign: TextAlign.center,
              ),
            ),
          ..._devices.map(
            (d) => DarkCard(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.watch_rounded,
                  color: AppColors.orangeBright,
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
        Icon(icon,
            color: accent ? AppColors.orangeBright : palette.muted,
            size: 28),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: accent ? AppColors.orangeBright : palette.text,
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
            Icon(icon, color: AppColors.orangeBright),
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
