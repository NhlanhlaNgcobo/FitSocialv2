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
import '../../../shared/widgets/liquid_glass.dart';

/// How tall the cover stands before the bar collapses onto it.
const double _heroHeight = 320;

/// One race, in full.
///
/// Arranged around one question — should I enter this? — so the entry button is
/// pinned to the bottom rather than sitting at the end of a scroll, and the two
/// things anybody checks first, when and where, are the two cards under the
/// cover.
class RaceDetailScreen extends ConsumerWidget {
  const RaceDetailScreen({required this.eventId, super.key});

  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final event = ref.watch(raceEventProvider(eventId));
    final loaded = event.valueOrNull;

    // The states with no race keep an ordinary bar. There is no cover for one to
    // float over, and a transparent bar on a plain background is just a bar with
    // its edge missing.
    if (loaded == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('RACE')),
        body: switch (event) {
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
          _ => Center(child: CircularProgressIndicator(color: palette.brand)),
        },
      );
    }

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _RaceHero(event: loaded, onShare: () => _share(loaded)),
          SliverToBoxAdapter(child: _RaceBody(event: loaded)),
        ],
      ),
      bottomNavigationBar: _EntryBar(event: loaded),
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

/// The cover, with the race's name written across the foot of it.
///
/// The name lives here rather than in the app bar's title. Shrinking a title
/// into the toolbar is the usual pattern, but race names here run to
/// "Voortrekker Monument Muller Potgieter Half Marathon" — scaled into one
/// ellipsised line it says almost nothing, and the scaling is what makes that
/// animation look cheap.
class _RaceHero extends StatelessWidget {
  const _RaceHero({required this.event, required this.onShare});

  final RaceEvent event;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final badges = event.tags
        .map(RaceBadge.forTag)
        .whereType<RaceBadge>()
        .toList(growable: false);

    return SliverAppBar(
      pinned: true,
      expandedHeight: _heroHeight,
      backgroundColor: palette.background,
      foregroundColor: AppColors.onMedia,
      // The glyphs sit on the picture while the bar is open, so they carry their
      // own dark disc rather than trusting whatever the cover happens to be.
      leading: const _HeroAction(icon: Icons.arrow_back_rounded, isBack: true),
      actions: [
        _HeroAction(icon: Icons.ios_share_rounded, onTap: onShare),
        const SizedBox(width: AppSpacing.sm),
      ],
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.parallax,
        background: Stack(
          fit: StackFit.expand,
          children: [
            RaceCover(event: event),
            // Two scrims doing separate jobs: the top keeps the back and share
            // glyphs legible, the bottom carries the name. Both fixed black
            // rather than themed — they lie on a photograph, whose brightness
            // owes nothing to the app's theme.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.center,
                  colors: [Color(0x8C000000), Color(0x00000000)],
                ),
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  stops: [0, 0.55, 1],
                  colors: [
                    Color(0xF2000000),
                    Color(0x99000000),
                    Color(0x00000000),
                  ],
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  0,
                  AppSpacing.md,
                  AppSpacing.md,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (badges.isNotEmpty) ...[
                      Wrap(spacing: 6, runSpacing: 6, children: badges),
                      const SizedBox(height: 10),
                    ],
                    Text(
                      event.name,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        height: 1.12,
                        letterSpacing: -0.4,
                        // Fixed, not themed: this lies on a picture. The theme
                        // migration once shipped near-black text on dark tiles
                        // by taking the page colour here.
                        color: AppColors.onMedia,
                        shadows: [
                          Shadow(blurRadius: 12, color: Color(0xB3000000)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(
                          Icons.place_rounded,
                          size: 14,
                          color: AppColors.onMediaMuted,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            event.venue.shortLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.onMediaMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A bar glyph with its own backing, so it stays visible on any cover.
class _HeroAction extends StatelessWidget {
  const _HeroAction({required this.icon, this.onTap, this.isBack = false});

  final IconData icon;
  final VoidCallback? onTap;
  final bool isBack;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: const Color(0x59000000),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap:
              onTap ?? (isBack ? () => Navigator.of(context).maybePop() : null),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, size: 20, color: AppColors.onMedia),
          ),
        ),
      ),
    );
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
    final description = event.description;
    final organiser = event.organiser;
    final verifiedAt = event.verifiedAt;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (organiser != null) ...[
            Row(
              children: [
                Icon(Icons.groups_rounded, size: 15, color: palette.muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    organiser,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: palette.muted,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (event.status.needsNotice) ...[
            _DetailNotice(status: event.status),
            const SizedBox(height: AppSpacing.md),
          ],

          // When and where, as two cards. These are the questions asked before
          // any other, and giving each its own card is what stops them reading
          // as rows in a form.
          _WhenCard(event: event, countdown: countdown),
          const SizedBox(height: AppSpacing.sm),
          _WhereCard(event: event, onOpenMap: () => _openMap(context)),

          const SizedBox(height: AppSpacing.lg),
          const _SectionHeading('DISTANCES'),
          const SizedBox(height: 10),
          _DistanceTable(event: event),

          if (description != null) ...[
            const SizedBox(height: AppSpacing.lg),
            const _SectionHeading('ABOUT'),
            const SizedBox(height: 10),
            Text(
              description,
              style: TextStyle(fontSize: 14, height: 1.55, color: palette.text),
            ),
          ],

          const SizedBox(height: AppSpacing.lg),
          // Provenance, at the foot, in small type. It matters — a date is only
          // as good as the last time somebody checked it — but it is not what
          // the reader came for, and putting it up top would say otherwise.
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
      ),
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

/// A small-caps heading with a hairline running off to the right.
///
/// The rule is what gives the page its rhythm. Without it the sections read as
/// one continuous column with occasional bold words in it.
class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      children: [
        RaceLabel(text),
        const SizedBox(width: 10),
        Expanded(child: Divider(height: 1, color: palette.stroke)),
      ],
    );
  }
}

/// The shell both fact cards sit in.
class _FactCard extends StatelessWidget {
  const _FactCard({required this.icon, required this.child, this.trailing});

  final IconData icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final side = trailing;

    return LiquidGlass(
      // Painted by the lens now rather than by a fill of its own:
      // a pane over the app backdrop, like every other card.
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: palette.stroke),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: palette.brandSoft,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: palette.brandSoftStroke),
              ),
              child: Icon(icon, size: 17, color: palette.brand),
            ),
            const SizedBox(width: 12),
            Expanded(child: child),
            if (side != null) ...[const SizedBox(width: AppSpacing.sm), side],
          ],
        ),
      ),
    );
  }
}

