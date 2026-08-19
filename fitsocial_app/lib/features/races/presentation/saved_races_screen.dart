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
import 'race_toasts.dart';
import 'race_widgets.dart';

/// The races the user has saved — their own calendar.
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
      appBar: AppBar(title: const Text('MY RACES')),
      body: !signedIn
          ? const RaceMessage(
              icon: Icons.lock_outline_rounded,
              title: 'Sign in to save races',
              body: 'Saved races are kept to your account so they follow you '
                  'between devices.',
            )
          : switch (saved) {
              AsyncValue(:final value?) =>
                _SavedList(events: value, now: now),
              AsyncValue(hasError: true) => const RaceMessage(
                  icon: Icons.cloud_off_rounded,
                  title: "Couldn't load your races",
                  body: 'Check your connection and try again.',
                ),
              _ => Center(
                  child: CircularProgressIndicator(color: palette.brand),
                ),
            },
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
      return RaceMessage(
        icon: Icons.bookmark_border_rounded,
        title: 'No saved races yet',
        body: 'Tap the bookmark on any race to keep it here.',
        action: TextButton(
          onPressed: () => context.push('/races'),
          child: const Text('Browse the calendar'),
        ),
      );
    }

    final upcoming = events.where((event) => !event.isPast(now)).toList();
    final past = events.where((event) => event.isPast(now)).toList().reversed
        .toList(growable: false);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        40,
      ),
      children: [
        if (upcoming.isNotEmpty) ...[
          _NextRaceHeader(event: upcoming.first, now: now),
          const SizedBox(height: AppSpacing.lg),
          const RaceLabel('COMING UP'),
          const SizedBox(height: 10),
          for (final event in upcoming)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _SavedRow(event: event, now: now),
            ),
        ],
        if (past.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          const RaceLabel('BEEN AND GONE'),
          const SizedBox(height: 10),
          for (final event in past)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Opacity(
                opacity: 0.6,
                child: _SavedRow(event: event, now: now),
              ),
            ),
        ],
      ],
    );
  }
}

/// The countdown to the next saved race.
///
/// The one piece of this screen that is not a list. Somebody who has saved a
/// goal race checks this to see how long they have, and burying that in a row
/// among five others would make them count the days themselves.
class _NextRaceHeader extends StatelessWidget {
  const _NextRaceHeader({required this.event, required this.now});

  final RaceEvent event;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final days = event.daysUntil(now);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: palette.brandSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.brandSoftStroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RaceLabel('NEXT RACE', colour: palette.brand),
          const SizedBox(height: 8),
          Text(
            event.name,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              height: 1.2,
              color: palette.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${RaceFormat.dateRange(event)} · ${event.venue.shortLabel}',
            style: TextStyle(fontSize: 12.5, color: palette.muted),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                days <= 0 ? 'Today' : days.toString(),
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  height: 1,
                  color: palette.brand,
                ),
              ),
              if (days > 0) ...[
                const SizedBox(width: 6),
                Text(
                  days == 1 ? 'day to go' : 'days to go',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: palette.muted,
                  ),
                ),
              ],
            ],
          ),
        ],
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
      onToggleSaved: () async {
        // The row leaves this list the moment the unsave lands, so the toast
        // rides the overlay captured before the await rather than a context
        // that is about to be disposed.
        final overlay = Overlay.of(context, rootOverlay: true);
        try {
          await ref.read(raceActionsProvider).toggleSaved(event.id);
          showRaceSavedToastOn(overlay, saved: false);
        } catch (_) {
          showRaceSaveFailedToastOn(overlay);
        }
      },
    );
  }
}
