import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../application/running_challenge_providers.dart';
import '../domain/challenge_clock.dart';
import '../domain/running_challenge.dart';

/// Creating a running challenge.
///
/// The whole form is here rather than in a wizard: there are six decisions and
/// five of them have a sensible default, so a stepper would make a
/// thirty-second job feel like a form to be endured.
class CreateChallengeScreen extends ConsumerStatefulWidget {
  const CreateChallengeScreen({super.key});

  @override
  ConsumerState<CreateChallengeScreen> createState() =>
      _CreateChallengeScreenState();
}

class _CreateChallengeScreenState extends ConsumerState<CreateChallengeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _goal = TextEditingController(text: '50');
  final _dailyMinimum = TextEditingController(text: '1');

  ChallengeVisibility _visibility = ChallengeVisibility.public;
  late String _startDayKey;
  late String _endDayKey;
  bool _saving = false;

  /// A month, starting today. Long enough for a streak to mean something and
  /// short enough that somebody will actually finish it.
  static const int _defaultLengthDays = 29;

  @override
  void initState() {
    super.initState();
    final actions = ref.read(runningChallengeActionsProvider);
    _startDayKey = actions.todayDayKey();
    _endDayKey = actions.dayKeyFromToday(_defaultLengthDays);
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _goal.dispose();
    _dailyMinimum.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Scaffold(
      appBar: AppBar(title: const Text('NEW CHALLENGE')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            40,
          ),
          children: [
            TextFormField(
              controller: _title,
              maxLength: 80,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'September 100',
              ),
              validator: (value) {
                final text = (value ?? '').trim();
                // Three characters is what the rules demand, so refusing it
                // here means the user is told why rather than watching a write
                // be rejected.
                if (text.length < 3) return 'Give it a name of 3 or more characters.';
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              controller: _description,
              maxLength: 160,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            const _Label('THE GOAL'),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              controller: _goal,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: const InputDecoration(
                labelText: 'Total distance',
                suffixText: 'km',
              ),
              validator: (value) => _number(
                value,
                min: kMinChallengeGoalKm,
                max: 10000,
                what: 'total distance',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              controller: _dailyMinimum,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: const InputDecoration(
                labelText: 'A day counts from',
                suffixText: 'km',
                // The one field nobody expects, so it explains itself. Without
                // a daily bar there is no such thing as a completed day, and
                // the leaderboard ranks on completed days first.
                helperText: 'Run at least this far and the day counts toward '
                    'your streak.',
                helperMaxLines: 2,
              ),
              validator: (value) => _number(
                value,
                min: kMinDailyQualifyingKm,
                max: 200,
                what: 'daily minimum',
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            const _Label('WHEN'),
            const SizedBox(height: AppSpacing.sm),
            _DateRow(
              label: 'Starts',
              dayKey: _startDayKey,
              onPick: (picked) => setState(() {
                _startDayKey = picked;
                // Keep the range valid rather than validating it later: an end
                // date behind a start date is refused by the rules, and a form
                // that lets you enter it is a form that wastes a round trip.
                if (_endDayKey.compareTo(picked) < 0) _endDayKey = picked;
              }),
            ),
            const SizedBox(height: AppSpacing.sm),
            _DateRow(
              label: 'Ends',
              dayKey: _endDayKey,
              earliest: _startDayKey,
              onPick: (picked) => setState(() => _endDayKey = picked),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              _lengthLabel(),
              style: TextStyle(color: palette.muted, fontSize: 12),
            ),
            const SizedBox(height: AppSpacing.lg),

            const _Label('WHO CAN JOIN'),
            const SizedBox(height: AppSpacing.sm),
            SegmentedButton<ChallengeVisibility>(
              segments: const [
                ButtonSegment(
                  value: ChallengeVisibility.public,
                  icon: Icon(Icons.public_rounded, size: 18),
                  label: Text('Public'),
                ),
                ButtonSegment(
                  value: ChallengeVisibility.private,
                  icon: Icon(Icons.lock_rounded, size: 18),
                  label: Text('Private'),
                ),
              ],
              selected: {_visibility},
              onSelectionChanged: (selected) =>
                  setState(() => _visibility = selected.first),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              _visibility.isPrivate
                  ? 'Hidden from discovery. Only people you invite can see it '
                      'or join.'
                  : 'Listed in Live challenges. Anyone can join.',
              style: TextStyle(color: palette.muted, fontSize: 12),
            ),
            const SizedBox(height: AppSpacing.xl),

            FilledButton(
              onPressed: _saving ? null : _create,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Create challenge'),
            ),
          ],
        ),
      ),
    );
  }

  String _lengthLabel() {
    final days = ChallengeClock.daysBetween(_startDayKey, _endDayKey) + 1;
    if (days > kMaxChallengeDays) {
      return '$days days — longer than the $kMaxChallengeDays-day maximum.';
    }
    return '$days ${days == 1 ? "day" : "days"}.';
  }

  String? _number(
    String? value, {
    required double min,
    required double max,
    required String what,
  }) {
    final parsed = double.tryParse((value ?? '').trim());
    if (parsed == null) return 'Enter a number for the $what.';
    if (parsed < min) return 'The $what has to be at least $min km.';
    if (parsed > max) return 'The $what has to be under $max km.';
    return null;
  }

  Future<void> _create() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final days = ChallengeClock.daysBetween(_startDayKey, _endDayKey) + 1;
    if (days > kMaxChallengeDays) {
      _say('A challenge can run for at most $kMaxChallengeDays days.');
      return;
    }

    final goal = double.parse(_goal.text.trim());
    final daily = double.parse(_dailyMinimum.text.trim());
    if (daily > goal) {
      // Not caught by either field's own validator, because it is a
      // relationship between them: a daily bar above the total goal is a
      // challenge that is finished the first time it is met.
      _say('The daily minimum cannot be more than the total goal.');
      return;
    }

    setState(() => _saving = true);
    try {
      final challenge =
          await ref.read(runningChallengeActionsProvider).create(
                title: _title.text,
                description: _description.text,
                goalValueKm: goal,
                dailyMinimumKm: daily,
                startDayKey: _startDayKey,
                endDayKey: _endDayKey,
                visibility: _visibility,
              );

      if (!mounted) return;
      if (challenge == null) {
        setState(() => _saving = false);
        _say('Sign in to create a challenge.');
        return;
      }

      // Replace rather than push: coming back from the board should return to
      // the hub, not to a create form that has already been submitted.
      context.pushReplacement('/challenge/board/${challenge.id}');
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      _say('That challenge could not be created. Try again.');
    }
  }

  void _say(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _DateRow extends StatelessWidget {
  const _DateRow({
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
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        final current = parseDayKey(dayKey);
        final first = earliest != null ? parseDayKey(earliest!) : null;
        final picked = await showDatePicker(
          context: context,
          initialDate: current,
          firstDate: first ?? DateTime.utc(2020),
          lastDate: DateTime.utc(current.year + 3),
        );
        if (picked != null) onPick(formatDayKey(picked));
      },
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(14),
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
