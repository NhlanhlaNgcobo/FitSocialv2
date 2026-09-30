import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/input/typed_number.dart';
import '../../challenges/domain/challenge_clock.dart';
import '../../main/domain/progress_models.dart' show formatThousands;
import '../application/goal_providers.dart';
import '../data/goal_repository.dart';
import '../domain/goal.dart';

/// Every running goal, and the way to set a new one.
class GoalsScreen extends ConsumerWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final goals = ref.watch(activeGoalsProvider);
    final count = goals.valueOrNull?.length ?? 0;

    return Scaffold(
      appBar: AppBar(title: const Text('GOALS')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: count >= kMaxActiveGoals
            ? () => _say(
                  context,
                  'You have $kMaxActiveGoals goals running. Archive one to '
                  'set another.',
                )
            : () => showCreateGoalSheet(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New goal'),
      ),
      body: goals.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _Message(
          icon: Icons.cloud_off_rounded,
          title: 'Goals could not load',
          body: 'Check your connection and pull down to try again.',
          onRetry: () => ref.invalidate(activeGoalsProvider),
        ),
        data: (list) {
          if (list.isEmpty) {
            return _Message(
              icon: Icons.track_changes_rounded,
              title: 'No goals yet',
              body: 'Set a target for the week, the month or the year. '
                  'FitSocial keeps count from your logs and your steps.',
              action: FilledButton(
                onPressed: () => showCreateGoalSheet(context),
                child: const Text('Set a goal'),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              96,
            ),
            itemCount: list.length + 1,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) {
              if (index == list.length) {
                return Text(
                  'Progress updates a minute or two after a log or a step '
                  'sync. Steps come from Health Connect.',
                  style: TextStyle(color: palette.muted, fontSize: 12),
                );
              }
              return GoalTile(goal: list[index]);
            },
          );
        },
      ),
    );
  }
}

/// One goal: what it is, how far along this period, and a menu to archive it.
class GoalTile extends ConsumerWidget {
  const GoalTile({required this.goal, super.key});

  final Goal goal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final hit = goal.isHit;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: hit ? palette.success : palette.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  goal.metric.label.toUpperCase(),
                  style: TextStyle(
                    color: palette.muted,
                    fontSize: 11,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (hit)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(
                    Icons.check_circle_rounded,
                    size: 18,
                    color: palette.success,
                  ),
                ),
              PopupMenuButton<String>(
                tooltip: 'Goal options',
                icon: Icon(Icons.more_horiz_rounded, color: palette.muted),
                onSelected: (_) => _confirmArchive(context, ref),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'archive', child: Text('Archive goal')),
                ],
              ),
            ],
          ),
          Text(
            goal.title,
            style: TextStyle(
              color: palette.text,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: goal.fraction,
              minHeight: 8,
              backgroundColor: palette.stroke,
              color: hit ? palette.success : palette.brand,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  goal.progressLabel,
                  style: TextStyle(
                    color: palette.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                hit
                    ? 'Done ${goal.period.currentLabel}'
                    : '${formatThousands(goal.remaining)} to go',
                style: TextStyle(color: palette.muted, fontSize: 12),
              ),
            ],
          ),
          if (goal.period.repeats && goal.completions > 0) ...[
            const SizedBox(height: 4),
            Text(
              'Hit ${goal.completions} '
              '${goal.completions == 1 ? 'time' : 'times'} so far',
              style: TextStyle(color: palette.muted, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmArchive(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Archive this goal?'),
        content: const Text(
          'It stops counting. Badges you earned from it stay.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(goalActionsProvider).archive(goal);
    } catch (_) {
      if (context.mounted) _say(context, 'That did not save. Try again.');
    }
  }
}

Future<void> showCreateGoalSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const CreateGoalSheet(),
  );
}

/// Choosing what to count, over what period, and how much.
class CreateGoalSheet extends ConsumerStatefulWidget {
  const CreateGoalSheet({super.key});

  @override
  ConsumerState<CreateGoalSheet> createState() => _CreateGoalSheetState();
}

class _CreateGoalSheetState extends ConsumerState<CreateGoalSheet> {
  GoalMetric _metric = GoalMetric.workouts;
  GoalPeriod _period = GoalPeriod.weekly;
  final _target = TextEditingController();
  late String _startDayKey;
  late String _endDayKey;
  bool _saving = false;

