import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/dark_card.dart';
import '../../../shared/widgets/primary_button.dart';
import '../application/activity_actions.dart';
import '../domain/app_models.dart';

class WorkoutLogScreen extends ConsumerStatefulWidget {
  const WorkoutLogScreen({super.key});

  @override
  ConsumerState<WorkoutLogScreen> createState() => _WorkoutLogScreenState();
}

class _WorkoutLogScreenState extends ConsumerState<WorkoutLogScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _durationController;
  late final TextEditingController _setsController;
  late final TextEditingController _repsController;
  late final TextEditingController _notesController;
  bool _shareToFeed = true;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _durationController = TextEditingController();
    _setsController = TextEditingController();
    _repsController = TextEditingController();
    _notesController = TextEditingController();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _durationController.dispose();
    _setsController.dispose();
    _repsController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _saveWorkout() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final sets = int.tryParse(_setsController.text.trim()) ?? 0;
      final reps = int.tryParse(_repsController.text.trim()) ?? 0;
      final exercises = <ExerciseEntry>[
        if (sets > 0 || reps > 0)
          ExerciseEntry(
            name: _titleController.text.trim(),
            sets: sets,
            reps: reps,
          ),
      ];

      final result = await ref.read(activityActionsProvider).saveWorkout(
            WorkoutLogDraft(
              title: _titleController.text.trim(),
              duration: '${_durationController.text.trim()} min',
              calories: '0 kcal',
              exercises: exercises,
              notes: _notesController.text.trim(),
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

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Log Workout')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            DarkCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Workout Title', style: TextStyle(color: AppColors.white, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _titleController,
                    style: const TextStyle(color: AppColors.white),
                    decoration: _inputDecoration('e.g. Upper Body Power'),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) return 'Required';
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
                    decoration: _inputDecoration('e.g. 45'),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) return 'Required';
                      if (int.tryParse(val.trim()) == null) return 'Invalid number';
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Sets', style: TextStyle(color: AppColors.white, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _setsController,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(color: AppColors.white),
                              decoration: _inputDecoration('e.g. 4'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Reps', style: TextStyle(color: AppColors.white, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _repsController,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(color: AppColors.white),
                              decoration: _inputDecoration('e.g. 10'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const Text('Notes', style: TextStyle(color: AppColors.white, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _notesController,
                    maxLines: 4,
                    style: const TextStyle(color: AppColors.white),
                    decoration: _inputDecoration('How did it feel?'),
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
              onPressed: _isSaving ? null : _saveWorkout,
            ),
          ],
        ),
      ),
    );
  }
}
