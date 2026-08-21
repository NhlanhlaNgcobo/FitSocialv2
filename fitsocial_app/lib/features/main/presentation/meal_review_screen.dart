import '../../../shared/widgets/quick_toast.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/dark_card.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/share_to_feed_toggle.dart';
import '../application/activity_actions.dart';
import '../application/create_flow_controller.dart';
import '../data/content_repository.dart';
import '../domain/app_models.dart';
import '../../music/presentation/music_island_action.dart';
import '../../../shared/widgets/liquid_glass.dart';

/// The three macros, each with a colour it keeps everywhere on this screen —
/// the split bar, the field tiles and the per-item readouts all agree, so a
/// glance at the bar maps onto a number without a legend.
const Color _proteinColor = AppColors.orangeBright;
const Color _carbsColor = Color(0xFF4FB6A5);
const Color _fatColor = Color(0xFFF5C451);

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

  /// Every field the hero summary and the split bar read from, merged so both
  /// repaint as the user types without a `setState` on each keystroke.
  late final Listenable _summary;

  bool _shareToFeed = true;
  bool _isSaving = false;
  String? _errorMessage;
  String? _imageUrl;

  /// The analysed breakdown. Editing a portion here rewrites the totals, so
  /// the numbers saved always match the items they came from.
  List<MealFoodItem> _items = const [];
  String? _confidence;
  double? _databaseCoverage;

  /// Whether the macro fields are driven by [_items].
  ///
  /// Sticky once set, so clearing the last item zeroes the totals instead of
  /// leaving the numbers of a breakdown that no longer exists. A meal typed in
  /// by hand never sets it, and its fields are left alone.
  bool _itemisedMeal = false;

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
    _summary = Listenable.merge([
      _nameController,
      _caloriesController,
      _proteinController,
      _carbsController,
      _fatController,
    ]);
    _shareToFeed = draft.shareToFeed;
    _imageUrl = draft.imageUrl;
    _items = draft.items;
    _itemisedMeal = draft.items.isNotEmpty;
    _confidence = draft.confidence;
    _databaseCoverage = draft.databaseCoverage;
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

  /// Writes the item totals into the macro fields.
  ///
  /// Called after any change to [_items] so the saved figures and the
  /// breakdown can't drift apart — the whole point of resolving items against
  /// the nutrition database is that the total is the sum of real values.
  void _applyItemTotals() {
    if (!_itemisedMeal) return;
    final totals = MacroTotals.of(_items);
    _caloriesController.text = totals.calories.toString();
    _proteinController.text = totals.protein.toString();
    _carbsController.text = totals.carbs.toString();
    _fatController.text = totals.fat.toString();
  }

  void _updateItem(int index, MealFoodItem item) {
    setState(() {
      final next = [..._items];
      next[index] = item;
      _items = next;
      _applyItemTotals();
    });
    _syncDraft();
  }

  void _removeItem(int index) {
    final removed = _items[index];
    setState(() {
      final next = [..._items]..removeAt(index);
      _items = next;
      _applyItemTotals();
    });
    _syncDraft();

    showQuickToast(
      context,
      'Removed ${removed.name}',
      icon: Icons.remove_circle_outline_rounded,
      actionLabel: 'Undo',
      onAction: () {
        setState(() {
          final next = [..._items]..insert(index, removed);
          _items = next;
          _applyItemTotals();
        });
        _syncDraft();
      },
    );
  }

  /// Adds a food the analyzer missed, straight from the nutrition database.
  Future<void> _addFoodFromDatabase() async {
    final food = await showModalBottomSheet<FoodSearchResult>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (context) => LiquidGlass(
              // A sheet always has a page behind it, which makes it the one
              // surface in the app guaranteed something worth bending.
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
              child: _FoodSearchSheet(
                search: (query) =>
                    ref.read(contentRepositoryProvider).searchFoods(query),
              ),
            ));

    if (food == null || !mounted) return;

    setState(() {
      _itemisedMeal = true;
      _items = [..._items, food.toItem(food.defaultPortionGrams)];
      _applyItemTotals();
    });
    _syncDraft();
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
              items: _items,
            ),
          );
      if (!mounted) return;
      ref.read(createFlowControllerProvider.notifier).completeMeal(
            result.message,
          );
      showQuickToast(context, result.message, tone: ToastTone.success);
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
      items: _items,
      confidence: _confidence,
      databaseCoverage: _databaseCoverage,
    );
  }

  void _syncDraft() {
    ref.read(createFlowControllerProvider.notifier).updateMeal(_currentDraft);
  }

  void _changePhoto() {
    _syncDraft();
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(CreateCanvasDestination.photo.route);
    }
  }

  int _valueOf(TextEditingController controller) =>
      int.tryParse(controller.text.trim()) ?? 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Transparent so this page sits on the app's one backdrop, the
      // same ground every other screen looks through.
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Meal Review'),
        actions: const [MusicIslandAction()],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.md,
        ),
        children: [
          _buildHero(context),
          const SizedBox(height: AppSpacing.lg),
          const _SectionLabel('Meal name'),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: _nameController,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'e.g. Grilled chicken salad',
              prefixIcon: Icon(Icons.restaurant_rounded, size: 20),
            ),
            textInputAction: TextInputAction.next,
            onChanged: (_) => _syncDraft(),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (_items.isNotEmpty)
            _BreakdownCard(
              items: _items,
              confidence: _confidence,
              onGramsChanged: (index, grams) =>
                  _updateItem(index, _items[index].withGrams(grams)),
              onRemove: _removeItem,
              onAddFood: _addFoodFromDatabase,
            )
          else
            _EmptyBreakdownCard(onAddFood: _addFoodFromDatabase),
          const SizedBox(height: AppSpacing.lg),
          _buildNutritionCard(context),
          const SizedBox(height: AppSpacing.lg),
          const _SectionLabel('Notes'),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: _notesController,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Anything worth remembering about this meal',
            ),
            onChanged: (_) => _syncDraft(),
          ),
          const SizedBox(height: AppSpacing.lg),
          ShareToFeedToggle(
            value: _shareToFeed,
            subtitle: 'Post this meal to your profile activity',
            onChanged: (value) {
              setState(() {
                _shareToFeed = value;
              });
              _syncDraft();
            },
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: AppSpacing.md),
            _ErrorBanner(message: _errorMessage!),
          ],
        ],
      ),
      bottomNavigationBar: _SaveBar(
        label: _isSaving
            ? 'Saving...'
            : (_shareToFeed ? 'Save Meal & Share' : 'Save Meal'),
        isSaving: _isSaving,
        onPressed: _isSaving ? null : _saveMeal,
      ),
    );
  }

  /// The photo, with the running totals burned into the bottom of it.
  ///
  /// The numbers are a readout of the fields below rather than a second copy —
  /// they follow every edit, so the picture and the figures can't disagree.
  Widget _buildHero(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: SizedBox(
        height: 224,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_imageUrl != null)
              Image.network(
                _imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const _HeroBackdrop(),
                loadingBuilder: (context, child, progress) =>
                    progress == null ? child : const _HeroBackdrop(),
              )
            else
              const _HeroBackdrop(),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x00000000),
                    Color(0x8A000000),
                    Color(0xE0000000),
                  ],
                  stops: [0.32, 0.7, 1],
                ),
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: _GlassButton(
                icon: Icons.photo_camera_rounded,
                label: 'Change',
                onTap: _changePhoto,
              ),
            ),
            Positioned(
              left: AppSpacing.md,
              right: AppSpacing.md,
              bottom: AppSpacing.md,
              child: AnimatedBuilder(
                animation: _summary,
                builder: (context, _) {
                  final name = _nameController.text.trim();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name.isEmpty ? 'Untitled meal' : _titleCase(name),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: name.isEmpty
                              ? AppColors.onMediaMuted
                              : AppColors.onMedia,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                '${_valueOf(_caloriesController)}',
                                style: const TextStyle(
                                  color: AppColors.onMedia,
                                  fontSize: 30,
                                  height: 1,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Text(
                                'kcal',
                                style: TextStyle(
                                  color: AppColors.onMediaMuted,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _HeroMacro(
                                    label: 'P',
                                    value: _valueOf(_proteinController),
                                    color: _proteinColor,
                                  ),
                                  const SizedBox(width: 12),
                                  _HeroMacro(
                                    label: 'C',
                                    value: _valueOf(_carbsController),
                                    color: _carbsColor,
                                  ),
                                  const SizedBox(width: 12),
                                  _HeroMacro(
                                    label: 'F',
                                    value: _valueOf(_fatController),
                                    color: _fatColor,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Calories and the three macros in one card: a large editable total, the
  /// split bar underneath it, then the macro tiles that feed both.
  Widget _buildNutritionCard(BuildContext context) {
    final palette = context.palette;

    return DarkCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _SectionLabel('Total calories'),
              const Spacer(),
              if (_itemisedMeal)
                Text(
                  'From items',
                  style: TextStyle(
                    color: palette.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: TextField(
                  controller: _caloriesController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textInputAction: TextInputAction.next,
                  cursorColor: AppColors.orangeBright,
                  style: const TextStyle(
                    fontSize: 34,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                    color: AppColors.orangeBright,
                  ),
                  decoration: InputDecoration(
                    filled: false,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    hintText: '0',
                    hintStyle: TextStyle(
                      fontSize: 34,
                      height: 1.1,
                      fontWeight: FontWeight.w800,
                      color: palette.muted,
                    ),
                  ),
                  onChanged: (_) => _syncDraft(),
                ),
              ),
              Text(
                'kcal',
                style: TextStyle(
                  color: palette.muted,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          AnimatedBuilder(
            animation: _summary,
            builder: (context, _) => _MacroSplitBar(
              protein: _valueOf(_proteinController),
              carbs: _valueOf(_carbsController),
              fat: _valueOf(_fatController),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _MacroField(
                  label: 'Protein',
                  color: _proteinColor,
                  controller: _proteinController,
                  onChanged: _syncDraft,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _MacroField(
                  label: 'Carbs',
                  color: _carbsColor,
                  controller: _carbsController,
                  onChanged: _syncDraft,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _MacroField(
                  label: 'Fat',
                  color: _fatColor,
                  controller: _fatController,
                  onChanged: _syncDraft,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The action bar pinned under the list.
///
/// It is the Scaffold's `bottomNavigationBar` rather than the last row of the
/// list, so the button is always reachable, and its [SafeArea] lifts it clear
/// of the gesture pill or the three-button nav instead of sitting under them.
class _SaveBar extends StatelessWidget {
  const _SaveBar({
    required this.label,
    required this.isSaving,
    required this.onPressed,
  });

  final String label;
  final bool isSaving;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return LiquidGlass(
      // Painted by the lens rather than by a fill of its own: a pane
      // over the app backdrop, like every other card.
      borderRadius: BorderRadius.circular(0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: palette.stroke)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: PrimaryButton(
              label: label,
              icon: isSaving ? null : Icons.check_rounded,
              onPressed: onPressed,
            ),
          ),
        ),
      ),
    );
  }
}

/// The stand-in behind the hero when there is no photo, or while one loads.
///
/// Deliberately dark in both themes: it stands in for media, and a cream block
/// under the white hero text would leave that text unreadable in light mode.
class _HeroBackdrop extends StatelessWidget {
  const _HeroBackdrop();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A1A0B), AppColors.mediaBackdrop],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.restaurant_menu_rounded,
          size: 44,
          color: AppColors.orangeBright,
        ),
      ),
    );
  }
}

class _HeroMacro extends StatelessWidget {
  const _HeroMacro({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          '$label ${value}g',
          style: const TextStyle(
            color: AppColors.onMedia,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _GlassButton extends StatelessWidget {
  const _GlassButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0x66000000),
      shape: const StadiumBorder(
        side: BorderSide(color: Color(0x33FFFFFF)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: AppColors.onMedia),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.onMedia,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// How the calories split across the three macros, at 4/4/9 kcal per gram.
class _MacroSplitBar extends StatelessWidget {
  const _MacroSplitBar({
    required this.protein,
    required this.carbs,
    required this.fat,
  });

  final int protein;
  final int carbs;
  final int fat;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final proteinKcal = protein * 4;
    final carbsKcal = carbs * 4;
    final fatKcal = fat * 9;
    final total = proteinKcal + carbsKcal + fatKcal;

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 8,
        child: total <= 0
            ? ColoredBox(color: palette.surfaceHigh)
            : LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  return Row(
                    children: [
                      for (final segment in [
                        (proteinKcal, _proteinColor),
                        (carbsKcal, _carbsColor),
                        (fatKcal, _fatColor),
                      ])
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOut,
                          width: width * segment.$1 / total,
                          color: segment.$2,
                        ),
                    ],
                  );
                },
              ),
      ),
    );
  }
}

/// The itemised analysis: what was recognised, how much of it, and where each
/// item's macros came from.
class _BreakdownCard extends StatelessWidget {
  const _BreakdownCard({
    required this.items,
    required this.confidence,
    required this.onGramsChanged,
    required this.onRemove,
    required this.onAddFood,
  });

  final List<MealFoodItem> items;
  final String? confidence;
  final void Function(int index, int grams) onGramsChanged;
  final void Function(int index) onRemove;
  final VoidCallback onAddFood;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final matched = items.where((item) => item.source.isFromDatabase).length;

    return DarkCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: palette.brandSoft,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  size: 17,
                  color: palette.brand,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Detected foods',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
              if (confidence != null) _ConfidenceChip(confidence: confidence!),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            matched == items.length
                ? 'All ${items.length} items matched the nutrition database. '
                    'Adjust a portion and the macros update.'
                : '$matched of ${items.length} items matched the nutrition '
                    'database. The rest are estimates worth checking.',
            style: TextStyle(
              color: palette.muted,
              fontSize: 13,
              height: 1.35,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          for (var index = 0; index < items.length; index++) ...[
            if (index > 0) const SizedBox(height: AppSpacing.sm),
            _FoodItemTile(
              // Keyed by identity so each tile keeps its own text field state
              // when the list around it changes.
              key: ValueKey(
                  '${items[index].foodId ?? items[index].name}-$index'),
              item: items[index],
              onGramsChanged: (grams) => onGramsChanged(index, grams),
              onRemove: () => onRemove(index),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          _AddFoodButton(onTap: onAddFood),
        ],
      ),
    );
  }
}

/// Shown when nothing was detected — or when the meal was typed in by hand.
class _EmptyBreakdownCard extends StatelessWidget {
  const _EmptyBreakdownCard({required this.onAddFood});

  final VoidCallback onAddFood;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return DarkCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: palette.surfaceHigh,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.search_rounded,
              color: palette.muted,
              size: 20,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'No foods detected',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'Add foods from the nutrition database and the macros below fill '
            'in for you.',
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.muted, fontSize: 13, height: 1.35),
          ),
          const SizedBox(height: AppSpacing.md),
          _AddFoodButton(onTap: onAddFood),
        ],
      ),
    );
  }
}

