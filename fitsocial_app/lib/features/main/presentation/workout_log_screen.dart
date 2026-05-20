import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/primary_button.dart';
import '../application/activity_actions.dart';
import '../domain/app_models.dart';

class WorkoutLogScreen extends ConsumerStatefulWidget {
  const WorkoutLogScreen({super.key});

  @override
  ConsumerState<WorkoutLogScreen> createState() => _WorkoutLogScreenState();
}

class _WorkoutLogScreenState extends ConsumerState<WorkoutLogScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _durationController;
  late final TextEditingController _caloriesController;
  bool _shareToFeed = true;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: 'Push Day');
    _durationController = TextEditingController(text: '52 min');
    _caloriesController = TextEditingController(text: '520 kcal');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _durationController.dispose();
    _caloriesController.dispose();
    super.dispose();
  }

  Future<void> _saveWorkout() async {
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final result = await ref.read(activityActionsProvider).saveWorkout(
            WorkoutLogDraft(
              title: _titleController.text,
              duration: _durationController.text,
              calories: _caloriesController.text,
              exercises: const [
                'Bench Press',
                'Incline Dumbbell Press',
                'Shoulder Press',
              ],
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
      appBar: AppBar(title: const Text('Log Workout')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          const _FieldLabel(label: 'Workout Title'),
          const SizedBox(height: 8),
          TextField(
            controller: _titleController,
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _MetricField(
                  label: 'Duration',
                  controller: _durationController,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _MetricField(
                  label: 'Calories',
                  controller: _caloriesController,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const _FieldLabel(label: 'Exercises'),
          const SizedBox(height: 8),
          ...const [
            _ExerciseTile(name: 'Bench Press', detail: '4 x 10  |  80 kg'),
            SizedBox(height: AppSpacing.sm),
            _ExerciseTile(
                name: 'Incline Dumbbell Press', detail: '3 x 12  |  26 kg'),
            SizedBox(height: AppSpacing.sm),
            _ExerciseTile(name: 'Shoulder Press', detail: '3 x 10  |  20 kg'),
          ],
          const SizedBox(height: AppSpacing.lg),
          SwitchListTile(
            value: _shareToFeed,
            activeThumbColor: AppColors.orangeBright,
            title: const Text('Share to Feed'),
            subtitle: const Text(
              'Post this workout to your profile activity',
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
          ],
          PrimaryButton(
            label: _isSaving
                ? 'Saving...'
                : (_shareToFeed ? 'Save Workout & Share' : 'Save Workout'),
            onPressed: _isSaving ? null : _saveWorkout,
          ),
        ],
      ),
    );
  }
}

class _MetricField extends StatelessWidget {
  const _MetricField({required this.label, required this.controller});

  final String label;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label: label),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
        ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: AppColors.white,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _ExerciseTile extends StatelessWidget {
  const _ExerciseTile({required this.name, required this.detail});

  final String name;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            detail,
            style: const TextStyle(color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}
