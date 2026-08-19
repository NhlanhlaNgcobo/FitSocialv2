import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../main/application/content_providers.dart'
    show currentUserIdProvider;
import '../../../shared/widgets/quick_toast.dart';
import '../application/race_providers.dart';
import '../domain/race_formatting.dart';
import '../domain/race_models.dart';
import 'race_artwork.dart';
import 'race_toasts.dart';
import 'race_widgets.dart';

/// One race, in full.
///
/// The whole screen is arranged around one question — should I enter this? — so
/// the entry button is pinned to the bottom rather than sitting at the end of a
/// scroll, and the distances table with its fees is the first thing under the
/// header.
class RaceDetailScreen extends ConsumerWidget {
  const RaceDetailScreen({required this.eventId, super.key});

  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final event = ref.watch(raceEventProvider(eventId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('RACE'),
        actions: [
          if (event.valueOrNull != null)
            IconButton(
              onPressed: () => _share(event.value!),
              tooltip: 'Share',
              icon: const Icon(Icons.ios_share_rounded),
            ),
        ],
      ),
      body: switch (event) {
        AsyncValue(:final value?) => _RaceBody(event: value),
        AsyncValue(hasError: true) => const RaceMessage(
            icon: Icons.cloud_off_rounded,
            title: "Couldn't load this race",
            body: 'Check your connection and try again.',
          ),
        // A resolved null is a race that is not there — a stale share link, or
        // an event a moderator removed. Distinguished from a load failure
        // because the two need different words and only one is worth retrying.
        AsyncValue(isLoading: false) => const RaceMessage(
            icon: Icons.event_busy_rounded,
            title: 'Race not found',
            body: 'This listing may have been removed from the calendar.',
          ),
        _ => Center(
            child: CircularProgressIndicator(color: palette.brand),
          ),
      },
      bottomNavigationBar:
          event.valueOrNull == null ? null : _EntryBar(event: event.value!),
    );
  }

  void _share(RaceEvent event) {
    final parts = [
      event.name,
      '${RaceFormat.dateRange(event)} · ${event.venue.shortLabel}',
      RaceFormat.distanceSummary(event, max: 8),
      if (event.entryUrl != null) event.entryUrl!,
    ];
    SharePlus.instance.share(ShareParams(text: parts.join('\n')));
  }
}

class _RaceBody extends ConsumerWidget {
  const _RaceBody({required this.event});