class _AddFoodButton extends StatelessWidget {
  const _AddFoodButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.add_rounded, size: 18),
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.brandText,
          padding: const EdgeInsets.symmetric(vertical: 14),
          side: BorderSide(color: palette.stroke),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        label: const Text('Add a food'),
      ),
    );
  }
}

/// Searches the nutrition database and returns the food the user picks.
///
/// The pick is added at the food's typical portion; the breakdown list is
/// where the weight then gets corrected, so there is no second step here.
class _FoodSearchSheet extends StatefulWidget {
  const _FoodSearchSheet({required this.search});

  final Future<List<FoodSearchResult>> Function(String query) search;

  @override
  State<_FoodSearchSheet> createState() => _FoodSearchSheetState();
}

class _FoodSearchSheetState extends State<_FoodSearchSheet> {
  final TextEditingController _queryController = TextEditingController();
  Timer? _debounce;
  List<FoodSearchResult> _results = const [];
  bool _isSearching = false;
  String? _error;

  /// Guards against an earlier, slower search overwriting a later one.
  int _requestId = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _queryController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.length < 2) {
      setState(() {
        _results = const [];
        _isSearching = false;
        _error = null;
      });
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => _runSearch(query),
    );
  }

  Future<void> _runSearch(String query) async {
    final requestId = ++_requestId;
    setState(() {
      _isSearching = true;
      _error = null;
    });

    try {
      final results = await widget.search(query);
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _results = results;
        _isSearching = false;
      });
    } catch (error) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _isSearching = false;
        _error = 'Could not search foods: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: palette.stroke,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              const Text(
                'Add a food',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                'Macros come from the nutrition database. It is added at a '
                'typical portion — adjust the grams afterwards.',
                style: TextStyle(color: palette.muted, fontSize: 13),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _queryController,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: 'Search foods, e.g. pap, chicken breast',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
                onChanged: _onQueryChanged,
              ),
              const SizedBox(height: AppSpacing.md),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.4,
                ),
                child: _buildResults(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResults() {
    final palette = context.palette;
    if (_isSearching) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.orangeBright,
            ),
          ),
        ),
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Text(
          _error!,
          style: TextStyle(color: palette.danger, fontSize: 13),
        ),
      );
    }

    if (_results.isEmpty) {
      final hasQuery = _queryController.text.trim().length >= 2;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Text(
          hasQuery
              ? 'No matching food. Type the totals in by hand instead.'
              : 'Start typing to search.',
          style: TextStyle(color: palette.muted, fontSize: 13),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      itemCount: _results.length,
      separatorBuilder: (_, __) => Divider(color: palette.stroke, height: 1),
      itemBuilder: (context, index) {
        final food = _results[index];
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            food.name,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          subtitle: Text(
            '${food.per100g.calories.round()} kcal · '
            'P ${food.per100g.protein.round()}g · '
            'C ${food.per100g.carbs.round()}g · '
            'F ${food.per100g.fat.round()}g per 100g',
            style: TextStyle(color: palette.muted, fontSize: 12),
          ),
          trailing: Text(
            '${food.defaultPortionGrams}g',
            style: TextStyle(color: palette.muted, fontSize: 12),
          ),
          onTap: () => Navigator.of(context).pop(food),
        );
      },
    );
  }
}

