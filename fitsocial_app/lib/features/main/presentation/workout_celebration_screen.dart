import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_theme.dart';
import '../../../shared/services/workout_card_exporter.dart';
import '../../../shared/widgets/liquid_glass.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/run_summary_card.dart'
    show localBackgroundImage;
import '../../../shared/widgets/save_workout_card_row.dart';
import '../../../shared/widgets/workout_summary_card.dart';
import '../../auth/application/body_metrics_providers.dart';
import '../../auth/domain/body_metrics.dart';
import '../domain/workout_celebration.dart';
import '../domain/workout_math.dart';

/// "Workout saved": which workout it was, the week's streak, the records it
/// set, and the card to share.
///
/// Built entirely from what the save screen handed over, so it works offline
/// on a save that is still queued. Close goes home; the workout is already
/// saved, so there is nothing here to lose.
class WorkoutCelebrationScreen extends ConsumerStatefulWidget {
  const WorkoutCelebrationScreen({required this.celebration, super.key});

  final WorkoutCelebration celebration;

  @override
  ConsumerState<WorkoutCelebrationScreen> createState() =>
      _WorkoutCelebrationScreenState();
}

class _WorkoutCelebrationScreenState
    extends ConsumerState<WorkoutCelebrationScreen> {
  late WorkoutCardLook _look = widget.celebration.backgroundPath != null
      ? WorkoutCardLook.photo
      : WorkoutCardLook.dark;

  static const _days = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', //
    'Friday', 'Saturday', 'Sunday',
  ];

  void _viewWorkout() {
    final id = widget.celebration.postId;
    final router = GoRouter.of(context);
    router.go('/home');
    if (id != null) router.push('/post/$id');
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final c = widget.celebration;
    final imperial = ref.watch(bodyMetricsProvider).valueOrNull?.units ==
        MeasurementUnits.imperial;
    final photo = c.backgroundPath == null
        ? null
        : localBackgroundImage(c.backgroundPath!);
    final looks = [
      if (photo != null) WorkoutCardLook.photo,
      WorkoutCardLook.dark,
      WorkoutCardLook.light,
      WorkoutCardLook.clear,
    ];

    Widget preview() {
      final card = WorkoutSummaryCard(
        workoutData: c.workoutData,
        activity: 'Workout',
        backgroundImage: _look == WorkoutCardLook.photo ? photo : null,
        forExport: _look != WorkoutCardLook.photo,
        transparentGround: _look == WorkoutCardLook.clear,
        margin: EdgeInsets.zero,
      );
      return switch (_look) {
        WorkoutCardLook.dark => Theme(data: AppTheme.darkTheme, child: card),
        WorkoutCardLook.light => Theme(data: AppTheme.lightTheme, child: card),
        _ => card,
      };
    }

    return PopScope(
      // Back is Close: the save screen behind this is spent.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go('/home');
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          actions: [
            IconButton(
              tooltip: 'Close',
              icon: const Icon(Icons.close_rounded),
              onPressed: () => context.go('/home'),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            AppSpacing.xl,
          ),
          children: [
            Text(
              'WORKOUT SAVED',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.brandText,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.6,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Workout #${c.workoutNumber}',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.text,
                fontSize: 30,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${c.title} · ${_days[c.loggedAt.weekday - 1]}',
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.muted, fontSize: 14),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: _Tile(
                    icon: Icons.local_fire_department_rounded,
                    value: '${c.weeklyStreak}',
                    label:
                        c.weeklyStreak == 1 ? 'week streak' : 'weeks in a row',
                    highlighted: true,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _Tile(
                    icon: Icons.emoji_events_rounded,
                    value: '${c.prs.length}',
                    label: c.prs.length == 1 ? 'new record' : 'new records',
                  ),
                ),
              ],
            ),
            if (c.prs.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              _RecordList(prs: c.prs, imperial: imperial),
            ],
            const SizedBox(height: AppSpacing.lg),
            Text(
              'SHARE CARD',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: palette.muted,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 8,
              children: [
                for (final look in looks)
                  ChoiceChip(
                    label: Text(_lookLabel(look)),
                    selected: _look == look,
                    onSelected: (_) => setState(() => _look = look),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            // A sticker on a checked ground, so its transparent edge reads.
            Container(
              decoration: _look == WorkoutCardLook.clear
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: palette.surfaceHigh,
                    )
                  : null,
              child: preview(),
            ),
            const SizedBox(height: AppSpacing.md),
            SaveWorkoutCardRow(
              card: WorkoutCardExport(
                activity: 'Workout',
                workoutData: c.workoutData,
                background: photo,
                look: _look,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(
              icon: Icons.visibility_rounded,
              label: c.postId == null ? 'Done' : 'View workout',
              onPressed: _viewWorkout,
            ),
          ],
        ),
      ),
    );
  }

  static String _lookLabel(WorkoutCardLook look) => switch (look) {
        WorkoutCardLook.photo => 'Photo',
        WorkoutCardLook.dark => 'Dark',
        WorkoutCardLook.light => 'Light',
        WorkoutCardLook.clear => 'Clear',
      };
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.value,
    required this.label,
    this.highlighted = false,
  });

  final IconData icon;
  final String value;
  final String label;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final radius = BorderRadius.circular(AppRadius.card);
    return LiquidGlass(
      borderRadius: radius,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: highlighted ? palette.brandSoft : null,
          borderRadius: radius,
          border: Border.all(
            color: highlighted ? palette.brandSoftStroke : palette.stroke,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: palette.brand, size: 26),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                color: palette.text,
                fontSize: 28,
                fontWeight: FontWeight.w900,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            Text(
              label,
              style: TextStyle(color: palette.muted, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordList extends StatelessWidget {
  const _RecordList({required this.prs, required this.imperial});

  final List<WorkoutPr> prs;
  final bool imperial;

  String _value(WorkoutPr pr) {
    String kg(double v) => imperial
        ? '${(v / 0.45359237).toStringAsFixed(0)} lb'
        : '${v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1)} kg';
    return switch (pr.kind) {
      PrKind.weight || PrKind.oneRepMax || PrKind.sessionVolume => kg(pr.value),
      PrKind.reps ||
      PrKind.repsSet ||
      PrKind.repsSession =>
        '${pr.value.round()} reps',
      PrKind.pace => () {
          final s = pr.value.round();
          return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')} /km';
        }(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final radius = BorderRadius.circular(AppRadius.card);
    return LiquidGlass(
      borderRadius: radius,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: palette.stroke),
        ),
        child: Column(
          children: [
            for (var i = 0; i < prs.length; i++) ...[
              if (i > 0) Divider(height: 1, color: palette.stroke),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: palette.brandSoft,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.emoji_events_rounded,
                          size: 17, color: palette.brand),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            prs[i].exerciseName,
                            style: TextStyle(
                              color: palette.text,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            describeRecord({prs[i].kind}),
                            style: TextStyle(
                              color: palette.muted,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      _value(prs[i]),
                      style: TextStyle(
                        color: palette.text,
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
