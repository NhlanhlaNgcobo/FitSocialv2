import 'package:flutter/material.dart';

import '../../../shared/widgets/fit_social_logo.dart';
import '../domain/recap.dart';

/// The width a recap card is laid out at. It is rasterised at 3x, so the file
/// comes out 1080 x 1920 -- the shape of a phone screen and of a Story.
const double kRecapCardWidth = 360;
const double kRecapCardHeight = 640;

/// A recap card as it is shared: FitSocial's own colours, one headline, the
/// figures the sharer let through, and the wordmark.
///
/// Always drawn on its own dark ground, whatever the app's theme: the image
/// is going to somebody else's feed, where the app's theme means nothing, and
/// one look is easier to recognise than two.
class RecapCard extends StatelessWidget {
  const RecapCard({required this.data, required this.options, super.key});

  final RecapCardData data;
  final RecapOptions options;

  static const _ink = Color(0xFFF7F7FA);
  static const _soft = Color(0xB3F7F7FA);
  static const _accent = Color(0xFFFF6A3D);

  IconData get _icon => switch (data.kind) {
        RecapKind.week => Icons.calendar_month_rounded,
        RecapKind.challenge => Icons.emoji_events_rounded,
        RecapKind.achievement => Icons.military_tech_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final stats = data.statsFor(options);
    final name = data.nameFor(options);
    final hero = options.showNumbers ? data.hero : null;

    return SizedBox(
      width: kRecapCardWidth,
      height: kRecapCardHeight,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1B1530), Color(0xFF0E0D16), Color(0xFF2A1410)],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 36, 28, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_icon, color: _accent, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      data.eyebrow,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _accent,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.6,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                data.headline,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  height: 1.05,
                ),
              ),
              if (hero != null) ...[
                const SizedBox(height: 18),
                Text(
                  hero,
                  style: const TextStyle(
                    color: _accent,
                    fontSize: 72,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
              ],
              if (data.subline != null) ...[
                const SizedBox(height: 10),
                Text(
                  data.subline!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(color: _soft, fontSize: 16, height: 1.3),
                ),
              ],
              const SizedBox(height: 24),
              Expanded(
                child: stats.isEmpty
                    ? const SizedBox.shrink()
                    : _StatGrid(stats: stats),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: name == null
                        ? const SizedBox.shrink()
                        : Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _ink,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                  Image.asset(kFitSocialMarkAsset, width: 30, height: 30),
                  const SizedBox(width: 8),
                  const Text(
                    'FitSocial',
                    style: TextStyle(
                      color: _ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.stats});

  final List<RecapStat> stats;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final stat in stats.take(6))
          Container(
            width: (kRecapCardWidth - 56 - 12) / 2,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0x14FFFFFF),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0x22FFFFFF)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stat.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: RecapCard._ink,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  stat.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(color: RecapCard._soft, fontSize: 12.5),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
