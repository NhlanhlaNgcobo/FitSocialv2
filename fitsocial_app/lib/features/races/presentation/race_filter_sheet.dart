import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../application/race_providers.dart';
import '../domain/race_models.dart';
import 'race_widgets.dart';

/// Opens the province and distance filters.
Future<void> showRaceFilterSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const _RaceFilterSheet(),
  );
}

/// The filters that need more room than the chip row has.
///
/// Provinces and distances are here rather than inline for a simple reason:
/// fifteen provinces and eight distance bands do not fit on a phone's width, and
/// a horizontally scrolling row of them hides most of the options behind a
/// gesture nobody knows to make.
///
/// Selections apply immediately rather than on a Done button. There is nothing
/// destructive to confirm, the list behind the sheet updates as you tap, and
/// that feedback is the point.
class _RaceFilterSheet extends ConsumerWidget {
  const _RaceFilterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final filter = ref.watch(raceFilterProvider);
    final notifier = ref.read(raceFilterProvider.notifier);

    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: palette.background,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(color: palette.stroke),
          ),
          child: Column(
            children: [
              const _SheetHandle(),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  0,
                  AppSpacing.sm,
                  0,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Filter races',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: palette.text,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: notifier.clear,
                      child: const Text('Reset'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.sm,
                    AppSpacing.md,
                    AppSpacing.xl,
                  ),
                  children: [
                    const RaceLabel('DISTANCE'),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        for (final bucket in DistanceBucket.values)
                          RaceChip(
                            label: bucket.label,
                            isSelected: filter.buckets.contains(bucket),
                            onTap: () => notifier.toggleBucket(bucket),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    const RaceLabel('PROVINCE'),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        for (final province in Province.southAfrican)
                          RaceChip(
                            label: province.label,
                            isSelected: filter.provinces.contains(province),
                            onTap: () => notifier.toggleProvince(province),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    // The neighbours sit under their own heading rather than
                    // mixed in with the provinces. A runner scanning for
                    // Mpumalanga should not have to read past Namibia to find
                    // it, and somebody planning a trip to Vic Falls knows to
                    // look further down.
                    const RaceLabel('BEYOND SOUTH AFRICA'),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        for (final province in Province.values)
                          if (!province.isSouthAfrican)
                            RaceChip(
                              label: province.label,
                              isSelected: filter.provinces.contains(province),
                              onTap: () => notifier.toggleProvince(province),
                            ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    const RaceLabel('RACE TYPE'),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        for (final tag in _filterableTags)
                          RaceChip(
                            label: tag.label,
                            isSelected: filter.tags.contains(tag),
                            onTap: () => notifier.toggleTag(tag),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// The tags worth offering as filters.
  ///
  /// Not every tag earns a chip. "Road" would match nearly the whole calendar,
  /// and "stage race" matches about four events a year — neither is a filter
  /// somebody reaches for. The two qualifier tags are absent here because they
  /// already have chips on the screen behind this sheet.
  static const List<RaceTag> _filterableTags = [
    RaceTag.trail,
    RaceTag.crossCountry,
    RaceTag.nightRace,
    RaceTag.womensRace,
    RaceTag.charity,
    RaceTag.virtual,
  ];
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Container(
        width: 38,
        height: 4,
        decoration: BoxDecoration(
          color: context.palette.stroke,
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}
