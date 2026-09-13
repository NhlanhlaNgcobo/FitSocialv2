import 'package:flutter/foundation.dart';

import '../../main/domain/activity_kind.dart';
import '../../main/domain/app_models.dart' show RoutePoint;

/// Whether a shared activity is still being tracked.
enum LiveSharePhase {
  /// The athlete is out there and the phone is still reporting.
  live,

  /// Finished. The final numbers stay readable until the document expires.
  ended;

  String get wireName => name;

  /// Anything unrecognised reads as ended: a phase this build has not heard of
  /// is not one it should draw a moving marker for.
  static LiveSharePhase fromWire(Object? value) =>
      value == live.wireName ? live : ended;
}

/// One shared, in-progress GPS activity, as it is written to Firestore and
/// read back by whoever holds the link.
///
/// This is *not* the run log. The run log is the athlete's private record of a
/// route, written once at the end and readable only by them. This is a
/// deliberately coarse, deliberately temporary view of the same activity — a
/// current position, a handful of headline numbers, and a thinned trail —
/// that exists so that somebody at home can see where a runner is right now.
/// It is readable by anyone holding its id, which is the whole reason it
/// carries no more than it does, and why it expires.
@immutable
class LiveActivityShare {
  const LiveActivityShare({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.kind,
    required this.phase,
    required this.startedAt,
    required this.updatedAt,
    required this.expiresAt,
    required this.distanceKm,
    required this.elapsed,
    required this.paceLabel,
    required this.isPaused,
    required this.trail,
    this.authorAvatarUrl,
    this.position,
    this.endedAt,
  });

  /// The document id, and the secret: this is the only thing in the link.
  final String id;

  final String authorId;
  final String authorName;
  final String? authorAvatarUrl;
  final ActivityKind kind;
  final LiveSharePhase phase;

  final DateTime startedAt;

  /// When the phone last wrote. What the viewer judges "live" against: a
  /// document that still says [LiveSharePhase.live] but has not been touched
  /// in minutes is a phone that lost signal or died, not a runner standing
  /// still, and it is shown as such.
  final DateTime updatedAt;

  /// When this document should stop being served at all. Written so a
  /// Firestore TTL policy can sweep it, and checked on read as well because
  /// TTL deletion is only guaranteed within a day of the expiry.
  final DateTime expiresAt;

  final DateTime? endedAt;

  /// Where the athlete was at [updatedAt]. Null before the first fix lands.
  final RoutePoint? position;

  final double distanceKm;
  final Duration elapsed;

  /// The headline second figure, already formatted for the [kind] — a pace on
  /// foot, a speed on a bike. Formatted by the phone rather than the viewer so
  /// both screens show the same number.
  final String paceLabel;

  /// Manually paused by the athlete. Distinct from having stopped moving,
  /// which the viewer can work out from a position that is not changing.
  final bool isPaused;

  /// The route so far, thinned to [maxTrailPoints]. Enough to draw the line
  /// on a map, not enough to be the run.
  final List<RoutePoint> trail;

  /// How long a share may live from the moment it starts, whatever happens to
  /// the phone. Long enough for any ride; short enough that a link is not a
  /// standing window onto somebody's whereabouts.
  static const Duration lifetime = Duration(hours: 24);

  /// How stale [updatedAt] may be before a live share is presented as having
  /// lost contact. The phone writes every few seconds when it can, so a gap
  /// this long is a real gap.
  static const Duration staleAfter = Duration(minutes: 3);

  /// Ceiling on the trail written to the document.
  ///
  /// Lower than the 1500 the run log keeps, on purpose: this document is
  /// rewritten every few seconds for the length of the activity, and every
  /// write carries the whole trail. Four hundred points draws a recognisable
  /// route on a phone-sized map at a fraction of the bandwidth.
  static const int maxTrailPoints = 400;

  bool get isLive => phase == LiveSharePhase.live;

  bool get isExpired => !DateTime.now().isBefore(expiresAt);

  /// Live on paper, but the phone has gone quiet.
  bool get hasLostContact =>
      isLive && DateTime.now().difference(updatedAt) > staleAfter;

