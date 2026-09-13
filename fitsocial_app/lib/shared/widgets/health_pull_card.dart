import 'package:flutter/material.dart';

import '../../app/theme/app_palette.dart';
import '../../app/theme/app_spacing.dart';
import 'liquid_glass.dart';

/// "Fill from your health app": one tap that asks for exercise access and
/// reads the latest session into whichever form it sits on.
///
/// Shared by the run log and the training log so the two read as the same
/// control. The card knows nothing about what was pulled — the screen hands it
/// a title and a line, and flips [filled] once a session is in, so a runner
/// can see the form is describing this morning's session and not last
/// week's. A [note] under the card says why the last pull came back empty.
class HealthPullCard extends StatelessWidget {
  const HealthPullCard({
    super.key,
    required this.busy,
    required this.filled,
    required this.title,
    required this.subtitle,
    required this.note,
    required this.onTap,
  });

  /// The idle wording, shared so both screens ask for the same thing.
  static const String idleTitle = 'Fill from your health app';

  final bool busy;
  final bool filled;
  final String title;
  final String subtitle;
  final String? note;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LiquidGlass(
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.card),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: busy ? null : onTap,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(
                    color: filled ? palette.brand : palette.stroke,
                  ),
                ),
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: palette.brandSoft,
                        shape: BoxShape.circle,
                      ),
                      child: busy
                          ? Padding(
                              padding: const EdgeInsets.all(12),
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: palette.brand,
                              ),
                            )
                          : Icon(
                              filled
                                  ? Icons.check_rounded
                                  : Icons.monitor_heart_outlined,
                              color: palette.brand,
                              size: 22,
                            ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              color: palette.text,
                              fontSize: 15.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            subtitle,
                            style: TextStyle(
                              color: palette.muted,
                              fontSize: 12.5,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Icon(
                      filled ? Icons.refresh_rounded : Icons.download_rounded,
                      color: palette.muted,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (note case final text?) ...[
          const SizedBox(height: AppSpacing.sm),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Text(
              text,
              style: TextStyle(
                color: palette.muted,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// "Today 07:12", "Yesterday 19:40", "9/9 06:30".
  static String whenLabel(DateTime at, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final todayDay = DateTime(today.year, today.month, today.day);
    final day = DateTime(at.year, at.month, at.day);
    final time = '${at.hour.toString().padLeft(2, '0')}:'
        '${at.minute.toString().padLeft(2, '0')}';
    if (day == todayDay) return 'Today $time';
    if (day == todayDay.subtract(const Duration(days: 1))) {
      return 'Yesterday $time';
    }
    return '${at.day}/${at.month} $time';
  }

  /// "50:25", "1:05:00".
  static String clockLabel(Duration d) {
    final mins = (d.inMinutes % 60).toString().padLeft(2, '0');
    final secs = (d.inSeconds % 60).toString().padLeft(2, '0');
    return d.inHours == 0 ? '$mins:$secs' : '${d.inHours}:$mins:$secs';
  }

  /// Why a pull found nothing, in the three ways it can. Shared so the two
  /// screens never explain the same failure differently.
  static const String refusedNote =
      'FitSocial needs permission to read your exercise sessions. '
      'Allow it in Health Connect and try again.';
  static const String emptyNote =
      'Nothing from the last two days yet. Health apps sync in batches, so a '
      'session you just finished can take a few minutes to show up. Try '
      'again shortly.';
  static const String failedNote =
      'Could not read your health app just now. Try again in a moment.';
}
