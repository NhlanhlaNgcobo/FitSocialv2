import 'package:flutter/foundation.dart';

import 'safety_models.dart';

/// How a panic event stands, as its contacts see it.
enum PanicEventStatus {
  active,

  /// The raiser cancelled under coercion. To contacts this is the most urgent
  /// state there is, not a cancellation.
  duress,
  resolved;

  static PanicEventStatus parse(Object? raw) {
    for (final value in values) {
      if (value.name == raw) return value;
    }
    // An unreadable status is shown as live. Wrongly telling a contact that
    // someone is safe is the one mistake this screen must not make.
    return PanicEventStatus.active;
  }
}

/// A contact the alert was addressed to.
@immutable
class AlertedContact {
  const AlertedContact({required this.uid, required this.displayName});

  final String uid;
  final String displayName;
}

/// A panic event, as the recipient screen draws it. See spec A.6.
///
/// One moving pin, not a trail: [current] is replaced every 30 seconds while
/// the event is open, and no history is kept. [position] is where it was
/// raised, for the moment before the first live fix lands.
@immutable
class PanicAlert {
  const PanicAlert({
    required this.eventId,
    required this.userId,
    required this.userName,
    required this.status,
    this.userAvatarUrl,
    this.position,
    this.current,
    this.batteryPercent,
    this.raisedAt,
    this.alerted = const [],
  });

  final String eventId;
  final String userId;
  final String userName;
  final String? userAvatarUrl;
  final PanicEventStatus status;
  final PanicPosition? position;

  /// The latest live position. Its [SharedPosition.updatedAt] is what the
  /// screen shows as "updated 40 seconds ago" — a phone that has died or lost
  /// signal stops updating, and the contact must be able to see that.
  final SharedPosition? current;
  final int? batteryPercent;
  final DateTime? raisedAt;
  final List<AlertedContact> alerted;

  bool get isOpen => status != PanicEventStatus.resolved;

  /// Battery from the latest live fix where there is one.
  int? get latestBattery => current?.batteryPercent ?? batteryPercent;
}

/// How a location share stands.
enum LocationShareStatus {
  active,
  ended,
  expired;

  static LocationShareStatus parse(Object? raw) {
    for (final value in values) {
      if (value.name == raw) return value;
    }
    return LocationShareStatus.ended;
  }
}

/// The owner's position on a share, updated at most every 30 seconds.
@immutable
class SharedPosition {
  const SharedPosition({
    required this.lat,
    required this.lng,
    required this.accuracy,
    this.batteryPercent,
    this.updatedAt,
  });

  final double lat;
  final double lng;
  final double accuracy;
  final int? batteryPercent;
  final DateTime? updatedAt;
}

/// A bounded, foreground-only share of one user's position with some of their
/// accepted safety contacts. See spec A.4.
@immutable
class LocationShare {
  const LocationShare({
    required this.id,
    required this.ownerId,
    required this.viewerIds,
    required this.status,
    required this.expiresAt,
    this.ownerName,
    this.startedAt,
    this.current,
  });

  /// The longest a share may run. Also enforced by the rules and closed by a
  /// scheduled function.
  static const Duration maxDuration = Duration(hours: 4);

  final String id;
  final String ownerId;
  final String? ownerName;
  final List<String> viewerIds;
  final LocationShareStatus status;
  final DateTime? startedAt;
  final DateTime expiresAt;
  final SharedPosition? current;

  bool isLiveAt(DateTime now) =>
      status == LocationShareStatus.active && now.isBefore(expiresAt);
}
