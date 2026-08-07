import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/bouncy_chip.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/share_to_feed_toggle.dart';
import '../../../shared/widgets/staggered_fade_in.dart';
import '../../../shared/widgets/stepper_field.dart';
import '../application/activity_actions.dart';
import '../application/create_flow_controller.dart';
import '../domain/app_models.dart';

class ManualRunEntryScreen extends ConsumerStatefulWidget {
  const ManualRunEntryScreen({super.key});

  @override
  ConsumerState<ManualRunEntryScreen> createState() =>
      _ManualRunEntryScreenState();
}

class _ManualRunEntryScreenState extends ConsumerState<ManualRunEntryScreen>
    with SingleTickerProviderStateMixin {
  static const int _sectionCount = 4;

  late final AnimationController _entranceController;
  late final TextEditingController _distanceController;

  double _distanceKm = 0;
  int _hours = 0;
  int _minutes = 0;
  int _seconds = 0;
  bool _shareToFeed = true;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();

    final draft = ref.read(createFlowControllerProvider).runDraft;
    _distanceKm = draft.distanceKm;
    _hours = draft.hours;
    _minutes = draft.minutes;
    _seconds = draft.seconds;
    _shareToFeed = draft.shareToFeed;
    _distanceController = TextEditingController(
      text: _distanceKm > 0 ? _distanceKm.toStringAsFixed(2) : '',
    );
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _distanceController.dispose();
    super.dispose();
  }

  Duration get _elapsed =>
      Duration(hours: _hours, minutes: _minutes, seconds: _seconds);

  String get _paceLabel {
    if (_distanceKm <= 0 || _elapsed.inSeconds <= 0) return '--';
    final secondsPerKm = _elapsed.inSeconds / _distanceKm;
    final minutes = (secondsPerKm ~/ 60).toString().padLeft(2, '0');
    final seconds = (secondsPerKm.round() % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds /km';
  }

  bool get _hasValidEntry => _distanceKm > 0 || _elapsed.inSeconds > 0;

  void _setDistance(double value) {
    setState(() {
      _distanceKm = value;
      _distanceController.text = value > 0 ? value.toStringAsFixed(2) : '';
    });
    _syncDraft();
  }

  void _bumpDistance(double amount) {
    _setDistance(double.parse((_distanceKm + amount).toStringAsFixed(2)));
  }

  RunDraftState get _currentDraft {
    return RunDraftState(
      distanceKm: _distanceKm,
      hours: _hours,
      minutes: _minutes,
      seconds: _seconds,
      shareToFeed: _shareToFeed,
    );
  }

  void _syncDraft() {
    ref.read(createFlowControllerProvider.notifier).updateRun(_currentDraft);
  }

  Future<void> _saveRun() async {
    if (!_hasValidEntry) {
      setState(() {
        _errorMessage = 'Add a distance or a time before saving.';
      });
      return;
    }

    _syncDraft();
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final result = await ref.read(activityActionsProvider).saveRun(
            RunLogDraft(
              distanceKm: _distanceKm,
              elapsed: _elapsed,
              averagePace: _paceLabel,
              shareToFeed: _shareToFeed,
            ),
          );
      if (!mounted) return;
      ref.read(createFlowControllerProvider.notifier).completeRun(
            result.message,
          );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
      context.go('/home');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    var sectionIndex = 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Log Run Manually')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          StaggeredFadeIn(
            controller: _entranceController,
            index: sectionIndex++,
            itemCount: _sectionCount,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Distance',
                  style: TextStyle(
                    color: palette.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  decoration: BoxDecoration(
                    color: palette.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: palette.stroke),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _distanceController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: palette.text,
                          ),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            hintText: '0.00',
                          ),
                          onChanged: (value) {
                            setState(() {
                              _distanceKm = double.tryParse(value) ?? 0;
                            });
                            _syncDraft();
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(
                          'km',
                          style: TextStyle(
                            color: palette.muted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [0.1, 0.5, 1, 5]
                      .map(
                        (amount) => BouncyChip(
                          label: '+${amount.toStringAsFixed(amount < 1 ? 1 : 0)} km',
                          onTap: () => _bumpDistance(amount.toDouble()),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          StaggeredFadeIn(
            controller: _entranceController,
            index: sectionIndex++,
            itemCount: _sectionCount,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Time',
                  style: TextStyle(
                    color: palette.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: StepperField(
                        label: 'Hours',
                        value: _hours.toDouble(),
                        max: 23,
                        onChanged: (value) {
                          setState(() => _hours = value.toInt());
                          _syncDraft();
                        },
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: StepperField(
                        label: 'Minutes',
                        value: _minutes.toDouble(),
                        max: 59,
                        onChanged: (value) {
                          setState(() => _minutes = value.toInt());
                          _syncDraft();
                        },
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: StepperField(
                        label: 'Seconds',
                        value: _seconds.toDouble(),
                        max: 59,
                        onChanged: (value) {
                          setState(() => _seconds = value.toInt());
                          _syncDraft();
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AnimatedSize(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 240),
              opacity: _hasValidEntry ? 1 : 0,
              child: _hasValidEntry
                  ? Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.orangeBright.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: AppColors.orangeBright.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Estimated pace',
                            style: TextStyle(color: palette.muted),
                          ),
                          Text(
                            _paceLabel,
                            style: const TextStyle(
                              color: AppColors.orangeBright,
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
          StaggeredFadeIn(
            controller: _entranceController,
            index: sectionIndex++,
            itemCount: _sectionCount,
            child: ShareToFeedToggle(
              value: _shareToFeed,
              subtitle: 'Post this run to your profile activity',
              onChanged: (value) {
                setState(() {
                  _shareToFeed = value;
                });
                _syncDraft();
              },
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (_errorMessage != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: palette.stroke),
              ),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: AppColors.orangeBright),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          StaggeredFadeIn(
            controller: _entranceController,
            index: sectionIndex++,
            itemCount: _sectionCount,
            child: PrimaryButton(
              label: _isSaving
                  ? 'Saving...'
                  : (_shareToFeed ? 'Save Run & Share' : 'Save Run'),
              onPressed: _isSaving ? null : _saveRun,
            ),
          ),
        ],
      ),
    );
  }
}
