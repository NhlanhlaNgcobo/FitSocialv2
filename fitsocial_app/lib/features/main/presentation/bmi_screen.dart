import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/dark_card.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../auth/application/body_metrics_providers.dart';
import '../../auth/data/user_profile_repository.dart';
import '../../auth/domain/body_metrics.dart';
import '../../auth/presentation/body_metrics_fields.dart';
import '../../music/presentation/music_island_action.dart';
import '../../onboarding/application/fitness_plan.dart';
import '../../workouts/domain/nutrition_target.dart';
import '../application/content_providers.dart';

class BmiScreen extends ConsumerStatefulWidget {
  const BmiScreen({super.key});

  @override
  ConsumerState<BmiScreen> createState() => _BmiScreenState();
}

class _BmiScreenState extends ConsumerState<BmiScreen> {
  /// What the fields currently hold. Seeded from storage on the first load and
  /// owned by [BodyMetricsFields] from then on.
  BodyMetrics _draft = const BodyMetrics();

  bool _isSaving = false;

  bool get _touched =>
      !_draft.isEmpty || _draft.age != null || _draft.sex != null;
  String? _errorMessage;

  /// The fields report during build when stored values arrive and seed
  /// them, and a rebuild cannot be asked for mid-build — so that report waits
  /// for the frame to finish. Typing reports outside build and applies now.
  void _onFieldsChanged(BodyMetrics metrics) {
    _draft = metrics;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  Future<void> _save() async {
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await ref.read(userProfileRepositoryProvider).saveBodyMetrics(_draft);
      if (!mounted) return;
      // The card on the profile reads the same provider, so it has to be told
      // the stored copy moved.
      // The calorie target is calculated from these too.
      ref
        ..invalidate(bodyMetricsProvider)
        ..invalidate(macroGoalsProvider);
      Navigator.of(context).maybePop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = "Couldn't save your measurements.");
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final stored = ref.watch(bodyMetricsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('BMI'),
        actions: const [MusicIslandAction()],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          // The first-open ask (spec §5.4): sign-up no longer collects these,
          // so this is where most people are first asked. Gone once there is
          // anything stored.
          if (stored.asData?.value.isEmpty ?? false) ...[
            Text(
              'Two numbers and we can show your BMI. Private to you, never '
              'on your profile.',
              style: TextStyle(color: palette.muted, fontSize: 15, height: 1.4),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          BodyMetricsFields(
            // Empty until the stored values land; the fields adopt them then,
            // and only while nothing has been typed.
            initial: stored.asData?.value ?? const BodyMetrics(),
            enabled: !_isSaving,
            // Rebuilds so the calorie target below follows the typing.
            onChanged: _onFieldsChanged,
          ),
          const SizedBox(height: AppSpacing.lg),
          _CalorieTargetCard(
            // Until the user types, the stored figures are what count.
            body: _touched ? _draft : stored.asData?.value ?? _draft,
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              _errorMessage!,
              style:
                  TextStyle(color: palette.danger, fontWeight: FontWeight.w600),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          PrimaryButton(
            label: _isSaving ? 'Saving…' : 'Save',
            onPressed: _isSaving ? null : _save,
          ),
          const SizedBox(height: AppSpacing.lg),
          const BmiFootnote(),
        ],
      ),
    );
  }
}

/// What BMI is not. Worth saying on a fitness app, where a good chunk of the
/// audience carries the muscle that makes the number lie.
class BmiFootnote extends StatelessWidget {
  const BmiFootnote({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    // A pane rather than loose text under the button. The caveat matters more
    // than its position in the scroll suggests, and on a page whose fields are
    // already glass, bare text was the one thing that read as unfinished.
    return DarkCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: palette.muted),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'BMI is a rough screen, not a diagnosis. It cannot tell muscle '
              'from fat, so athletes often read high. Talk to a professional '
              'before acting on it.',
              style: TextStyle(color: palette.muted, fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

/// The calculated daily calorie target, beside the BMI (build spec §9) — or,
/// while an input is missing, the ask for it (spec §5.4).
class _CalorieTargetCard extends ConsumerWidget {
  const _CalorieTargetCard({required this.body});

  final BodyMetrics body;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final plan = ref.watch(fitnessProfileProvider).valueOrNull;
    final ownTargets =
        ref.watch(macroGoalsProvider).valueOrNull?.isCustom ?? false;
    final target = deriveMacroGoals(body, plan);

    return DarkCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.local_fire_department_outlined,
            size: 22,
            color: palette.brandText,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: target == null
                ? Text(
                    'Your calorie target needs your height, weight, age and '
                    'sex. Private to you.',
                    style: TextStyle(
                      color: palette.muted,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'About ${target.calories} kcal a day',
                        style: TextStyle(
                          color: palette.text,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Protein ${target.protein} g · Carbs ${target.carbs} g '
                        '· Fat ${target.fat} g',
                        style: TextStyle(color: palette.text, fontSize: 13),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        ownTargets
                            ? 'You set your own targets on Meal tracking, so '
                                'those are the ones used.'
                            : 'Worked out from your height, weight, age, sex '
                                'and training plan. An estimate, not advice. '
                                'You can set your own on Meal tracking.',
                        style: TextStyle(
                          color: palette.muted,
                          fontSize: 12.5,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
