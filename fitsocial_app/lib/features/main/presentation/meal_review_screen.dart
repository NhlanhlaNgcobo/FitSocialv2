import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/dark_card.dart';
import '../../../shared/widgets/primary_button.dart';
import '../application/activity_actions.dart';
import '../application/create_flow_controller.dart';
import '../domain/app_models.dart';

class MealReviewScreen extends ConsumerStatefulWidget {
  const MealReviewScreen({super.key});

  @override
  ConsumerState<MealReviewScreen> createState() => _MealReviewScreenState();
}

class _MealReviewScreenState extends ConsumerState<MealReviewScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _caloriesController;
  late final TextEditingController _proteinController;
  late final TextEditingController _carbsController;
  late final TextEditingController _fatController;
  late final TextEditingController _notesController;
  bool _shareToFeed = true;
  bool _isSaving = false;
  String? _errorMessage;
  String? _imageUrl;

  @override
  void initState() {
    super.initState();
    final draft = ref.read(createFlowControllerProvider).mealDraft;
    _nameController = TextEditingController(text: draft.name);
    _caloriesController = TextEditingController(text: draft.calories);
    _proteinController = TextEditingController(text: draft.protein);
    _carbsController = TextEditingController(text: draft.carbs);
    _fatController = TextEditingController(text: draft.fat);
    _notesController = TextEditingController(text: draft.notes);
    _shareToFeed = draft.shareToFeed;
    _imageUrl = draft.imageUrl;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _caloriesController.dispose();
    _proteinController.dispose();
    _carbsController.dispose();
    _fatController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _saveMeal() async {
    final draft = _currentDraft;
    if (draft.name.trim().isEmpty) {
      setState(() {
        _errorMessage = 'Add a meal name before saving.';
      });
      return;
    }

    ref.read(createFlowControllerProvider.notifier).updateMeal(draft);
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final result = await ref.read(activityActionsProvider).saveMeal(
            MealLogDraft(
              name: draft.name,
              calories: draft.calories,
              protein: draft.protein,
              carbs: draft.carbs,
              fat: draft.fat,
              notes: draft.notes,
              shareToFeed: draft.shareToFeed,
              imageUrl: _imageUrl,
            ),
          );
      if (!mounted) return;
      ref.read(createFlowControllerProvider.notifier).completeMeal(
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

  MealDraftState get _currentDraft {
    return MealDraftState(
      name: _nameController.text,
      calories: _caloriesController.text,
      protein: _proteinController.text,
      carbs: _carbsController.text,
      fat: _fatController.text,
      notes: _notesController.text,
      shareToFeed: _shareToFeed,
      imageUrl: _imageUrl,
    );
  }

  void _syncDraft() {
    ref.read(createFlowControllerProvider.notifier).updateMeal(_currentDraft);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Meal Review')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          DarkCard(
            child: Row(
              children: [
                Container(
                  width: 92,
                  height: 92,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.stroke),
                  ),
                  child: const Icon(
                    Icons.restaurant_menu_rounded,
                    color: AppColors.orangeBright,
                    size: 36,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Meal details',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Add the meal information you want to log.',
                        style: TextStyle(color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () {
                    _syncDraft();
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go(CreateCanvasDestination.photo.route);
                    }
                  },
                  child: const Text('Change'),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const _Label(label: 'Meal Name'),
          const SizedBox(height: 8),
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(hintText: 'Meal name'),
            textInputAction: TextInputAction.next,
            onChanged: (_) => _syncDraft(),
          ),
          const SizedBox(height: AppSpacing.md),
          const _Label(label: 'Calories (kcal)'),
          const SizedBox(height: 8),
          TextFormField(
            controller: _caloriesController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(hintText: 'Calories'),
            textInputAction: TextInputAction.next,
            onChanged: (_) => _syncDraft(),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _MacroField(
                  label: 'Protein (g)',
                  controller: _proteinController,
                  onChanged: _syncDraft,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _MacroField(
                  label: 'Carbs (g)',
                  controller: _carbsController,
                  onChanged: _syncDraft,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _MacroField(
                  label: 'Fat (g)',
                  controller: _fatController,
                  onChanged: _syncDraft,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const _Label(label: 'Notes (optional)'),
          const SizedBox(height: 8),
          TextFormField(
            controller: _notesController,
            maxLines: 3,
            decoration: const InputDecoration(hintText: 'Notes'),
            onChanged: (_) => _syncDraft(),
          ),
          const SizedBox(height: AppSpacing.md),
          SwitchListTile(
            value: _shareToFeed,
            activeThumbColor: AppColors.orangeBright,
            contentPadding: EdgeInsets.zero,
            title: const Text('Share to feed'),
            subtitle: const Text(
              'Post this meal to your profile activity',
              style: TextStyle(color: AppColors.muted),
            ),
            onChanged: (value) {
              setState(() {
                _shareToFeed = value;
              });
              _syncDraft();
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
                : (_shareToFeed ? 'Save Meal & Share' : 'Save Meal'),
            onPressed: _isSaving ? null : _saveMeal,
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontWeight: FontWeight.w700,
        color: AppColors.white,
      ),
    );
  }
}

class _MacroField extends StatelessWidget {
  const _MacroField({
    required this.label,
    required this.controller,
    required this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Label(label: label),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
          onChanged: (_) => onChanged(),
        ),
      ],
    );
  }
}