  /// Evenly thins [route] to at most [maxTrailPoints], always keeping the
  /// first and last fix so the start marker and the athlete stay put.
  ///
  /// The same decimation the run log applies at save time, with a smaller
  /// ceiling. Deliberately a copy rather than a shared helper: the two
  /// ceilings must be free to move independently, and the run log's is
  /// private to its repository for good reason.
  static List<RoutePoint> thinTrail(List<RoutePoint> route) {
    if (route.length <= maxTrailPoints) return List.unmodifiable(route);

    final step = route.length / maxTrailPoints;
    final indices = <int>[
      for (var i = 0; i < maxTrailPoints; i++) (i * step).floor(),
    ];
    final lastIndex = route.length - 1;
    if (indices.last != lastIndex) indices.add(lastIndex);

    return List.unmodifiable(indices.map((i) => route[i]));
  }

  /// Reads a document back. Returns null when the document is not one this
  /// build can present — no author, no start time — rather than throwing on a
  /// link that leads somewhere malformed.
  ///
  /// Timestamps arrive already converted: the data layer turns Firestore's
  /// `Timestamp` into [DateTime] before handing the map over, so this stays
  /// free of the Firestore package and testable without it.
  static LiveActivityShare? fromMap(String id, Map<String, dynamic> data) {
    final authorId = data['authorId'];
    final startedAt = data['startedAt'];
    final updatedAt = data['updatedAt'];
    if (authorId is! String || authorId.isEmpty) return null;
    if (startedAt is! DateTime) return null;

    // A document whose updatedAt is still the unresolved server sentinel
    // (a local write not yet acknowledged) is read as "just now".
    final updated = updatedAt is DateTime ? updatedAt : DateTime.now();
    final expiresAt = data['expiresAt'];

    final lat = data['lat'];
    final lng = data['lng'];
    final position = lat is num && lng is num
        ? RoutePoint.fromMap({'lat': lat, 'lng': lng})
        : null;

    final elapsedSeconds = data['elapsedSeconds'];
    final distance = data['distanceKm'];

    return LiveActivityShare(
      id: id,
      authorId: authorId,
      authorName: data['authorName'] is String
          ? data['authorName'] as String
          : 'FitSocial Member',
      authorAvatarUrl: data['authorAvatarUrl'] as String?,
      kind: ActivityKindX.fromWire(data['activityType']),
      phase: LiveSharePhase.fromWire(data['status']),
      startedAt: startedAt,
      updatedAt: updated,
      expiresAt: expiresAt is DateTime ? expiresAt : startedAt.add(lifetime),
      endedAt: data['endedAt'] is DateTime ? data['endedAt'] as DateTime : null,
      position: position,
      distanceKm: distance is num ? distance.toDouble() : 0,
      elapsed: Duration(seconds: elapsedSeconds is num ? elapsedSeconds.toInt() : 0),
      paceLabel: data['paceLabel'] is String ? data['paceLabel'] as String : '--',
      isPaused: data['isPaused'] == true,
      trail: RoutePoint.listFromFirestore(data['trail']),
    );
  }
}

/// What the phone reports about the activity in progress, each time it writes.
///
/// A plain value rather than the tracker's own state object so the share
/// layer does not depend on the whole of [LiveRunService] — it needs five
/// numbers and a route, and a test can build those by hand.
@immutable
class LiveShareSnapshot {
  const LiveShareSnapshot({
    required this.distanceKm,
    required this.elapsed,
    required this.paceLabel,
    required this.isPaused,
    required this.route,
  });

  final double distanceKm;
  final Duration elapsed;
  final String paceLabel;
  final bool isPaused;

  /// The full route as tracked. Thinned on the way out, not here.
  final List<RoutePoint> route;

  RoutePoint? get position => route.isEmpty ? null : route.last;

  /// The fields written on every update. `updatedAt` is added by the data
  /// layer because it is the server's clock, not the phone's.
  Map<String, dynamic> toUpdate() {
    final current = position;
    return {
      'distanceKm': double.parse(distanceKm.toStringAsFixed(3)),
      'elapsedSeconds': elapsed.inSeconds,
      'paceLabel': paceLabel,
      'isPaused': isPaused,
      if (current != null) 'lat': current.latitude,
      if (current != null) 'lng': current.longitude,
      'trail': LiveActivityShare.thinTrail(route)
          .map((p) => p.toMap())
          .toList(growable: false),
    };
  }

  /// Whether anything worth a write has changed since [previous].
  ///
  /// The clock alone does not count: elapsed time moves every second, and a
  /// write per second for a two-hour ride is the bill this exists to avoid.
  /// The viewer runs its own clock off `updatedAt` in the meantime.
  bool differsFrom(LiveShareSnapshot? previous) {
    if (previous == null) return true;
    return distanceKm != previous.distanceKm ||
        isPaused != previous.isPaused ||
        route.length != previous.route.length ||
        paceLabel != previous.paceLabel;
  }
}
