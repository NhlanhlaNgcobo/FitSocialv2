import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/liquid_glass.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/quick_toast.dart';
import '../application/content_providers.dart';
import '../data/content_repository.dart';
import '../domain/meal_repeat.dart';
import '../domain/meal_tracking.dart';

/// What can be done with a logged meal: log it again now, or put it on a
/// schedule.
Future<void> showMealActionsSheet(
  BuildContext context,
  WidgetRef ref,
  LoggedMeal meal,
) async {
  final action = await showModalBottomSheet<_MealAction>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => _MealActionsSheet(meal: meal),
  );
  if (action == null || !context.mounted) return;

  switch (action) {
    case _MealAction.logAgain:
      try {
        await ref.read(contentRepositoryProvider).relogMeal(meal);
        ref.invalidate(loggedMealsProvider);
        if (context.mounted) {
          showQuickToast(
            context,
            '${meal.displayName} logged again.',
            tone: ToastTone.success,
          );
        }
      } catch (error) {
        if (context.mounted) {
          showQuickToast(
            context,
            'Could not log it again. Try once more.',
            icon: Icons.error_outline_rounded,
          );
        }
      }
    case _MealAction.repeat:
      await showMealRepeatSheet(context, ref, meal: meal);
  }
}

/// Sets up a repeat for [meal], or edits [existing]. Exactly one is given.
Future<void> showMealRepeatSheet(
  BuildContext context,
  WidgetRef ref, {
  LoggedMeal? meal,
  MealRepeat? existing,
}) async {
  assert((meal == null) != (existing == null));
  final now = DateTime.now();
  final initial = existing ??
      MealRepeat.fromMeal(
        meal!,
        id: now.microsecondsSinceEpoch.toRadixString(36),
        // Every day to start with: the commonest repeat is the same
        // breakfast, and trimming days is quicker than adding them.
        weekdays: const {1, 2, 3, 4, 5, 6, 7},
        today: now,
      );

  final result = await showModalBottomSheet<_RepeatResult>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _MealRepeatSheet(
      initial: initial,
      isNew: existing == null,
    ),
  );
  if (result == null || !context.mounted) return;

  final repository = ref.read(contentRepositoryProvider);
  try {
    final message = switch (result) {
      _SaveRepeat(:final repeat) => await repository
          .saveMealRepeat(repeat)
          .then((_) => '${repeat.name}: ${repeat.scheduleLabel}.'),
      _DeleteRepeat() => await repository
          .deleteMealRepeat(initial.id)
          .then((_) => '${initial.name} will not repeat any more.'),
    };
    ref.invalidate(mealRepeatsProvider);
    if (context.mounted) {
      showQuickToast(context, message, tone: ToastTone.success);
    }
  } catch (error) {
    if (context.mounted) {
      showQuickToast(
        context,
        error is StateError ? error.message : 'Could not save the repeat.',
        icon: Icons.error_outline_rounded,
      );
    }
  }
}

enum _MealAction { logAgain, repeat }

sealed class _RepeatResult {
  const _RepeatResult();
}

class _SaveRepeat extends _RepeatResult {
  const _SaveRepeat(this.repeat);
  final MealRepeat repeat;
}

class _DeleteRepeat extends _RepeatResult {
  const _DeleteRepeat();
}

/// The glass panel both sheets are drawn on, matching the macro goals sheet.
class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: LiquidGlass(
        lens: true,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: palette.stroke),
          ),
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(child: child),
          ),
        ),
      ),
    );
  }
}

class _MealActionsSheet extends StatelessWidget {
  const _MealActionsSheet({required this.meal});

  final LoggedMeal meal;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return _SheetFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            meal.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: palette.text,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _ActionTile(
            icon: Icons.replay_rounded,
            title: 'Log again now',
            subtitle: 'Same foods and portions, logged privately.',
            onTap: () => Navigator.of(context).pop(_MealAction.logAgain),
          ),
          const SizedBox(height: AppSpacing.sm),
          _ActionTile(
            icon: Icons.event_repeat_rounded,
            title: 'Repeat this meal',
            subtitle: 'Logged for you on the days you pick.',
            onTap: () => Navigator.of(context).pop(_MealAction.repeat),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: palette.stroke),
        ),
        child: Row(
          children: [
            Icon(icon, color: palette.brand, size: 22),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: palette.text,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(color: palette.muted, fontSize: 12.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MealRepeatSheet extends StatefulWidget {
  const _MealRepeatSheet({required this.initial, required this.isNew});

  final MealRepeat initial;
  final bool isNew;

  @override
  State<_MealRepeatSheet> createState() => _MealRepeatSheetState();
}

class _MealRepeatSheetState extends State<_MealRepeatSheet> {
  late Set<int> _days = {...widget.initial.weekdays};
  late TimeOfDay _time =
      TimeOfDay(hour: widget.initial.hour, minute: widget.initial.minute);

  void _toggle(int day) {
    setState(() {
      // Never down to no days: a repeat with none would never fire, and the
      // way to stop one is the button below, not an empty row of chips.
      if (_days.contains(day) && _days.length > 1) {
        _days = {..._days}..remove(day);
      } else {
        _days = {..._days, day};
      }
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  void _save() {
    Navigator.of(context).pop(
      _SaveRepeat(
        widget.initial.copyWith(
          weekdays: _days,
          hour: _time.hour,
          minute: _time.minute,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final preview = widget.initial.copyWith(
      weekdays: _days,
      hour: _time.hour,
      minute: _time.minute,
    );

    return _SheetFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Repeat ${widget.initial.name}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: palette.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.isNew
                ? 'Logged for you at this time on these days, starting '
                    'tomorrow. Days the app is not opened are skipped.'
                : 'Logged for you at this time on these days. Days the app is '
                    'not opened are skipped.',
            style: TextStyle(color: palette.muted, fontSize: 13, height: 1.35),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var day = 1; day <= 7; day++)
                _DayChip(
                  label: MealRepeat.weekdayShortNames[day - 1][0],
                  semanticLabel: MealRepeat.weekdayShortNames[day - 1],
                  selected: _days.contains(day),
                  onTap: () => _toggle(day),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: _pickTime,
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: palette.stroke),
              ),
              child: Row(
                children: [
                  Icon(Icons.schedule_rounded, color: palette.muted, size: 20),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Time',
                      style: TextStyle(
                        color: palette.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    preview.timeLabel,
                    style: TextStyle(
                      color: palette.brand,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            preview.scheduleLabel,
            style: TextStyle(color: palette.muted, fontSize: 13),
          ),
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            label: widget.isNew ? 'Start repeating' : 'Save',
            onPressed: _save,
          ),
          if (!widget.isNew) ...[
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () =>
                    Navigator.of(context).pop(const _DeleteRepeat()),
                child: Text(
                  'Stop repeating',
                  style: TextStyle(
                    color: palette.danger,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.label,
    required this.semanticLabel,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String semanticLabel;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      label: semanticLabel,
      selected: selected,
      button: true,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: 24,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected ? palette.brand : Colors.transparent,
            border: Border.all(
              color: selected ? palette.brand : palette.stroke,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? AppColors.onBrand : palette.text,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}