  /// The target the user has not touched yet follows the metric and period,
  /// so switching from sessions to steps does not leave "3 steps" behind.
  bool _targetEdited = false;

  @override
  void initState() {
    super.initState();
    final today = ChallengeClock.ofDevice().today();
    _startDayKey = today;
    _endDayKey = ChallengeClock.addDays(today, 29);
    _resetTarget();
  }

  @override
  void dispose() {
    _target.dispose();
    super.dispose();
  }

  void _resetTarget() {
    if (_targetEdited) return;
    _target.text = _metric.suggestedTarget(_period).toString();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final insets = MediaQuery.viewInsetsOf(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md + insets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'New goal',
              style: TextStyle(
                color: palette.text,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            const _Label('WHAT TO COUNT'),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final metric in GoalMetric.values)
                  ChoiceChip(
                    label: Text(metric.label),
                    selected: metric == _metric,
                    onSelected: (_) => setState(() {
                      _metric = metric;
                      _resetTarget();
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _metric.explanation,
              style: TextStyle(color: palette.muted, fontSize: 12),
            ),
            const SizedBox(height: AppSpacing.md),
            const _Label('HOW OFTEN'),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final period in GoalPeriod.values)
                  ChoiceChip(
                    label: Text(period.label),
                    selected: period == _period,
                    onSelected: (_) => setState(() {
                      _period = period;
                      _resetTarget();
                    }),
                  ),
              ],
            ),
            if (_period.repeats) ...[
              const SizedBox(height: 6),
              Text(
                _period.repeatNote,
                style: TextStyle(color: palette.muted, fontSize: 12),
              ),
            ] else ...[
              const SizedBox(height: AppSpacing.sm),
              _DateField(
                label: 'Starts',
                dayKey: _startDayKey,
                onPick: (picked) => setState(() {
                  _startDayKey = picked;
                  if (_endDayKey.compareTo(picked) < 0) _endDayKey = picked;
                }),
              ),
              const SizedBox(height: AppSpacing.sm),
              _DateField(
                label: 'Ends',
                dayKey: _endDayKey,
                earliest: _startDayKey,
                onPick: (picked) => setState(() => _endDayKey = picked),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _target,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => _targetEdited = true,
              decoration: InputDecoration(
                labelText: 'Target',
                suffixText: _metric.unit,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: _saving ? null : _create,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Set goal'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _create() async {
    final target = parseTypedDouble(_target.text)?.round();
    if (target == null || target < 1) {
      _say(context, 'Enter a target above zero.');
      return;
    }

    setState(() => _saving = true);
    try {
      final custom = _period == GoalPeriod.custom;
      await ref.read(goalActionsProvider).create(
            metric: _metric,
            period: _period,
            target: target,
            startDayKey: custom ? _startDayKey : null,
            endDayKey: custom ? _endDayKey : null,
          );
      if (mounted) Navigator.pop(context);
    } on GoalRejected catch (rejection) {
      if (!mounted) return;
      setState(() => _saving = false);
      _say(context, rejection.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      _say(context, 'That goal could not be set. Try again.');
    }
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.dayKey,
    required this.onPick,
    this.earliest,
  });

  final String label;
  final String dayKey;
  final String? earliest;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.field),
      onTap: () async {
        final current = parseDayKey(dayKey);
        final picked = await showDatePicker(
          context: context,
          initialDate: current,
          firstDate: earliest != null
              ? parseDayKey(earliest!)
              : current.subtract(const Duration(days: 7)),
          lastDate: current.add(const Duration(days: 365)),
        );
        if (picked != null) onPick(formatDayKey(picked));
      },
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(AppRadius.field),
          border: Border.all(color: palette.stroke),
        ),
        child: Row(
          children: [
            Text(label, style: TextStyle(color: palette.muted)),
            const Spacer(),
            Text(
              dayKey,
              style: TextStyle(
                color: palette.text,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Icon(Icons.calendar_today_rounded, size: 16, color: palette.muted),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: context.palette.muted,
        fontSize: 11,
        letterSpacing: 1.2,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: palette.muted),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.text,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.muted),
            ),
            if (action != null) ...[
              const SizedBox(height: AppSpacing.md),
              action!,
            ],
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.md),
              OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ],
        ),
      ),
    );
  }
}

void _say(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
