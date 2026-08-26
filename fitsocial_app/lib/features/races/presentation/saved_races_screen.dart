import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/liquid_glass.dart';
import '../../main/application/content_providers.dart'
    show currentUserIdProvider;
import '../application/race_providers.dart';
import '../domain/race_formatting.dart';
import '../domain/race_models.dart';
import 'race_artwork.dart';
import 'race_toasts.dart';
import 'race_widgets.dart';

/// The races the user has saved — their own calendar.
///
/// Three registers, largest first, because the three groups are not read the
/// same way. The next race is a *countdown*, so it gets the cover art and the
/// big numeral. The rest of the upcoming ones are a *list*, so they get the
/// ordinary calendar card. Past races are a *log* — nobody scans them for a
/// free Saturday — so they collapse to a compact row.
///
/// Past races stay, under their own heading. A race you ran is part of your
/// year, and a list that quietly dropped it the morning after would lose the
/// only record the app has that you meant to be there.
class SavedRacesScreen extends ConsumerWidget {
  const SavedRacesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final signedIn = ref.watch(currentUserIdProvider) != null;
    final saved = ref.watch(savedRacesProvider);
    final now = ref.watch(raceClockProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('MY RACES'),
        actions: [
          IconButton(
            onPressed: () => context.push('/races'),
            tooltip: 'Race calendar',
            icon: const Icon(Icons.calendar_month_rounded),
          ),
        ],
      ),
      body: !signedIn
          ? const _Centred(
              child: RaceMessage(
                icon: Icons.lock_outline_rounded,
                title: 'Sign in to save races',
                body: 'Saved races are kept to your account so they follow you '
                    'between devices.',
              ),
            )
          : switch (saved) {
              AsyncValue(:final value?) => _SavedList(events: value, now: now),
              AsyncValue(hasError: true) => const _Centred(
                  child: RaceMessage(
                    icon: Icons.cloud_off_rounded,
                    title: "Couldn't load your races",
                    body: 'Check your connection and try again.',
                  ),
                ),
              _ => Center(
                  child: CircularProgressIndicator(color: palette.brand),
                ),
            },
    );
  }
}

/// Puts a whole-page message in the middle of the page rather than under the
/// bar.
///
/// [RaceMessage] is written for the foot of a list on the calendar screen; here
/// it *is* the screen, and a block of text pinned to the top edge of an
/// otherwise empty page reads as a layout that failed to finish loading.
class _Centred extends StatelessWidget {
  const _Centred({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      // Scrollable so the message survives a short screen or a large text
      // scale instead of overflowing.
      child: SingleChildScrollView(child: child),
    );
  }
}

class _SavedList extends ConsumerWidget {
  const _SavedList({required this.events, required this.now});

  final List<RaceEvent> events;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (events.isEmpty) {
      return _Centred(
        child: RaceMessage(
          icon: Icons.bookmark_border_rounded,
          title: 'No saved races yet',
          body: 'Tap the bookmark on any race to keep it here.',
          action: TextButton(
            onPressed: () => context.push('/races'),
            child: const Text('Browse the calendar'),
          ),
        ),
      );
    }

    final upcoming = events.where((event) => !event.isPast(now)).toList();
    final past = events
        .where((event) => event.isPast(now))
        .toList()
        .reversed
        .toList(growable: false);

    // The soonest race is the header, so it is dropped from the list beneath
    // it. Showing it in both places was the screen's loudest duplication: the
    // same race, twice, a centimetre apart.
    final next = upcoming.isEmpty ? null : upcoming.first;
    final rest = upcoming.skip(1).toList(growable: false);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        40,
      ),
      children: [
        if (next != null)
          _NextRaceCard(event: next, now: now)
        else
          const _NothingComingUp(),
        if (rest.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          _SectionHeader(label: 'ALSO COMING UP', count: rest.length),
          const SizedBox(height: 12),
          for (final event in rest)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _SavedRow(event: event, now: now),
            ),
        ],
        if (past.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          _SectionHeader(label: 'BEEN AND GONE', count: past.length),
          const SizedBox(height: 12),
          for (final event in past)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _PastRow(event: event),
            ),
        ],
      ],
    );
  }
}