  final RaceEvent event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final now = ref.watch(raceClockProvider);
    final countdown = RaceFormat.countdown(event, now);
    final badges = event.tags
        .map(RaceBadge.forTag)
        .whereType<RaceBadge>()
        .toList(growable: false);
    final description = event.description;
    final organiser = event.organiser;
    final verifiedAt = event.verifiedAt;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.lg,
      ),
      children: [
        // Taller than the list band: here the cover is the header of a page
        // somebody chose to open, not a strip they are scrolling past.
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: RaceCover(event: event),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          event.name,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            height: 1.2,
            color: palette.text,
          ),
        ),
        if (organiser != null) ...[
          const SizedBox(height: 4),
          Text(
            organiser,
            style: TextStyle(fontSize: 13, color: palette.muted),
          ),
        ],
        if (badges.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Wrap(spacing: 6, runSpacing: 6, children: badges),
        ],
        if (event.status.needsNotice) ...[
          const SizedBox(height: AppSpacing.md),
          _DetailNotice(status: event.status),
        ],
        const SizedBox(height: AppSpacing.lg),
        _FactRow(
          icon: Icons.event_rounded,
          label: RaceFormat.dateRange(event),
          detail: countdown == null
              ? 'First start ${RaceFormat.time(event.startAt)}'
              : '$countdown · first start ${RaceFormat.time(event.startAt)}',
        ),
        const SizedBox(height: AppSpacing.md),
        _FactRow(
          icon: Icons.place_rounded,
          label: event.venue.longLabel,
          detail: event.venue.addressLine,
          // Only offered when there is a pin to send the maps app to. A link
          // that opens a map of nowhere in particular is worse than no link.
          onTap: event.venue.hasCoordinates ? () => _openMap(context) : null,
          actionLabel: 'Open in maps',
        ),
        const SizedBox(height: AppSpacing.lg),
        const RaceLabel('DISTANCES'),
        const SizedBox(height: 10),
        _DistanceTable(event: event),
        if (description != null) ...[
          const SizedBox(height: AppSpacing.lg),
          const RaceLabel('ABOUT'),
          const SizedBox(height: 10),
          Text(
            description,
            style: TextStyle(fontSize: 14, height: 1.5, color: palette.text),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        // Provenance, at the bottom, in small type. It matters — a date is only
        // as good as the last time somebody checked it — but it is not what the
        // reader came for, and putting it up top would say otherwise.
        Text(
          verifiedAt == null
              ? _sourceNote(event.source)
              : '${_sourceNote(event.source)} · last checked '
                  '${RaceFormat.date(verifiedAt)}',
          style: TextStyle(fontSize: 11.5, height: 1.4, color: palette.muted),
        ),
        const SizedBox(height: 6),
        Text(
          'Always confirm the date and start time with the organiser before '
          'you travel.',
          style: TextStyle(fontSize: 11.5, height: 1.4, color: palette.muted),
        ),
      ],
    );
  }

  static String _sourceNote(RaceSource source) => switch (source) {
        RaceSource.curated => 'From an official fixture list',
        RaceSource.submission => 'Submitted by a FitSocial user',
        RaceSource.partner => 'From the entry platform',
      };

  Future<void> _openMap(BuildContext context) async {
    final overlay = Overlay.of(context, rootOverlay: true);
    final latitude = event.venue.latitude!;
    final longitude = event.venue.longitude!;
    // A geo: URI would be the native choice on Android but has no meaning on
    // iOS or the web build, and the https form is handled by every maps app on
    // all three.
    final url = Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': '$latitude,$longitude',
    });

    var opened = false;
    try {
      opened = await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {
      // No maps app and no browser. Same handling as a refusal.
    }
    if (!opened) {
      showQuickToastOn(
        overlay,
        "Couldn't open a map on this device.",
        icon: Icons.error_outline_rounded,
        tone: ToastTone.danger,
      );
    }
  }
}

/// The distances, with their fees and start times.
class _DistanceTable extends StatelessWidget {
  const _DistanceTable({required this.event});

  final RaceEvent event;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    if (event.distances.isEmpty) {
      return Text(
        'The organiser has not published the distances yet.',
        style: TextStyle(fontSize: 13, color: palette.muted),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.stroke),
      ),
      child: Column(
        children: [
          for (var index = 0; index < event.distances.length; index++) ...[
            if (index > 0) Divider(height: 1, color: palette.stroke),
            _DistanceRow(
              distance: event.distances[index],
              // A distance with no time of its own goes with the gun, so the
              // event's first start is what it inherits.
              fallbackTime: RaceFormat.time(event.startAt),
            ),
          ],
        ],
      ),
    );
  }
}

class _DistanceRow extends StatelessWidget {
  const _DistanceRow({required this.distance, required this.fallbackTime});

  final RaceDistance distance;
  final String fallbackTime;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final price = distance.priceLabel;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 12,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  distance.label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: palette.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${RaceFormat.kilometres(distance.kilometres)} · '
                  'starts ${distance.startTime ?? fallbackTime}',
                  style: TextStyle(fontSize: 12, color: palette.muted),
                ),
              ],
            ),
          ),
          Text(
            // "—" rather than "R0" or a blank: an unpublished fee is a real
            // state and reading it as free would send somebody to the start
            // line with no money.
            price ?? '—',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: price == null ? palette.muted : palette.text,
            ),
          ),
        ],
      ),
    );
  }
}

/// One line of the facts block.
class _FactRow extends StatelessWidget {
  const _FactRow({
    required this.icon,
    required this.label,
    this.detail,
    this.onTap,
    this.actionLabel,
  });

