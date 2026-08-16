import 'package:flutter/material.dart';

import '../../app/theme/app_palette.dart';
import 'dark_card.dart';

class StatTile extends StatelessWidget {
  const StatTile({
    required this.label,
    required this.value,
    required this.delta,
    required this.chartBars,
    super.key,
  });

  final String label;
  final String value;
  final String delta;
  final List<double> chartBars;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return DarkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // No explicit colour: the card's Material hands down the theme's
          // body colour, which is the foreground for whichever mode is active.
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 28,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            delta,
            style: TextStyle(
              color: palette.success,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 58,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: chartBars
                  .map(
                    (bar) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: FractionallySizedBox(
                            heightFactor: bar,
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(99),
                                // Fades toward the card rather than toward
                                // transparency. The old fade was the orange at
                                // 40% alpha, which sinks into black on dark but
                                // blooms into a pale glow on white — the columns
                                // stopped reading as bars and started reading as
                                // smudges.
                                gradient: LinearGradient(
                                  colors: [
                                    palette.brand,
                                    Color.lerp(
                                      palette.brand,
                                      palette.surface,
                                      0.55,
                                    )!,
                                  ],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}
