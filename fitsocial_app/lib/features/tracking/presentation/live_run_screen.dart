import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/dark_card.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../main/application/activity_actions.dart';
import '../../main/domain/app_models.dart';
import '../application/tracking_providers.dart';
import '../data/live_run_service.dart';
import 'run_route_map.dart';

/// Live GPS run tracking: start/pause/stop with real-time distance,
/// duration, and pace from the phone's location sensors, plus live BPM
/// when a Bluetooth heart-rate device is connected.
class LiveRunScreen extends ConsumerStatefulWidget {
  const LiveRunScreen({super.key});

  @override
  ConsumerState<LiveRunScreen> createState() => _LiveRunScreenState();
}

class _LiveRunScreenState extends ConsumerState<LiveRunScreen> {
  bool _isSaving = false;
  String? _errorMessage;

  Future<void> _start() async {
    setState(() => _errorMessage = null);
    try {
      await ref.read(liveRunServiceProvider).start();
    } on LocationPermissionException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (e) {
      setState(() => _errorMessage = 'Could not start GPS tracking: $e');
    }
  }

  Future<void> _stopAndSave() async {
    final service = ref.read(liveRunServiceProvider);
    final result = service.stop();

    if (result.distanceKm < 0.05) {
      setState(() {
        _errorMessage =
            'Run too short to save (${(result.distanceKm * 1000).round()} m).';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    try {
      final saved = await ref.read(activityActionsProvider).saveRun(
            RunLogDraft(
              distanceKm: double.parse(result.distanceKm.toStringAsFixed(2)),
              elapsed: result.elapsed,
              averagePace: result.formattedAveragePace,
              shareToFeed: true,
            ),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(saved.message)),
      );
      context.go('/home');
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String _formatElapsed(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final runState =
        ref.watch(liveRunStateProvider).valueOrNull ?? LiveRunState.idle;
    final liveBpm = ref.watch(liveHeartRateProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Run'),
        actions: [
          IconButton(
            tooltip: 'Connect heart-rate device',
            icon: Icon(
              liveBpm != null
                  ? Icons.favorite_rounded
                  : Icons.monitor_heart_outlined,
              color: liveBpm != null ? AppColors.orangeBright : null,
            ),
            onPressed: () => context.push('/health'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          if (runState.isTracking) ...[
            RunRouteMap(points: runState.points),
            const SizedBox(height: AppSpacing.md),
          ],
          DarkCard(
            child: Column(
              children: [
                Text(
                  runState.distanceKm.toStringAsFixed(2),
                  style: const TextStyle(
                    fontSize: 64,
                    fontWeight: FontWeight.w900,
                    color: AppColors.white,
                  ),
                ),
                const Text(
                  'KILOMETERS',
                  style: TextStyle(
                    color: AppColors.muted,
                    letterSpacing: 2,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _Metric(
                      label: 'TIME',
                      value: _formatElapsed(runState.elapsed),
                    ),
                    _Metric(
                      label: 'PACE',
                      value: '${runState.formattedPace} /km',
                    ),
                    _Metric(
                      label: 'BPM',
                      value: liveBpm?.toString() ?? '--',
                      accent: liveBpm != null,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (runState.isTracking && !runState.isPaused)
            Row(
              children: [
                Expanded(
                  child: PrimaryButton(
                    label: 'Pause',
                    icon: Icons.pause_rounded,
                    onPressed: () => ref.read(liveRunServiceProvider).pause(),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: PrimaryButton(
                    label: _isSaving ? 'Saving...' : 'Finish',
                    icon: Icons.stop_rounded,
                    onPressed: _isSaving ? null : _stopAndSave,
                  ),
                ),
              ],
            )
          else if (runState.isTracking && runState.isPaused)
            Row(
              children: [
                Expanded(
                  child: PrimaryButton(
                    label: 'Resume',
                    icon: Icons.play_arrow_rounded,
                    onPressed: () => ref.read(liveRunServiceProvider).resume(),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: PrimaryButton(
                    label: _isSaving ? 'Saving...' : 'Finish',
                    icon: Icons.stop_rounded,
                    onPressed: _isSaving ? null : _stopAndSave,
                  ),
                ),
              ],
            )
          else
            PrimaryButton(
              label: 'Start GPS Run',
              icon: Icons.play_arrow_rounded,
              onPressed: _start,
            ),
          const SizedBox(height: AppSpacing.md),
          if (_errorMessage != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.stroke),
              ),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: AppColors.orangeBright),
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          if (runState.isAutoPaused)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.orangeBright.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.motion_photos_paused_rounded,
                      color: AppColors.orangeBright, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Auto-paused — start moving to resume',
                    style: TextStyle(
                      color: AppColors.orangeBright,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          if (runState.isAutoPaused) const SizedBox(height: AppSpacing.md),
          Text(
            runState.isTracking
                ? 'GPS tracking active — ${runState.points.length} location fixes recorded.'
                : 'Distance, time, and pace are measured live from GPS. '
                    'Keep your phone with you during the run.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, this.accent = false});

  final String label;
  final String value;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: accent ? AppColors.orangeBright : AppColors.white,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.muted,
            fontSize: 11,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }
}