/// A small caps heading, its count, and a rule running out to the margin.
///
/// The rule is what keeps two adjacent groups of cards from reading as one long
/// list — the label on its own is too light to divide anything at a glance.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Row(
      children: [
        RaceLabel(label),
        const SizedBox(width: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: palette.surfaceHigh,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: palette.muted,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Container(height: 1, color: palette.stroke)),
      ],
    );
  }
}

/// The countdown to the next saved race.
///
/// The one piece of this screen that is not a list. Somebody who has saved a
/// goal race checks this to see how long they have, and burying that in a row
/// among five others would make them count the days themselves.
///
/// Built on the race's own cover rather than on a flat tinted box. Every other
/// surface in the app that stands for a single race — the calendar row, the
/// detail hero — leads with that art, and the one race the runner cares most
/// about was the only one on the screen without it.
class _NextRaceCard extends ConsumerWidget {
  const _NextRaceCard({required this.event, required this.now});

  final RaceEvent event;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final days = event.daysUntil(now);
    final notice = event.status.needsNotice;

    return GestureDetector(
      onTap: () => context.push('/race/${event.id}'),
      child: LiquidGlass(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: palette.stroke),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1.85,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    RaceCover(event: event),
                    // Fixed black rather than themed: it lies on artwork, whose
                    // brightness owes nothing to the app's theme.
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.center,
                          colors: [Color(0xD9000000), Color(0x00000000)],
                        ),
                      ),
                    ),
                    Positioned(
                      left: AppSpacing.md,
                      right: AppSpacing.md,
                      bottom: AppSpacing.md,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _NextTag(),
                          const SizedBox(height: 8),
                          Text(
                            event.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                              height: 1.15,
                              color: AppColors.onMedia,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '${RaceFormat.dateRange(event)} · '
                            '${event.venue.shortLabel}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.onMediaMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      top: AppSpacing.sm,
                      right: AppSpacing.sm,
                      child: _CoverUnsave(event: event),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    _Countdown(days: days),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        notice
                            ? event.status.label
                            : RaceFormat.distanceSummary(event, max: 3),
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight:
                              notice ? FontWeight.w700 : FontWeight.w600,
                          color: notice
                              ? _noticeColour(context, event.status)
                              : palette.muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Cancelled and postponed are the ones that waste somebody's Saturday, so
  /// they get the danger colour. Closed entries are merely disappointing.
  static Color _noticeColour(BuildContext context, RaceStatus status) {
    final palette = context.palette;
    final isHard =
        status == RaceStatus.cancelled || status == RaceStatus.postponed;
    return isHard ? palette.danger : palette.muted;
  }
}

/// The orange flag on the cover. Brand colours rather than palette ones: it
/// sits on artwork, which looks the same in both themes.
class _NextTag extends StatelessWidget {
  const _NextTag();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.orangeBright,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: const Text(
        'NEXT RACE',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
          color: AppColors.onBrandInk,
        ),
      ),
    );
  }
}

/// `12 / DAYS / TO GO`, or the words that replace it once counting stops.
class _Countdown extends StatelessWidget {
  const _Countdown({required this.days});

  final int days;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    if (days <= 0) {
      return Text(
        'Race day',
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w800,
          height: 1,
          color: palette.brand,
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$days',
          style: TextStyle(
            fontSize: 38,
            fontWeight: FontWeight.w800,
            height: 1,
            color: palette.brand,
          ),
        ),
        const SizedBox(width: 9),
        // Stacked rather than run on in a line, so the numeral keeps the height
        // of the row to itself and reads as the figure it is.
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(days == 1 ? 'DAY' : 'DAYS', style: _unitStyle(palette)),
            Text('TO GO', style: _unitStyle(palette)),
          ],
        ),
      ],
    );
  }

  static TextStyle _unitStyle(AppPalette palette) => TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
        height: 1.45,
        color: palette.muted,
      );
}

/// The unsave control on the cover, carrying its own dark disc rather than
/// trusting whatever the artwork happens to be underneath it.
class _CoverUnsave extends ConsumerWidget {
  const _CoverUnsave({required this.event});

