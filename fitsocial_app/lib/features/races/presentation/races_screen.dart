import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../main/application/content_providers.dart'
    show currentUserIdProvider;
import '../application/race_providers.dart';
import '../domain/race_formatting.dart';
import '../domain/race_models.dart';
import 'race_filter_sheet.dart';
import 'race_toasts.dart';
import 'race_widgets.dart';

/// The running calendar — every upcoming race, filtered.
///
/// Grouped by month rather than shown as a flat list. A runner reading this is
/// looking for a date they are free on, and month headers are what turn a
/// scroll into that search. The filter row above is the whole navigation: there
/// are no sub-pages here, only narrower versions of this one list.
class RacesScreen extends ConsumerStatefulWidget {
  const RacesScreen({super.key});

  @override
  ConsumerState<RacesScreen> createState() => _RacesScreenState();
}

class _RacesScreenState extends ConsumerState<RacesScreen> {
  final TextEditingController _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    // The filter outlives the screen, so a search term set before leaving has
    // to be put back into the field on the way in or the list and the box
    // would disagree about what is being searched.
    _search.text = ref.read(raceFilterProvider).query;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    // Invalidating the clock as well as the list is what makes a pull-to-refresh
    // on a Sunday morning actually drop yesterday's races: the window is
    // computed from that instant, and refetching against the old one would
    // return the same page.
    ref.invalidate(raceClockProvider);
    ref.invalidate(raceEventsProvider);
    await ref.read(raceEventsProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final filter = ref.watch(raceFilterProvider);
    final events = ref.watch(raceEventsProvider);
    final savedIds = ref.watch(savedRaceIdsProvider).valueOrNull ?? const {};
    final signedIn = ref.watch(currentUserIdProvider) != null;
    final now = ref.watch(raceClockProvider);
    final savedCount = savedIds.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('RACES'),
        actions: [
          IconButton(
            onPressed: () => context.push('/races/saved'),
            tooltip: 'My races',
            icon: Badge(
              isLabelVisible: savedCount > 0,
              label: Text('$savedCount'),
              child: const Icon(Icons.bookmark_border_rounded),
            ),
          ),
          IconButton(
            onPressed: () => context.push('/races/submit'),
            tooltip: 'Submit a race',
            icon: const Icon(Icons.add_circle_outline_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: palette.brand,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.md,
                  AppSpacing.sm,
                ),
                child: _SearchField(
                  controller: _search,
                  onChanged: (value) =>
                      ref.read(raceFilterProvider.notifier).setQuery(value),
                ),
              ),
            ),
            SliverToBoxAdapter(child: _TimeframeRow(filter: filter)),
            SliverToBoxAdapter(child: _QuickFilterRow(filter: filter)),
            SliverToBoxAdapter(
              child: _ResultSummary(
                filter: filter,
                count: events.valueOrNull?.length,
              ),
            ),
            ..._buildBody(
              events: events,
              now: now,
              savedIds: savedIds,
              signedIn: signedIn,
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildBody({
    required AsyncValue<List<RaceEvent>> events,
    required DateTime now,
    required Set<String> savedIds,
    required bool signedIn,
  }) {
    // The previous page stays on screen while a new filter loads, so switching
    // a chip does not blank the list. Only a first load with nothing to show
    // gets the spinner.
    final rows = events.valueOrNull;
    if (rows == null) {
      if (events.hasError) {
        return const [
          SliverToBoxAdapter(
            child: RaceMessage(
              icon: Icons.cloud_off_rounded,
              title: "Couldn't load the calendar",
              body: 'Check your connection and pull down to try again.',
            ),
          ),
        ];
      }
      return const [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.only(top: 60),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      ];
    }

    if (rows.isEmpty) {
      final filter = ref.read(raceFilterProvider);
      return [
        SliverToBoxAdapter(
          child: RaceMessage(
            icon: Icons.event_busy_rounded,
            title: filter.hasActiveFilters
                ? 'No races match those filters'
                : 'No races listed yet',
            body: filter.hasActiveFilters
                ? 'Try a wider timeframe, or clear the filters to see everything coming up.'
                : 'The calendar is still being built. Know a race that should be here? Add it.',
            action: filter.hasActiveFilters
                ? TextButton(
                    onPressed: () =>
                        ref.read(raceFilterProvider.notifier).clear(),
                    child: const Text('Clear filters'),
                  )
                : TextButton(
                    onPressed: () => context.push('/races/submit'),
                    child: const Text('Submit a race'),
                  ),
          ),
        ),
      ];
    }

    // One flat sliver list with headers interleaved, rather than a nested
    // builder per month. Keeps the whole calendar on one lazy list so a
    // six-month view does not build every month's rows to lay out the scroll.
    final items = _withMonthHeaders(rows);

    return [
      SliverList.builder(
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          if (item is _MonthHeader) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.sm,
              ),
              child: RaceLabel(item.label.toUpperCase()),
            );
          }
          final event = (item as _EventRow).event;
          return Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: RaceCard(
              event: event,
              now: now,
              isSaved: savedIds.contains(event.id),
              onTap: () => context.push('/race/${event.id}'),
              onToggleSaved: signedIn ? () => _toggleSaved(event) : null,
            ),
          );
        },
      ),
    ];
  }

  Future<void> _toggleSaved(RaceEvent event) async {
    try {
      final saved =
          await ref.read(raceActionsProvider).toggleSaved(event.id);
      if (!mounted) return;
      showRaceSavedToast(context, saved: saved);
    } catch (_) {
      if (!mounted) return;
      showRaceSaveFailedToast(context);
    }
  }

  /// Interleaves month headers into a date-ordered list of events.
  static List<Object> _withMonthHeaders(List<RaceEvent> events) {
    final items = <Object>[];
    int? month;
    int? year;
    for (final event in events) {
      if (event.startAt.month != month || event.startAt.year != year) {
        month = event.startAt.month;
        year = event.startAt.year;
        items.add(_MonthHeader(RaceFormat.monthHeader(event.startAt)));
      }
      items.add(_EventRow(event));
    }
    return items;
  }
}