class _FoodItemTile extends StatefulWidget {
  const _FoodItemTile({
    super.key,
    required this.item,
    required this.onGramsChanged,
    required this.onRemove,
  });

  final MealFoodItem item;
  final ValueChanged<int> onGramsChanged;
  final VoidCallback onRemove;

  @override
  State<_FoodItemTile> createState() => _FoodItemTileState();
}

class _FoodItemTileState extends State<_FoodItemTile> {
  /// How much a tap of − or + moves the portion. Meal-sized rather than
  /// gram-sized, so correcting a 254 g block takes a few taps, not fifty.
  static const int _step = 10;

  late final TextEditingController _gramsController;

  @override
  void initState() {
    super.initState();
    _gramsController = TextEditingController(
      text: widget.item.grams?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _gramsController.dispose();
    super.dispose();
  }

  void _commitGrams(String value) {
    final grams = int.tryParse(value.trim());
    if (grams != null && grams > 0 && grams != widget.item.grams) {
      widget.onGramsChanged(grams);
    }
  }

  void _nudge(int delta) {
    final current =
        widget.item.grams ?? int.tryParse(_gramsController.text.trim()) ?? 0;
    final next = (current + delta).clamp(_step, 5000);
    if (next == current) return;
    _gramsController.text = next.toString();
    widget.onGramsChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final item = widget.item;
    final matched = item.matchedFood;

    return LiquidGlass(
      // Painted by the lens rather than by a fill of its own: a pane
      // over the app backdrop, like every other card.
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: palette.stroke),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _titleCase(item.name),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: palette.text,
                          ),
                        ),
                        if (matched != null &&
                            matched.toLowerCase() !=
                                item.name.toLowerCase()) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Matched: $matched',
                            style: TextStyle(
                              color: palette.muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: _SourceBadge(source: item.source),
                ),
                IconButton(
                  onPressed: widget.onRemove,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: palette.muted,
                  ),
                  tooltip: 'Remove item',
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _GramsStepper(
                  controller: _gramsController,
                  onCommit: _commitGrams,
                  onDecrement: () => _nudge(-_step),
                  onIncrement: () => _nudge(_step),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${item.calories} kcal',
                        style: TextStyle(
                          color: palette.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      // Scaled down rather than wrapped: on a narrow phone the
                      // three pips are still one glanceable line.
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _MacroPip(
                              label: 'P',
                              value: item.protein,
                              color: _proteinColor,
                            ),
                            const SizedBox(width: 8),
                            _MacroPip(
                              label: 'C',
                              value: item.carbs,
                              color: _carbsColor,
                            ),
                            const SizedBox(width: 8),
                            _MacroPip(
                              label: 'F',
                              value: item.fat,
                              color: _fatColor,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (item.per100g == null && item.grams != null) ...[
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 13,
                    color: palette.muted,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Not in the database — changing the weight will not '
                      'recalculate these macros.',
                      style: TextStyle(
                        color: palette.muted,
                        fontSize: 11,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The portion control: − and + for quick corrections, the field itself for
/// when the packet says 254.
class _GramsStepper extends StatelessWidget {
  const _GramsStepper({
    required this.controller,
    required this.onCommit,
    required this.onDecrement,
    required this.onIncrement,
  });

  final TextEditingController controller;
  final ValueChanged<String> onCommit;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.stroke),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepIcon(icon: Icons.remove_rounded, onTap: onDecrement),
          SizedBox(
            width: 46,
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textInputAction: TextInputAction.done,
              textAlign: TextAlign.center,
              cursorColor: AppColors.orangeBright,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: palette.text,
              ),
              decoration: const InputDecoration(
                filled: false,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
              onChanged: onCommit,
              onSubmitted: onCommit,
            ),
          ),
          Text(
            'g',
            style: TextStyle(
              color: palette.muted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          _StepIcon(icon: Icons.add_rounded, onTap: onIncrement),
        ],
      ),
    );
  }
}

class _StepIcon extends StatelessWidget {
  const _StepIcon({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 22,
      child: SizedBox(
        width: 36,
        height: 40,
        child: Icon(icon, size: 16, color: AppColors.orangeBright),
      ),
    );
  }
}

class _MacroPip extends StatelessWidget {
  const _MacroPip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          '$label ${value}g',
          style: TextStyle(
            color: context.palette.muted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.source});

  final MacroSource source;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final fromDatabase = source.isFromDatabase;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: fromDatabase
            ? palette.brandSoft
            : palette.overlay.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: fromDatabase ? palette.brandSoftStroke : palette.stroke,
        ),
      ),
      child: Text(
        source.label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          color: fromDatabase ? palette.brandText : palette.muted,
        ),
      ),
    );
  }
}