  final RaceEvent event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0x8C000000),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        onPressed: () => _unsave(context, ref, event.id),
        tooltip: 'Remove from my races',
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
        icon: const Icon(
          Icons.bookmark_rounded,
          size: 19,
          color: AppColors.onMedia,
        ),
      ),
    );
  }
}

/// The prompt that stands in for the countdown when every saved race is behind
/// them. The alternative was a page that opens on "BEEN AND GONE", which is a
/// bleak thing to hand a runner.
class _NothingComingUp extends StatelessWidget {
  const _NothingComingUp();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return GestureDetector(
      onTap: () => context.push('/races'),
      child: LiquidGlass(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: palette.stroke),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: palette.brandSoft,
                  shape: BoxShape.circle,
                  border: Border.all(color: palette.brandSoftStroke),
                ),
                child: Icon(
                  Icons.event_available_rounded,
                  size: 19,
                  color: palette.brand,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Nothing coming up',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: palette.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Your saved races are all behind you. Find the next one.',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        color: palette.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Icon(Icons.chevron_right_rounded, size: 20, color: palette.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _SavedRow extends ConsumerWidget {
  const _SavedRow({required this.event, required this.now});

  final RaceEvent event;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RaceCard(
      event: event,
      now: now,
      isSaved: true,
      onTap: () => context.push('/race/${event.id}'),
      onToggleSaved: () => _unsave(context, ref, event.id),
    );
  }
}

/// A race that has already been run.
///
/// Compact, and deliberately not the calendar card dimmed down. Dimming meant
/// an [Opacity] over a pane of liquid glass, which paints the pane into a fresh
/// offscreen buffer with no backdrop for the lens to bend — so a past race came
/// out as a hole rather than as a quiet card. Dropping the cover art says the
/// same thing about importance, honestly, and at a third of the height.
class _PastRow extends ConsumerWidget {
  const _PastRow({required this.event});

  final RaceEvent event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;

    return GestureDetector(
      onTap: () => context.push('/race/${event.id}'),
      child: LiquidGlass(
        borderRadius: BorderRadius.circular(AppRadius.nested),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.nested),
            border: Border.all(color: palette.stroke),
          ),
          child: Row(
            children: [
              _PastDateChip(date: event.startAt),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: palette.text,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      event.venue.shortLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: palette.muted),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => _unsave(context, ref, event.id),
                tooltip: 'Remove from my races',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                icon: Icon(
                  Icons.bookmark_rounded,
                  size: 18,
                  color: palette.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The date on a past row: month, day, year, as a torn-off calendar page.
///
/// Quieter than the calendar's own date block, which is brand-tinted. A log of
/// finished races carrying a column of orange would pull the eye to exactly the
/// part of this screen that no longer needs a decision — and the year matters
/// here in a way it never does upcoming, because this list runs back through
/// seasons.
class _PastDateChip extends StatelessWidget {
  const _PastDateChip({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      width: 46,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: palette.overlay.withValues(alpha: palette.isDark ? 0.06 : 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.stroke),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            // `Sat 30 Aug` — the month is the third word.
            RaceFormat.dayAndDate(date).split(' ')[2].toUpperCase(),
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: palette.muted,
            ),
          ),
          Text(
            '${date.day}',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              height: 1.15,
              color: palette.text,
            ),
          ),
          Text(
            '${date.year}',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: palette.muted,
            ),
          ),
        ],
      ),
    );
  }
}

/// Unsaves a race and says so.
///
/// The row leaves this list the moment the unsave lands, so the toast rides the
/// overlay captured before the await rather than a context that is about to be
/// disposed.
Future<void> _unsave(
  BuildContext context,
  WidgetRef ref,
  String eventId,
) async {
  final overlay = Overlay.of(context, rootOverlay: true);
  try {
    await ref.read(raceActionsProvider).unsave(eventId);
    showRaceSavedToastOn(overlay, saved: false);
  } catch (_) {
    showRaceSaveFailedToastOn(overlay);
  }
}
