import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../application/content_providers.dart';
import '../domain/meal_tracking.dart';
import '../domain/progress_models.dart';
import 'macro_goals_sheet.dart';
import '../../music/presentation/music_island_action.dart';
import '../../../shared/widgets/app_photo.dart';
import '../../../shared/widgets/liquid_glass.dart';

/// The colour each macro keeps, on the summary bars and on the meal rows.
///
/// Calories take the brand orange because they are the headline; the other
/// three are given distinct hues so a glance at a bar maps onto a number
/// without reading the label.
///
/// Takes the palette because these are drawn on an app surface: the three hues
/// below were picked against near-black and need deepening for paper, and the
/// headline follows the brand's own light-mode weight.
Color macroColor(MacroKind kind, AppPalette palette) => switch (kind) {
      MacroKind.calories => palette.brand,
      MacroKind.protein => palette.accent(const Color(0xFF4FB6A5)),
      MacroKind.carbs => palette.accent(const Color(0xFF5B9FD4)),
      MacroKind.fat => palette.accent(const Color(0xFFB07FE8)),
    };

/// Meal tracking: what was eaten in a window, against what was aimed for.
///
/// The periods stop at Month rather than offering the Year the Progress tab
/// does. A year of eating against a daily target is a number nobody acts on,
/// and the meal list under it would run to thousands of rows.
const List<ProgressPeriod> _mealPeriods = [
  ProgressPeriod.day,
  ProgressPeriod.week,
  ProgressPeriod.month,
];

class MealTrackingScreen extends ConsumerStatefulWidget {
  const MealTrackingScreen({super.key});

  @override
  ConsumerState<MealTrackingScreen> createState() => _MealTrackingScreenState();
}

class _MealTrackingScreenState extends ConsumerState<MealTrackingScreen> {
  ProgressPeriod _period = ProgressPeriod.day;

  /// How many periods back from the current one the user has paged.
  int _offset = 0;

  ProgressWindow get _window => ProgressWindow.forOffset(_period, _offset);

