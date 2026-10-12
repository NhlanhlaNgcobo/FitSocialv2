import 'package:flutter/foundation.dart';

import 'activity_kind.dart';
import 'app_models.dart';

/// A GPS activity the runner saved without posting, read back from its log so
/// it can still go out later.
///
/// Carries the card exactly as the runner left it on the finish sheet — the
/// photo, whether the map was on, and where they put the line — so reopening
/// it picks up where they stopped rather than from a blank card.
@immutable
class UnsharedRun {
  const UnsharedRun({
    required this.id,
    required this.kind,
    required this.startedAt,
    required this.distanceKm,
    required this.elapsed,
    required this.averagePace,
    this.routePoints = const [],
    this.imageUrl,
    this.showRouteMap = false,
    this.routePlacement = RoutePlacement.centred,
  });

  /// The `runs/` document id.
  final String id;

  /// Run, hike or ride. All three live in `runs/`.
  final ActivityKind kind;

  final DateTime startedAt;
  final double distanceKm;
  final Duration elapsed;

  /// Already formatted: a pace on foot, a speed on a bike.
  final String averagePace;

  /// The GPS trace. Empty for a treadmill run, which has no line to draw.
  final List<RoutePoint> routePoints;

  /// The photo the runner put behind the card, already uploaded. Null for the
  /// gradient.
  final String? imageUrl;

  /// Whether the runner had the map on. Runs saved before this was recorded
  /// read as off.
  final bool showRouteMap;

  /// Where the runner put the line on their photo. Centred on runs saved
  /// before this was recorded.
  final RoutePlacement routePlacement;

  bool get hasRoute => routePoints.length >= 2;
}

/// How the runner left the card when they tapped Post on an unshared run.
@immutable
class UnsharedRunShare {
  const UnsharedRunShare({
    required this.run,
    this.backgroundImagePath,
    this.keepExistingImage = false,
    this.showRouteMap = false,
    this.routePlacement = RoutePlacement.centred,
    this.taggedUsers = const [],
  });

  final UnsharedRun run;

  /// A new photo picked in the editor, or the captured map, as a local file
  /// still to be uploaded. Wins over [keepExistingImage].
  final String? backgroundImagePath;

  /// Post with the photo already saved on the run rather than a new one.
  final bool keepExistingImage;

  final bool showRouteMap;
  final RoutePlacement routePlacement;
  final List<TaggedUser> taggedUsers;
}