/// Date, start time, and how far off it is.
class _WhenCard extends StatelessWidget {
  const _WhenCard({required this.event, required this.countdown});

  final RaceEvent event;
  final String? countdown;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final until = countdown;

    return _FactCard(
      icon: Icons.event_rounded,
      trailing: until == null
          ? null
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: palette.brandSoft,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: palette.brandSoftStroke),
              ),
              child: Text(
                until.toUpperCase(),
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: palette.brandText,
                ),
              ),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            RaceFormat.dateRange(event),
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
              height: 1.25,
              color: palette.text,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'First start ${RaceFormat.time(event.startAt)}',
            style: TextStyle(fontSize: 12.5, color: palette.muted),
          ),
        ],
      ),
    );
  }
}

/// Venue, address, and the way out to a map.
class _WhereCard extends StatelessWidget {
  const _WhereCard({required this.event, required this.onOpenMap});

  final RaceEvent event;
  final VoidCallback onOpenMap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final address = event.venue.addressLine;

    return _FactCard(
      icon: Icons.place_rounded,
      // Only offered when there is a pin to send the maps app to. A link that
      // opens a map of nowhere in particular is worse than no link.
      trailing: event.venue.hasCoordinates
          ? IconButton(
              onPressed: onOpenMap,
              tooltip: 'Open in maps',
              visualDensity: VisualDensity.compact,
              style: IconButton.styleFrom(
                backgroundColor: palette.surfaceHigh,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: Icon(Icons.map_outlined, size: 18, color: palette.brand),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            event.venue.longLabel,
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
              height: 1.25,
              color: palette.text,
            ),
          ),
          if (address != null) ...[
            const SizedBox(height: 3),
            Text(
              address,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: palette.muted,
              ),
            ),
          ],
        ],
      ),
    );
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

    return LiquidGlass(
      // Painted by the lens now rather than by a fill of its own:
      // a pane over the app backdrop, like every other card.
      borderRadius: BorderRadius.circular(14),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: palette.stroke),
        ),
        child: Column(
          children: [
            for (var index = 0; index < event.distances.length; index++) ...[
              // Indented past the band tile, so the rule separates the rows'
              // content rather than cutting the column of tiles in half.
              if (index > 0)
                Divider(height: 1, indent: 58, color: palette.stroke),
              _DistanceRow(
                distance: event.distances[index],
                // A distance with no time of its own goes with the gun, so the
                // event's first start is what it inherits.
                fallbackTime: RaceFormat.time(event.startAt),
              ),
            ],
          ],
        ),
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
          // The band, not the exact kilometres. The figure is already in the
          // line beneath, so repeating it here would be a larger copy of the
          // same word rather than a second piece of information.
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette.brandSoft,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: palette.brandSoftStroke),
            ),
            child: Text(
              _bandLabel(distance.bucket),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
                height: 1.05,
                color: palette.brandText,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  distance.label,
                  style: TextStyle(
                    fontSize: 14.5,
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
          const SizedBox(width: AppSpacing.sm),
          Text(
            // "—" rather than "R0" or a blank: an unpublished fee is a real
            // state and reading it as free would send somebody to the start
            // line with no money.
            price ?? '—',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              // Tabular, so the prices form a column instead of drifting a pixel
              // or two per row.
              fontFeatures: const [FontFeature.tabularFigures()],
              color: price == null ? palette.muted : palette.text,
            ),
          ),
        ],
      ),
    );
  }

  /// A short name for the distance band, for the leading tile.
  static String _bandLabel(DistanceBucket bucket) => switch (bucket) {
        DistanceBucket.fun => 'FUN',
        DistanceBucket.fiveK => '5K',
        DistanceBucket.tenK => '10K',
        DistanceBucket.fifteenK => '15K',
        DistanceBucket.half => 'HALF',
        DistanceBucket.thirtyK => '30K',
        DistanceBucket.marathon => 'FULL',
        DistanceBucket.ultra => 'ULTRA',
      };
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

    return LiquidGlass(
      // Painted by the lens now rather than by a fill of its own:
      // a pane over the app backdrop, like every other card.
      borderRadius: BorderRadius.circular(0),
      child: Container(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          MediaQuery.paddingOf(context).bottom + AppSpacing.sm,
        ),
        decoration: BoxDecoration(
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
