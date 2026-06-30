import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
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
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _caloriesController;
  late final TextEditingController _proteinController;
  late final TextEditingController _carbsController;
  late final TextEditingController _fatController;
  late final TextEditingController _notesController;
  bool _shareToFeed = true;
  bool _isSaving = false;

  String? _imageUrl;
  bool _didInitFromExtra = false;

  @override
  void initState() {
    super.initState();
    // Default empty — will be overridden in didChangeDependencies from route extra.
    _nameController = TextEditingController();
    _caloriesController = TextEditingController();
    _proteinController = TextEditingController();
    _carbsController = TextEditingController();
    _fatController = TextEditingController();
    _notesController = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInitFromExtra) return;
    _didInitFromExtra = true;

    final extra = GoRouterState.of(context).extra;
    if (extra is Map<String, dynamic>) {
      _imageUrl = extra['imageUrl'] as String?;
      _nameController.text = (extra['name'] as String?) ?? '';
      _caloriesController.text = (extra['calories'] as String?) ?? '';
      _proteinController.text = (extra['protein'] as String?) ?? '';
      _carbsController.text = (extra['carbs'] as String?) ?? '';
      _fatController.text = (extra['fat'] as String?) ?? '';
    } else if (extra is String) {
      // Backwards compatibility: plain image path string
      _imageUrl = extra;
    }
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
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
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
              imageUrl: _imageUrl,
            ),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
      context.go('/home');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving meal: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  InputDecoration _buildInputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.muted),
      filled: true,
      fillColor: AppColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Meal Review')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          if (_imageUrl != null) ...[
            DarkCard(
              padding: EdgeInsets.zero,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  _imageUrl!,
                  fit: BoxFit.cover,
                  height: 250,
                  width: double.infinity,
                  errorBuilder: (_, __, ___) => const SizedBox(
                    height: 250,
                    child: Center(
                      child: Icon(Icons.broken_image, color: AppColors.muted, size: 48),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          DarkCard(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _Label(label: 'Meal Name'),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _nameController,
                    style: const TextStyle(color: AppColors.white),
                    decoration: _buildInputDecoration('e.g., Grilled Chicken Bowl'),
                    validator: (value) => value == null || value.isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const _Label(label: 'Calories (kcal)'),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _caloriesController,
                    style: const TextStyle(color: AppColors.white),
                    keyboardType: TextInputType.number,
                    decoration: _buildInputDecoration('e.g., 520'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: _MacroField(
                          label: 'Protein (g)',
                          controller: _proteinController,
                          decoration: _buildInputDecoration('0'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: _MacroField(
                          label: 'Carbs (g)',
                          controller: _carbsController,
                          decoration: _buildInputDecoration('0'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: _MacroField(
                          label: 'Fat (g)',
                          controller: _fatController,
                          decoration: _buildInputDecoration('0'),
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
                    style: const TextStyle(color: AppColors.white),
                    decoration: _buildInputDecoration('Any additional details...'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SwitchListTile(
            value: _shareToFeed,
            activeThumbColor: AppColors.white,
            activeTrackColor: AppColors.orangeBright,
            contentPadding: EdgeInsets.zero,
            title: const Text('Share to feed', style: TextStyle(color: AppColors.white, fontWeight: FontWeight.w600)),
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
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            label: _isSaving
                ? 'Saving...'
                : (_shareToFeed ? 'Save Meal & Share' : 'Save Meal'),
            onPressed: _isSaving ? null : _saveMeal,
          ),
          const SizedBox(height: AppSpacing.xl),
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
  const _MacroField({required this.label, required this.controller, required this.decoration});

  final String label;
  final TextEditingController controller;
  final InputDecoration decoration;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Label(label: label),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          style: const TextStyle(color: AppColors.white),
          keyboardType: TextInputType.number,
          decoration: decoration,
        ),
      ],
    );
  }
}