class _ConfidenceChip extends StatelessWidget {
  const _ConfidenceChip({required this.confidence});

  final String confidence;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final level = confidence.toLowerCase();
    final color = switch (level) {
      'high' => palette.success,
      'low' => palette.danger,
      _ => _fatColor,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            '${confidence[0].toUpperCase()}${confidence.substring(1)}',
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.danger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.danger.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, size: 18, color: palette.danger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: palette.danger,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _titleCase(String value) {
  if (value.isEmpty) return value;
  return value[0].toUpperCase() + value.substring(1);
}

/// The quiet all-caps label that heads each section.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.9,
        color: context.palette.muted,
      ),
    );
  }
}

/// One macro: a coloured dot, its name, and the grams under both.
class _MacroField extends StatelessWidget {
  const _MacroField({
    required this.label,
    required this.color,
    required this.controller,
    required this.onChanged,
  });

  final String label;
  final Color color;
  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return LiquidGlass(
      // Painted by the lens rather than by a fill of its own: a pane
      // over the app backdrop, like every other card.
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: palette.stroke),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    textInputAction: TextInputAction.next,
                    cursorColor: AppColors.orangeBright,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: palette.text,
                    ),
                    decoration: InputDecoration(
                      filled: false,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      hintText: '0',
                      hintStyle: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: palette.muted,
                      ),
                    ),
                    onChanged: (_) => onChanged(),
                  ),
                ),
                Text(
                  'g',
                  style: TextStyle(
                    color: palette.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
