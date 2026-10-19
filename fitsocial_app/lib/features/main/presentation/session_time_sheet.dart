import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_palette.dart';
import '../../../shared/widgets/glass_well.dart';
import '../../../shared/widgets/liquid_glass.dart';
import '../../../shared/widgets/primary_button.dart';
import '../application/active_workout_controller.dart';

/// The live session's time: pause and resume, or correct when it started and
/// how long it has run — "I began 20 minutes before I opened the app".
///
/// Opened by tapping Duration on the session's stats strip.
Future<void> showSessionTimeSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    isScrollControlled: true,
    builder: (_) => const _SessionTimeSheet(),
  );
}

class _SessionTimeSheet extends ConsumerWidget {
  const _SessionTimeSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final workout = ref.watch(activeWorkoutProvider);
    final controller = ref.read(activeWorkoutProvider.notifier);
    if (workout == null) return const SizedBox.shrink();

    Widget row(IconData icon, String label, VoidCallback onTap) => ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon, color: palette.brand),
          title: Text(
            label,
            style: TextStyle(color: palette.text, fontWeight: FontWeight.w700),
          ),
          onTap: onTap,
        );

    return _Frame(
      title: workout.isPaused ? 'Workout paused' : 'Workout time',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          workout.isPaused
              ? row(Icons.play_arrow_rounded, 'Resume', () {
                  controller.resume();
                  Navigator.of(context).pop();
                })
              : row(Icons.pause_rounded, 'Pause', () {
                  controller.pause();
                  Navigator.of(context).pop();
                }),
          row(Icons.schedule_rounded, 'Edit start time', () async {
            final at = await pickStartTime(context, initial: workout.startedAt);
            if (at != null) controller.setStartedAt(at);
          }),
          row(Icons.timelapse_rounded, 'Edit duration', () async {
            final length = await showDurationPrompt(
              context,
              initial: workout.elapsed(DateTime.now()),
            );
            if (length != null) controller.setDuration(length);
          }),
        ],
      ),
    );
  }
}

/// A date then a time, for when a workout began. Never in the future. Null
/// when either picker is dismissed.
Future<DateTime?> pickStartTime(
  BuildContext context, {
  required DateTime initial,
}) async {
  final now = DateTime.now();
  final day = await showDatePicker(
    context: context,
    initialDate: initial.isAfter(now) ? now : initial,
    firstDate: now.subtract(const Duration(days: 30)),
    lastDate: now,
  );
  if (day == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(initial),
  );
  if (time == null) return null;
  final at = DateTime(day.year, day.month, day.day, time.hour, time.minute);
  return at.isAfter(now) ? now : at;
}

/// Hours and minutes, for how long a workout lasted. Null when dismissed.
Future<Duration?> showDurationPrompt(
  BuildContext context, {
  required Duration initial,
}) {
  return showModalBottomSheet<Duration>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    isScrollControlled: true,
    builder: (_) => _DurationPrompt(initial: initial),
  );
}

class _DurationPrompt extends StatefulWidget {
  const _DurationPrompt({required this.initial});

  final Duration initial;

  @override
  State<_DurationPrompt> createState() => _DurationPromptState();
}

class _DurationPromptState extends State<_DurationPrompt> {
  late final _hours = TextEditingController(text: '${widget.initial.inHours}');
  late final _minutes = TextEditingController(
    text: '${widget.initial.inMinutes.remainder(60)}',
  );
  String? _error;

  @override
  void dispose() {
    _hours.dispose();
    _minutes.dispose();
    super.dispose();
  }

  void _submit() {
    final h = int.tryParse(_hours.text.trim().isEmpty ? '0' : _hours.text);
    final m = int.tryParse(_minutes.text.trim().isEmpty ? '0' : _minutes.text);
    if (h == null || m == null || m > 59 || (h == 0 && m == 0) || h > 12) {
      setState(() => _error = 'Enter a length between 1 minute and 12 hours.');
      return;
    }
    Navigator.of(context).pop(Duration(hours: h, minutes: m));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    Widget field(TextEditingController c, String unit) => Expanded(
          child: GlassWell(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: c,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: TextStyle(
                      color: palette.text,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                Text(unit, style: TextStyle(color: palette.muted)),
              ],
            ),
          ),
        );

    return _Frame(
      title: 'How long did it last?',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              field(_hours, 'h'),
              const SizedBox(width: 12),
              field(_minutes, 'min'),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: TextStyle(color: palette.danger, fontSize: 13)),
          ],
          const SizedBox(height: 12),
          PrimaryButton(label: 'Set duration', onPressed: _submit),
        ],
      ),
    );
  }
}

class _Frame extends StatelessWidget {
  const _Frame({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        12,
        0,
        12,
        12 +
            MediaQuery.viewInsetsOf(context).bottom +
            MediaQuery.viewPaddingOf(context).bottom,
      ),
      child: LiquidGlass(
        lens: true,
        borderRadius: BorderRadius.circular(28),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: palette.stroke),
          ),
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
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: palette.text,
                ),
              ),
              const SizedBox(height: 8),
              child,
            ],
          ),
        ),
      ),
    );
  }
}
