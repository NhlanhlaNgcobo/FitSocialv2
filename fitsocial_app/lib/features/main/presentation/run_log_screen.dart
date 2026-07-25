import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/dark_card.dart';
import '../../../shared/widgets/primary_button.dart';
import '../application/activity_actions.dart';
import '../domain/app_models.dart';

class RunLogScreen extends ConsumerStatefulWidget {
  const RunLogScreen({super.key});

  @override
  ConsumerState<RunLogScreen> createState() => _RunLogScreenState();
}

class _RunLogScreenState extends ConsumerState<RunLogScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _distanceController;
  late final TextEditingController _durationController;
  bool _shareToFeed = true;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _distanceController = TextEditingController();
    _durationController = TextEditingController();
  }

  @override
  void dispose() {
    _distanceController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  Future<void> _saveRun() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final distance = double.parse(_distanceController.text.trim());
      final durationMins = int.parse(_durationController.text.trim());

      final elapsed = Duration(minutes: durationMins);

      String averagePace = '--';
      if (distance > 0) {
        final pace = durationMins / distance;
        final mins = pace.floor();
        final secs = ((pace - mins) * 60).round().toString().padLeft(2, '0');
        averagePace = '$mins:$secs /km';
      }

      final result = await ref.read(activityActionsProvider).saveRun(
            RunLogDraft(
              distanceKm: distance,
              elapsed: elapsed,
              averagePace: averagePace,
              shareToFeed: _shareToFeed,
            ),
          );
      if (!mounted) return;
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
    return Scaffold(
      appBar: AppBar(title: const Text('Log Run')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            DarkCard(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.gps_fixed_rounded,
                  color: AppColors.orangeBright,
                ),
                title: const Text(
                  'Track live with GPS',
                  style: TextStyle(
                    color: AppColors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: const Text(
                  'Real-time distance, pace, and heart rate',
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
                ),
                trailing:
                    const Icon(Icons.chevron_right, color: AppColors.muted),
                onTap: () => context.push('/live-run'),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            const Center(
              child: Text(
                'or log manually',
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            DarkCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Distance (km)', style: TextStyle(color: AppColors.white, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _distanceController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: AppColors.white),
                    decoration: InputDecoration(
                      hintText: 'e.g. 5.0',
                      hintStyle: const TextStyle(color: AppColors.muted),
                      filled: true,
                      fillColor: AppColors.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.stroke),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.stroke),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.orangeBright),
                      ),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) return 'Required';
                      if (double.tryParse(val.trim()) == null) return 'Invalid number';
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const Text('Duration (minutes)', style: TextStyle(color: AppColors.white, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _durationController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: AppColors.white),
                    decoration: InputDecoration(
                      hintText: 'e.g. 30',
                      hintStyle: const TextStyle(color: AppColors.muted),
                      filled: true,
                      fillColor: AppColors.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.stroke),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.stroke),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.orangeBright),
                      ),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) return 'Required';
                      if (int.tryParse(val.trim()) == null) return 'Invalid number';
                      return null;
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            SwitchListTile(
              value: _shareToFeed,
              activeColor: AppColors.orangeBright,
              title: const Text('Share to feed'),
              subtitle: const Text(
                'Post this run to your profile activity',
                style: TextStyle(color: AppColors.muted),
              ),
              contentPadding: EdgeInsets.zero,
              onChanged: (value) {
                setState(() {
                  _shareToFeed = value;
                });
              },
            ),
            const SizedBox(height: AppSpacing.md),
            if (_errorMessage != null) ...[
              Container(
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
            ],
            PrimaryButton(
              label: _isSaving ? 'Saving...' : 'Save',
              onPressed: _isSaving ? null : _saveRun,
            ),
          ],
        ),
      ),
    );
  }
}