  final IconData icon;
  final String label;
  final String? detail;
  final VoidCallback? onTap;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final sub = detail;
    final tap = onTap;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: palette.brand),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                  color: palette.text,
                ),
              ),
              if (sub != null) ...[
                const SizedBox(height: 2),
                Text(
                  sub,
                  style: TextStyle(fontSize: 12.5, color: palette.muted),
                ),
              ],
              if (tap != null && actionLabel != null)
                TextButton(
                  onPressed: tap,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    actionLabel!,
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DetailNotice extends StatelessWidget {
  const _DetailNotice({required this.status});

  final RaceStatus status;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isHard =
        status == RaceStatus.cancelled || status == RaceStatus.postponed;
    final colour = isHard ? palette.danger : palette.muted;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colour.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 16, color: colour),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              switch (status) {
                RaceStatus.cancelled =>
                  'This race has been cancelled by the organiser.',
                RaceStatus.postponed =>
                  'This race has been postponed. Check with the organiser for '
                      'a new date.',
                RaceStatus.soldOut => 'Entries are sold out.',
                RaceStatus.entriesClosed =>
                  'Online entries have closed. Entries on the day may still '
                      'be possible.',
                RaceStatus.scheduled => '',
              },
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: colour,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The pinned bar: save, and enter.
class _EntryBar extends ConsumerWidget {
  const _EntryBar({required this.event});

  final RaceEvent event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final signedIn = ref.watch(currentUserIdProvider) != null;
    final isSaved = ref.watch(raceIsSavedProvider(event.id));
    final entryUrl = event.entryUrl;

    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        MediaQuery.paddingOf(context).bottom + AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(top: BorderSide(color: palette.stroke)),
      ),
      child: Row(
        children: [
          if (signedIn)
            IconButton(
              onPressed: () => _toggleSaved(context, ref),
              tooltip: isSaved ? 'Remove from my races' : 'Save race',
              style: IconButton.styleFrom(
                backgroundColor: palette.background,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: palette.stroke),
                ),
                minimumSize: const Size(48, 48),
              ),
              icon: Icon(
                isSaved
                    ? Icons.bookmark_rounded
                    : Icons.bookmark_border_rounded,
                color: isSaved ? palette.brand : palette.muted,
              ),
            ),
          if (signedIn) const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: SizedBox(
              height: 48,
              child: FilledButton(
                // Disabled rather than hidden when there is nowhere to enter.
                // Its absence would read as a loading state; a greyed button
                // with the reason on it reads as the answer.
                onPressed: entryUrl == null || !event.status.isOpen
                    ? null
                    : () => _openEntry(context, ref, entryUrl),
                style: FilledButton.styleFrom(
                  backgroundColor: palette.brand,
                  foregroundColor: AppColors.onBrandInk,
                  disabledBackgroundColor: palette.stroke,
                  disabledForegroundColor: palette.muted,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  _entryLabel(event),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _entryLabel(RaceEvent event) {
    if (!event.status.isOpen) return event.status.label.toUpperCase();
    if (event.entryUrl == null) return 'ENTRIES ON THE DAY';
    return 'ENTER THIS RACE';
  }

  Future<void> _toggleSaved(BuildContext context, WidgetRef ref) async {
    // Grabbed before the await: this screen can be popped while the write is
    // in flight, and the root overlay outlives the route that started it.
    final overlay = Overlay.of(context, rootOverlay: true);
    try {
      final saved = await ref.read(raceActionsProvider).toggleSaved(event.id);
      showRaceSavedToastOn(overlay, saved: saved);
    } catch (_) {
      showRaceSaveFailedToastOn(overlay);
    }
  }

  Future<void> _openEntry(
    BuildContext context,
    WidgetRef ref,
    String entryUrl,
  ) async {
    final overlay = Overlay.of(context, rootOverlay: true);
    final url = Uri.tryParse(entryUrl);
    // A malformed entry URL is a data problem, not a user one, so it fails with
    // the address visible rather than silently doing nothing.
    if (url == null || !url.hasScheme) {
      showQuickToastOn(
        overlay,
        'The entry link looks wrong: $entryUrl',
        icon: Icons.link_off_rounded,
        tone: ToastTone.danger,
      );
      return;
    }

    // Recorded before the launch and not awaited: the tap is the thing being
    // measured, so it counts whether or not a browser turns up, and waiting on a
    // Firestore write before opening one would make the button feel slow.
    ref.read(raceActionsProvider).recordEntryTap(event);

    var opened = false;
    try {
      opened = await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {
      // No browser on the device. Handled as a refusal.
    }
    if (!opened) {
      showQuickToastOn(
        overlay,
        'Could not open a browser. Visit $entryUrl',
        icon: Icons.error_outline_rounded,
        tone: ToastTone.danger,
      );
    }
  }
}
