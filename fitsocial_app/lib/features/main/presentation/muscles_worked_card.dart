import 'package:flutter/material.dart';

import '../../../app/theme/app_palette.dart';
import '../../../shared/widgets/glass_well.dart';
import '../../../shared/widgets/muscle_heatmap.dart';
import '../domain/muscle_heat.dart';

/// "Muscles worked" on a workout's detail page: the body, the top four
/// muscles as bars, and a tap on the body to read any one of them.
class MusclesWorkedCard extends StatefulWidget {
  const MusclesWorkedCard({
    required this.sets,
    this.onThisWeek,
    super.key,
  });

  /// The workout's `muscleSets`.
  final Map<String, double> sets;

  /// Opens the week's heatmap. Null hides the link — on someone else's
  /// workout, "this week" would be the viewer's week, not theirs.
  final VoidCallback? onThisWeek;

  @override
  State<MusclesWorkedCard> createState() => _MusclesWorkedCardState();
}

class _MusclesWorkedCardState extends State<MusclesWorkedCard> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final sets = widget.sets;
    final ranked = [
      for (final m in paintedMuscles)
        if ((sets[m] ?? 0) > 0) m,
    ]..sort((a, b) => sets[b]!.compareTo(sets[a]!));
    final top = ranked.take(4).toList();
    final selected = _selected;
    // A muscle tapped outside the top four still gets its bar.
    final bars =
        selected != null && !top.contains(selected) ? [...top, selected] : top;
    final max = ranked.isEmpty ? 1.0 : sets[ranked.first]!;
    final fullBody = sets['full body'] ?? 0;

    return GlassWell(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Muscles worked',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: palette.text,
                  ),
                ),
              ),
              if (widget.onThisWeek != null)
                TextButton(
                  onPressed: widget.onThisWeek,
                  style: TextButton.styleFrom(
                    foregroundColor: palette.brandText,
                    minimumSize: const Size(48, 44),
                  ),
                  child: const Text('This week'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Center(
            child: MuscleHeatmap(
              sets: sets,
              scale: HeatScale.session,
              height: 198,
              selected: selected,
              onTap: (m) =>
                  setState(() => _selected = m == _selected ? null : m),
            ),
          ),
          const SizedBox(height: 14),
          if (bars.isEmpty)
            Text(
              fullBody > 0
                  ? 'Full body · ${formatSets(fullBody)} sets'
                  : 'Nothing here credits a muscle group.',
              style: TextStyle(color: palette.muted),
            )
          else ...[
            for (final m in bars)
              _MuscleBar(
                muscle: m,
                sets: sets[m] ?? 0,
                fraction: (sets[m] ?? 0) / max,
                highlighted: m == selected,
              ),
            if (fullBody > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Full body · ${formatSets(fullBody)} sets',
                  style: TextStyle(color: palette.muted, fontSize: 13),
                ),
              ),
          ],
          const SizedBox(height: 10),
          Text(
            'Sets this workout · primary 1, secondary 0.5',
            style: TextStyle(color: palette.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _MuscleBar extends StatelessWidget {
  const _MuscleBar({
    required this.muscle,
    required this.sets,
    required this.fraction,
    required this.highlighted,
  });

  final String muscle;
  final double sets;
  final double fraction;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final weight = highlighted ? FontWeight.w800 : FontWeight.w600;
    return Semantics(
      label: '${muscleLabel(muscle)}, ${formatSets(sets)} sets this workout',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 92,
              child: Text(
                muscleLabel(muscle),
                style: TextStyle(color: palette.text, fontWeight: weight),
              ),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Stack(
                  children: [
                    Container(height: 8, color: heatColor(0, palette)),
                    FractionallySizedBox(
                      widthFactor: fraction.clamp(0.04, 1),
                      child: Container(
                        height: 8,
                        color: heatColor(
                          heatLevel(sets, HeatScale.session),
                          palette,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: 40,
              child: Text(
                formatSets(sets),
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: palette.text,
                  fontWeight: weight,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