  void _selectPeriod(ProgressPeriod period) {
    setState(() {
      _period = period;
      // Offsets do not carry across periods — five days back and five months
      // back are nowhere near each other. Switching returns to the present.
      _offset = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final window = _window;
    final summary = ref.watch(mealWindowSummaryProvider(window));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Meal Summary'),
        actions: const [MusicIslandAction()],
      ),
      body: RefreshIndicator(
        color: context.palette.brand,
        onRefresh: () async {
          ref
            ..invalidate(loggedMealsProvider)
            ..invalidate(macroGoalsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.xl,
          ),
          children: [
            _PeriodPicker(selected: _period, onSelected: _selectPeriod),
            const SizedBox(height: AppSpacing.md),
            _DateNavigator(
              window: window,
              onPrevious: () => setState(() => _offset -= 1),
              // Null past the current period — nobody has eaten tomorrow yet.
              onNext:
                  window.isCurrent ? null : () => setState(() => _offset += 1),
            ),
            const SizedBox(height: AppSpacing.md),
            summary.when(
              loading: () => const _SummarySkeleton(),
              error: (error, _) => _SummaryError(
                onRetry: () => ref.invalidate(loggedMealsProvider),
              ),
              data: (data) => _SummaryBody(summary: data),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryBody extends StatelessWidget {
  const _SummaryBody({required this.summary});

  final MealWindowSummary summary;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MacroSummaryCard(summary: summary),
        const SizedBox(height: AppSpacing.md),
        _MealsLoggedCard(summary: summary),
      ],
    );
  }
}

/// Day / Week / Month.
class _PeriodPicker extends StatelessWidget {
  const _PeriodPicker({required this.selected, required this.onSelected});

  final ProgressPeriod selected;
  final ValueChanged<ProgressPeriod> onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return LiquidGlass(
      // Painted by the lens rather than by a fill of its own: a pane
      // over the app backdrop, like every other card.
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: palette.stroke),
        ),
        child: Row(
          children: [
            for (final period in _mealPeriods)
              Expanded(
                child: GestureDetector(
                  onTap: () => onSelected(period),
                  child: Container(
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: period == selected
                          ? palette.brandSoft
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      period.label,
                      style: TextStyle(
                        color: period == selected
                            ? palette.brandText
                            : palette.muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DateNavigator extends StatelessWidget {
  const _DateNavigator({
    required this.window,
    required this.onPrevious,
    required this.onNext,
  });

  final ProgressWindow window;
  final VoidCallback onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Row(
      children: [
        IconButton(
          onPressed: onPrevious,
          tooltip: 'Previous',
          icon: Icon(Icons.chevron_left_rounded, color: palette.muted),
        ),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.calendar_today_rounded,
                size: 15,
                color: palette.muted,
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  mealWindowLabel(window),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: onNext,
          tooltip: 'Next',
          icon: Icon(
            Icons.chevron_right_rounded,
            // Dimmed rather than removed, so the row keeps its shape at the
            // present rather than the label sliding sideways.
            color: onNext == null ? palette.stroke : palette.muted,
          ),
        ),
      ],
    );
  }
}

/// The four macros with their totals, targets and progress bars.
class _MacroSummaryCard extends ConsumerWidget {
  const _MacroSummaryCard({required this.summary});

  final MealWindowSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Macronutrient Summary',
                  style: TextStyle(
                    color: palette.text,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              // The targets have to be reachable from where they are shown —
              // every denominator on this card comes from them.
              IconButton(
                onPressed: () => showMacroGoalsSheet(context, ref),
                tooltip: 'Edit targets',
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.tune_rounded, size: 18, color: palette.muted),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final progress in summary.allProgress) ...[
                Expanded(child: _MacroColumn(progress: progress)),
                if (progress.kind != MacroKind.fat)
                  const SizedBox(width: AppSpacing.sm),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _InsightRow(summary: summary),
        ],
      ),
    );
  }
}

class _MacroColumn extends StatelessWidget {
  const _MacroColumn({required this.progress});

  final MacroProgress progress;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = macroColor(progress.kind, palette);
    final unit = progress.kind.unit;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          progress.kind.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        // Scales down rather than wrapping: four columns on a narrow phone
        // leave little room, and "1 842" must stay on one line.
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            progress.kind == MacroKind.calories
                ? formatMacroValue(progress.total)
                : '${formatMacroValue(progress.total)} $unit',
            maxLines: 1,
            style: TextStyle(
              color: palette.text,
              fontSize: 19,
              height: 1.1,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            '/ ${formatMacroValue(progress.goal)} $unit',
            maxLines: 1,
            style: TextStyle(color: palette.muted, fontSize: 11.5),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            minHeight: 5,
            value: progress.fraction,
            backgroundColor: palette.stroke,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${progress.percent}%',
          style: TextStyle(
            // Over target is stated in the app's danger colour rather than the
            // macro's own — the percentage is the only thing on the card that
            // can report a problem, and the bar has already run out of track.
            color: progress.isOver ? palette.danger : palette.muted,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _InsightRow extends StatelessWidget {
  const _InsightRow({required this.summary});

  final MealWindowSummary summary;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return LiquidGlass(
      // Painted by the lens rather than by a fill of its own: a pane
      // over the app backdrop, like every other card.
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 12,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: palette.success.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.insights_rounded,
                size: 17,
                color: palette.success,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                summary.insight,
                style: TextStyle(
                  color: palette.muted,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The meals themselves, in the order they were eaten.
class _MealsLoggedCard extends StatelessWidget {
  const _MealsLoggedCard({required this.summary});

  final MealWindowSummary summary;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Meals Logged',
                  style: TextStyle(
                    color: palette.text,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              if (summary.meals.isNotEmpty)
                Text(
                  '${summary.meals.length}',
                  style: TextStyle(
                    color: palette.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (summary.isEmpty)
            const _NoMeals()
          else
            for (final meal in summary.meals) _MealRow(meal: meal),
          const SizedBox(height: AppSpacing.sm),
          const _LogAnotherMealButton(),
        ],
      ),
    );
  }
}

class _MealRow extends StatelessWidget {
  const _MealRow({required this.meal});

  final LoggedMeal meal;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      // A shared meal has a post to open; one logged privately has nowhere to
      // go, so it is not made to look tappable.
      onTap: meal.postId == null
          ? null
          : () => context.push('/post/${meal.postId}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            _MealThumbnail(imageUrl: meal.imageUrl),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    meal.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.text,
                      fontWeight: FontWeight.w700,
                      fontSize: 14.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    meal.timeLabel,
                    style: TextStyle(color: palette.muted, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  _MacroChips(meal: meal),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: formatMacroValue(meal.calories),
                        style: TextStyle(
                          color: palette.text,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      TextSpan(
                        text: ' kcal',
                        style: TextStyle(color: palette.muted, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (meal.postId != null)
              Icon(Icons.chevron_right_rounded, color: palette.muted, size: 20),
          ],
        ),
      ),
    );
  }
}

/// P / C / F under a meal's name, each in its macro's colour.
class _MacroChips extends StatelessWidget {
  const _MacroChips({required this.meal});

  final LoggedMeal meal;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    int gramsOf(MacroKind kind) => switch (kind) {
          MacroKind.protein => meal.protein,
          MacroKind.carbs => meal.carbs,
          MacroKind.fat => meal.fat,
          MacroKind.calories => 0,
        };

    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: 4,
      children: [
        for (final kind in const [
          MacroKind.protein,
          MacroKind.carbs,
          MacroKind.fat,
        ])
          Text(
            '${kind.shortLabel} ${gramsOf(kind)}g',
            style: TextStyle(
              color: macroColor(kind, palette),
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
      ],
    );
  }
}

/// The meal's photo, at the head of its row.
///
/// A plate shrunk to a row-sized square is the only picture on this screen, so
/// it gets the treatment a photograph deserves rather than a bare crop: a warm
/// bed to sit on while it downloads, a lit rim so the crop doesn't dissolve
/// into the card behind it, and a fade rather than a pop when the pixels land.
class _MealThumbnail extends StatelessWidget {
  const _MealThumbnail({required this.imageUrl});

  final String? imageUrl;

  /// Big enough for the food to be recognisable — at the old 46 a plate was a
  /// smear of colour — without outgrowing the three lines of text beside it.
  static const double _size = 52;

  /// Softer than the 12 it replaces. A near-square photo reads as a *print* at
  /// this radius and as a UI chip below it.
  static const double _radius = 16;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final shadow = palette.paneShadow;
    final url = imageUrl;

    return Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_radius),
        // The bed. Shows through until the photo lands, and stands in for good
        // when there is no photo at all — warm rather than the flat grey well
        // it replaces, so an unloaded row still looks deliberate.
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.brandSoft, palette.surfaceHigh],
        ),
        boxShadow: [
          // Only the light theme has a shadow to cast; see
          // [AppPalette.paneShadow].
          if (shadow.a != 0)
            BoxShadow(color: shadow, blurRadius: 8, offset: const Offset(0, 3)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_radius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: Icon(
                Icons.restaurant_rounded,
                size: 20,
                color: palette.brandText.withValues(alpha: 0.55),
              ),
            ),
            if (url != null && url.isNotEmpty) _photo(url),
            // A hairline of light down the top-left, as on the app's glass. A
            // photo cropped to a square otherwise meets the card with nothing
            // marking the seam, which is what made the old thumbnail read as a
            // hole punched in the row.
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(_radius),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: 0.14),
                    Colors.transparent,
                  ],
                  stops: const [0, 0.55],
                ),
                border: Border.all(
                  color: palette.overlay.withValues(alpha: 0.10),
                  width: 0.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _photo(String url) => Image(
        image: appPhoto(url),
        fit: BoxFit.cover,
        // A thumbnail that will not load must not cost the row its macros. The
        // bed underneath is left showing, so the row keeps its shape either
        // way instead of swapping one square for another.
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        frameBuilder: (_, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded) return child;
          return AnimatedOpacity(
            opacity: frame == null ? 0 : 1,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOut,
            child: child,
          );
        },
      );
}

class _LogAnotherMealButton extends StatelessWidget {
  const _LogAnotherMealButton();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return SizedBox(
      width: double.infinity,
      child: TextButton.icon(
        // Straight into the scanner: the photo is how a meal gets logged, and
        // the review screen that follows it is where the numbers are checked.
        onPressed: () => context.push('/meal-upload'),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: palette.stroke),
          ),
        ),
        icon: const Icon(Icons.add_rounded, size: 18),
        label: const Text(
          'Log Another Meal',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _NoMeals extends StatelessWidget {
  const _NoMeals();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Column(
        children: [
          Icon(Icons.no_meals_rounded, size: 30, color: palette.muted),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'No meals logged for this period.',
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.muted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// The card both sections sit in.
class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return LiquidGlass(
      // Painted by the lens rather than by a fill of its own: a pane
      // over the app backdrop, like every other card.
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: palette.stroke),
        ),
        child: child,
      ),
    );
  }
}

class _SummarySkeleton extends StatelessWidget {
  const _SummarySkeleton();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    Widget block(double height) => LiquidGlass(
          // Painted by the lens rather than by a fill of its own: a pane over
          // the app backdrop, like every other card.
          borderRadius: BorderRadius.circular(20),
          child: Container(
            height: height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: palette.stroke),
            ),
          ),
        );

    // Roughly the two cards' real heights, so the page does not jump when the
    // numbers land.
    return Column(
      children: [
        block(190),
        const SizedBox(height: AppSpacing.md),
        block(220),
      ],
    );
  }
}

class _SummaryError extends StatelessWidget {
  const _SummaryError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return _Panel(
      child: Column(
        children: [
          Icon(Icons.cloud_off_rounded, size: 32, color: palette.muted),
          const SizedBox(height: AppSpacing.md),
          Text(
            "Couldn't load your meals",
            style: TextStyle(
              color: palette.text,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Check your connection and try again.',
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.muted, fontSize: 13),
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: palette.text,
              side: BorderSide(color: palette.stroke),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