class _MonthHeader {
  const _MonthHeader(this.label);

  final String label;
}

class _EventRow {
  const _EventRow(this.event);

  final RaceEvent event;
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      style: TextStyle(fontSize: 14, color: palette.text),
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Search a race, town or club',
        prefixIcon: Icon(Icons.search_rounded, size: 20, color: palette.muted),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                icon: Icon(Icons.close_rounded, size: 18, color: palette.muted),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              ),
        filled: true,
        fillColor: palette.surface,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide: BorderSide(color: palette.stroke),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide: BorderSide(color: palette.stroke),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide: BorderSide(color: palette.brand),
        ),
      ),
    );
  }
}

/// The timeframe row — single choice, always visible.
class _TimeframeRow extends ConsumerWidget {
  const _TimeframeRow({required this.filter});

  final RaceFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        itemCount: RaceTimeframe.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, index) {
          final timeframe = RaceTimeframe.values[index];
          return RaceChip(
            label: timeframe.label,
            isSelected: timeframe == filter.timeframe,
            onTap: () =>
                ref.read(raceFilterProvider.notifier).setTimeframe(timeframe),
          );
        },
      ),
    );
  }
}

/// The row below the timeframe: the two qualifier chips, trail, and a way into
/// the full filter sheet.
///
/// The qualifier chips are promoted to the top level rather than buried in the
/// sheet because for a large part of the SA season they are the only filter
/// anybody wants. Everything with more than a handful of options — provinces,
/// distances — lives in the sheet, where it has room.
class _QuickFilterRow extends ConsumerWidget {
  const _QuickFilterRow({required this.filter});

  final RaceFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(raceFilterProvider.notifier);
    final narrowed = filter.provinces.length + filter.buckets.length;

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: SizedBox(
        height: 36,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          children: [
            RaceChip(
              label: narrowed == 0 ? 'Filter' : 'Filter · $narrowed',
              icon: Icons.tune_rounded,
              isSelected: narrowed > 0,
              onTap: () => showRaceFilterSheet(context),
            ),
            const SizedBox(width: AppSpacing.sm),
            RaceChip(
              label: 'Comrades qualifier',
              icon: Icons.verified_rounded,
              isSelected: filter.tags.contains(RaceTag.comradesQualifier),
              onTap: () => notifier.toggleTag(RaceTag.comradesQualifier),
            ),
            const SizedBox(width: AppSpacing.sm),
            RaceChip(
              label: 'Two Oceans qualifier',
              icon: Icons.verified_rounded,
              isSelected: filter.tags.contains(RaceTag.twoOceansQualifier),
              onTap: () => notifier.toggleTag(RaceTag.twoOceansQualifier),
            ),
            const SizedBox(width: AppSpacing.sm),
            RaceChip(
              label: 'Trail',
              icon: Icons.terrain_rounded,
              isSelected: filter.tags.contains(RaceTag.trail),
              onTap: () => notifier.toggleTag(RaceTag.trail),
            ),
          ],
        ),
      ),
    );
  }
}

/// The line between the filters and the list: how many races, and where.
class _ResultSummary extends ConsumerWidget {
  const _ResultSummary({required this.filter, required this.count});

  final RaceFilter filter;
  final int? count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final total = count;

    final where = filter.provinces.isEmpty
        ? 'Southern Africa'
        : filter.provinces.map((province) => province.label).join(', ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        0,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              total == null
                  ? 'Loading races…'
                  : '$total ${total == 1 ? 'race' : 'races'} · $where',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: palette.muted,
              ),
            ),
          ),
          if (filter.hasActiveFilters)
            TextButton(
              onPressed: () => ref.read(raceFilterProvider.notifier).clear(),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
              ),
              child: const Text('Clear', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }
}
