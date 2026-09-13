import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/identity/profile_identity.dart';
import '../../../shared/widgets/avatar.dart';
import '../../../shared/widgets/liquid_glass.dart';
import '../../../shared/widgets/run_route_map.dart';
import '../../main/domain/activity_kind.dart';
import '../data/live_share_repository.dart';
import '../domain/live_activity_share.dart';
import 'run_session_widgets.dart';

/// The share behind a link, kept current. autoDispose so closing the page
/// closes the listener: this is somebody else's location, and nothing should
/// keep watching it once the viewer has looked away.
final liveActivityShareProvider = StreamProvider.autoDispose
    .family<LiveActivityShare?, String>((ref, shareId) {
  return ref.watch(liveShareRepositoryProvider).watch(shareId);
});

/// Somebody else's run, hike or ride, watched through a shared link.
///
/// Opened from `/live/{id}` — a link forwarded by the athlete, or an App Link
/// tapped in a chat. The page is a map with the athlete on it and the three
/// numbers the person at home actually wants: how far, how long, how fast.
///
/// The phone writes every few seconds, not every second, so the clock here
/// runs forward locally from the last write while the share is live. What it
/// cannot do is know about a phone that has gone quiet, which is why the
/// "updated N s ago" line is always on screen and turns into a lost-contact
/// state once the gap gets long.
class LiveActivityViewerScreen extends ConsumerStatefulWidget {
  const LiveActivityViewerScreen({required this.shareId, super.key});

  final String shareId;

  @override
  ConsumerState<LiveActivityViewerScreen> createState() =>
      _LiveActivityViewerScreenState();
}

class _LiveActivityViewerScreenState
    extends ConsumerState<LiveActivityViewerScreen> {
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    // One repaint a second, for the elapsed clock and the "updated ago" line.
    // Both are derived from timestamps at build time, so this only needs to
    // ask for the frame.
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final share = ref.watch(liveActivityShareProvider(widget.shareId));

    return share.when(
      loading: () => const _StatusScaffold(
        title: 'Live activity',
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => _StatusScaffold(
        title: 'Live activity',
        child: _Message(
          icon: Icons.cloud_off_rounded,
          title: "Couldn't open this activity",
          message: 'Check your connection and try again.',
          onRetry: () =>
              ref.invalidate(liveActivityShareProvider(widget.shareId)),
        ),
      ),
      data: (share) {
        if (share == null || share.isExpired) {
          return const _StatusScaffold(
            title: 'Live activity',
            child: _Message(
              icon: Icons.location_off_rounded,
              title: 'This link has expired',
              message: 'Live locations are shared for the length of the '
                  'activity, and the person sharing it has stopped.',
            ),
          );
        }
        return _SharePage(share: share);
      },
    );
  }
}

class _SharePage extends StatelessWidget {
  const _SharePage({required this.share});

  final LiveActivityShare share;

  /// The clock as the viewer should read it now.
  ///
  /// Advanced from the last write while the athlete is moving; frozen at what
  /// was written while they are paused, finished, or out of contact — a clock
  /// that kept counting on a phone that had died would be inventing a run.
  Duration get _elapsed {
    if (!share.isLive || share.isPaused || share.hasLostContact) {
      return share.elapsed;
    }
    final sinceWrite = DateTime.now().difference(share.updatedAt);
    return share.elapsed + (sinceWrite.isNegative ? Duration.zero : sinceWrite);
  }

