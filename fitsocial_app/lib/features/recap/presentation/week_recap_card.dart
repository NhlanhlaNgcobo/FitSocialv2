import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/liquid_glass.dart';
import '../application/recap_providers.dart';
import 'recap_share_sheet.dart';

/// "Share your week" on the Progress tab: opens last week's recap card.
///
/// Draws nothing at all -- not even its spacing -- while Recap Cards are off
/// or last week had nothing in it.
class WeekRecapEntry extends ConsumerWidget {
  const WeekRecapEntry({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(recapCardsEnabledProvider)) return const SizedBox.shrink();
    final recap = ref.watch(lastWeekRecapProvider).valueOrNull;
    if (recap == null) return const SizedBox.shrink();

    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: LiquidGlass(
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => showRecapSheet(context, recap),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: palette.stroke),
            ),
            child: Row(
              children: [
                Icon(Icons.ios_share_rounded, color: palette.brand),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Share last week',
                        style: TextStyle(
                          color: palette.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'A recap card of your week, ready to post',
                        style: TextStyle(color: palette.muted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: palette.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
