import 'package:flutter/material.dart';

import '../../../app/theme/app_palette.dart';
import '../domain/challenge_models.dart';

/// The last fortnight, as squares.
///
/// A completed day is filled, a missed day is an outline, and today — still
/// open — is drawn with a dashed-looking soft border. The value of this strip
/// is that it shows a pattern: three misses in a row look like three misses in
/// a row, which is a more useful warning than any counter.
class DayHistoryStrip extends StatelessWidget {
  const DayHistoryStrip({
    required this.days,
    this.todayKey,
    super.key,
  });

  /// Oldest first, so the strip reads left to right as time passing.
  final List<DailyProgress> days;

  /// The day still open, drawn differently from a day that was missed. Without
  /// this, a day the user is halfway through looks like a day they lost.
  final String? todayKey;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    if (days.isEmpty) {
      return Text(
        'No finalised days yet.',
        style: TextStyle(color: palette.muted, fontSize: 13),
      );
    }

    return SizedBox(
      height: 26,
      child: Row(
        children: [
          for (final day in days) ...[
            Expanded(child: _DaySquare(day: day, isToday: day.dayKey == todayKey)),
            if (day != days.last) const SizedBox(width: 4),
          ],
        ],
      ),
    );
  }
}

class _DaySquare extends StatelessWidget {
  const _DaySquare({required this.day, required this.isToday});

  final DailyProgress day;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final complete = day.isComplete;

    return Tooltip(
      message: '${day.dayKey} — ${day.tasksLabel}',
      child: Container(
        decoration: BoxDecoration(
          color: complete ? palette.brand : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: complete
                ? palette.brand
                : isToday
                    ? palette.brandSoftStroke
                    : palette.stroke,
            width: isToday ? 2 : 1,
          ),
        ),
      ),
    );
  }
}