  static String _formatElapsed(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  static String _ago(DateTime at) {
    final gap = DateTime.now().difference(at);
    if (gap.inSeconds < 5) return 'just now';
    if (gap.inSeconds < 60) return '${gap.inSeconds} s ago';
    if (gap.inMinutes < 60) return '${gap.inMinutes} min ago';
    return '${gap.inHours} h ago';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final descriptor = share.kind.descriptor;
    final usesPace = descriptor.usesPace;

    final isMoving = share.isLive && !share.isPaused && !share.hasLostContact;
    final (String statusLabel, bool statusAccent) = switch (share) {
      _ when !share.isLive => ('FINISHED', false),
      _ when share.hasLostContact => ('LOST CONTACT', false),
      _ when share.isPaused => ('PAUSED', false),
      _ => ('LIVE', true),
    };

    // The trail plus the newest fix, in case the two have come apart — the
    // trail is thinned on the way out and the current position is not.
    final route = <LatLng>[
      for (final p in share.trail) LatLng(p.latitude, p.longitude),
      if (share.position != null &&
          (share.trail.isEmpty ||
              share.trail.last.latitude != share.position!.latitude ||
              share.trail.last.longitude != share.position!.longitude))
        LatLng(share.position!.latitude, share.position!.longitude),
    ];

    final title = "${share.authorName}'s ${descriptor.singular.toLowerCase()}";

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontSize: 18)),
      ),
      body: Stack(
        children: [
          AmbientRunGlow(active: isMoving),
          ListView(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.xl + MediaQuery.of(context).viewPadding.bottom,
            ),
            children: [
              _Athlete(share: share, subtitle: title),
              const SizedBox(height: AppSpacing.md),
              if (route.isNotEmpty)
                _MapFrame(
                  route: route,
                  markerTitle: share.authorName,
                  isLive: share.isLive,
                )
              else
                const _WaitingForFix(),
              const SizedBox(height: AppSpacing.md),
              RunHeroCard(
                statusLabel: statusLabel,
                statusAccent: statusAccent,
                isRunning: isMoving,
                headlineValue: share.distanceKm.toStringAsFixed(2),
                headlineUnit: 'KM',
                metrics: [
                  RunMetric(
                    icon: Icons.timer_outlined,
                    label: 'TIME',
                    value: _formatElapsed(_elapsed),
                  ),
                  RunMetric(
                    icon: Icons.speed_rounded,
                    label: usesPace ? 'AVG /KM' : 'AVG KM/H',
                    value: share.paceLabel,
                  ),
                ],
              ),
              if (share.hasLostContact) ...[
                const SizedBox(height: AppSpacing.md),
                const RunBanner(
                  icon: Icons.signal_cellular_connected_no_internet_0_bar_rounded,
                  message: "Their phone hasn't reported in a while — this is "
                      'the last position it sent. It usually means no signal, '
                      'not that anything is wrong.',
                  tone: RunBannerTone.brand,
                ),
              ],
              if (!share.isLive) ...[
                const SizedBox(height: AppSpacing.md),
                RunBanner(
                  icon: Icons.flag_rounded,
                  message: '${share.authorName} has finished. These are the '
                      'final numbers.',
                  tone: RunBannerTone.brand,
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    share.isLive
                        ? Icons.satellite_alt_rounded
                        : Icons.check_circle_outline_rounded,
                    size: 14,
                    color: palette.muted,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      share.isLive
                          ? 'Updated ${_ago(share.updatedAt)}'
                          : 'Finished ${_ago(share.endedAt ?? share.updatedAt)}',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: palette.muted, fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Who is being watched. Tapping opens their profile, the same as anywhere
/// else a name appears.
class _Athlete extends StatelessWidget {
  const _Athlete({required this.share, required this.subtitle});

  final LiveActivityShare share;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final descriptor = share.kind.descriptor;

    return InkWell(
      onTap: () => context.push('/user/${share.authorId}'),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Avatar(
              initials: avatarInitials(share.authorName),
              imageUrl: share.authorAvatarUrl,
              size: 44,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    share.authorName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Sharing a live ${descriptor.singular.toLowerCase()}',
                    style: TextStyle(color: palette.muted, fontSize: 12.5),
                  ),
                ],
              ),
            ),
            Icon(descriptor.icon, color: palette.accent(descriptor.accent)),
          ],
        ),
      ),
    );
  }
}

class _MapFrame extends StatelessWidget {
  const _MapFrame({
    required this.route,
    required this.markerTitle,
    required this.isLive,
  });

  final List<LatLng> route;
  final String markerTitle;
  final bool isLive;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.stroke),
        boxShadow: [
          BoxShadow(
            color: palette.navShadow,
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: RunRouteMap(
        route: route,
        // Once finished the whole route is the thing to see, framed once,
        // the way the feed shows a completed run.
        mode: isLive ? RunRouteMapMode.spectator : RunRouteMapMode.completed,
        currentMarkerTitle: markerTitle,
        height: 300,
      ),
    );
  }
}

/// The share exists but the phone has not sent a fix yet — the runner tapped
/// share in the first seconds, before the GPS had settled.
class _WaitingForFix extends StatelessWidget {
  const _WaitingForFix();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return LiquidGlass(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 300,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: palette.stroke),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: palette.brandSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.satellite_alt_rounded,
                color: palette.brand,
                size: 26,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Waiting for a GPS fix',
              style: TextStyle(
                color: palette.text,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'The map draws as soon as their phone reports a position',
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.muted, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusScaffold extends StatelessWidget {
  const _StatusScaffold({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: Text(title, style: const TextStyle(fontSize: 18))),
      body: child,
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.message,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: palette.muted),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.text,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.muted, height: 1.5),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.lg),
              TextButton(onPressed: onRetry, child: const Text('Try again')),
            ],
          ],
        ),
      ),
    );
  }
}
