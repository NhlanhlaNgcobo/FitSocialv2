import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/brand_image_tile.dart';
import '../../../shared/widgets/dark_card.dart';
import '../../../shared/widgets/primary_button.dart';
import '../application/activity_actions.dart';
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

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: 'Grilled Chicken Bowl');
    _caloriesController = TextEditingController(text: '520');
    _proteinController = TextEditingController(text: '45');
    _carbsController = TextEditingController(text: '40');
    _fatController = TextEditingController(text: '18');
    _notesController =
        TextEditingController(text: 'High protein and balanced meal');
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
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final result = await ref.read(activityActionsProvider).saveMeal(
            MealLogDraft(
              name: _nameController.text,
              calories: _caloriesController.text,
              protein: _proteinController.text,
              carbs: _carbsController.text,
              fat: _fatController.text,
              notes: _notesController.text,
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
      appBar: AppBar(title: const Text('Meal Review')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          DarkCard(
            child: Row(
              children: [
                const SizedBox(
                  width: 92,
                  height: 92,
                  child: BrandImageTile(
                    tile: AppVisualTile.mealBowl,
                    borderRadius: BorderRadius.all(Radius.circular(18)),
                    overlay: Color(0x12050505),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Grilled Chicken Bowl',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'AI estimate ready to review',
                        style: TextStyle(color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => context.pop(),
                  child: const Text('Change'),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const _Label(label: 'Meal Name'),
          const SizedBox(height: 8),
          TextFormField(controller: _nameController),
          const SizedBox(height: AppSpacing.md),
          const _Label(label: 'Calories (kcal)'),
          const SizedBox(height: 8),
          TextFormField(controller: _caloriesController),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _MacroField(
                  label: 'Protein (g)',
                  controller: _proteinController,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _MacroField(
                  label: 'Carbs (g)',
                  controller: _carbsController,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _MacroField(
                  label: 'Fat (g)',
                  controller: _fatController,
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
  const _MacroField({required this.label, required this.controller});

  final String label;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Label(label: label),
        const SizedBox(height: 8),
        TextFormField(controller: controller),
      ],
    );
  }
}
