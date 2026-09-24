import 'package:flutter/foundation.dart';

/// Where a safety-contact handshake stands. See spec A.3.
///
/// Only [accepted] carries any weight: it is the one state in which a contact
/// receives alerts or may watch a location share. The others exist so both
/// people can see where an invite went.
enum SafetyContactStatus {
  pending,
  accepted,
  declined,
  revoked;

  static SafetyContactStatus parse(Object? raw) {
    for (final value in values) {
      if (value.name == raw) return value;
    }
    // An unknown status is treated as the weakest one. A contact the app
    // cannot read the state of must never be counted as someone who will
    // answer an alert.
    return SafetyContactStatus.revoked;
  }
}

/// The most accepted contacts one person may have. Three: enough people that
/// one will answer, few enough that everyone alerted feels responsible rather
/// than assuming somebody else has it. Must match MAX_ACCEPTED_CONTACTS in
/// functions/safety.js and the viewer cap in firestore.rules.
const int maxAcceptedSafetyContacts = 3;

/// One side of a safety-contact relationship.
///
/// The same shape serves both lists: people I asked to watch over me
/// (`users/{me}/safetyContacts`) and people who asked me
/// (`users/{me}/safetyContactOf`). [uid] is always the *other* person.
@immutable
class SafetyContact {
  const SafetyContact({
    required this.uid,
    required this.status,
    required this.displayName,
    required this.handle,
    this.avatarUrl,
    this.invitedAt,
    this.respondedAt,
  });

  final String uid;
  final SafetyContactStatus status;
  final String displayName;
  final String handle;
  final String? avatarUrl;
  final DateTime? invitedAt;
  final DateTime? respondedAt;

  bool get isAccepted => status == SafetyContactStatus.accepted;
}

/// Where an email contact stands.
enum EmailContactStatus {
  /// Emailed a confirmation link; not alerted until they confirm.
  pending,

  /// Confirmed. Alerted by email with a private tracking link.
  confirmed,

  /// Said no. Cannot be asked again.
  declined,

  /// Removed by the owner.
  removed;

  static EmailContactStatus parse(Object? raw) {
    for (final value in values) {
      if (value.name == raw) return value;
    }
    return EmailContactStatus.removed;
  }
}

/// A safety contact without FitSocial, reached by email. Shares the
/// [maxAcceptedSafetyContacts] cap with FitSocial contacts: three people in
/// total, however each is reached.
@immutable
class EmailSafetyContact {
  const EmailSafetyContact({
    required this.id,
    required this.name,
    required this.email,
    required this.status,
    this.addedAt,
    this.confirmedAt,
  });

  final String id;
  final String name;
  final String email;
  final EmailContactStatus status;
  final DateTime? addedAt;
  final DateTime? confirmedAt;

  bool get isConfirmed => status == EmailContactStatus.confirmed;

  /// Whether this row takes one of the three slots.
  bool get takesSlot =>
      status == EmailContactStatus.pending ||
      status == EmailContactStatus.confirmed;
}

/// How many of the three slots are in use, across both kinds of contact.
int usedSafetySlots(
  List<SafetyContact> appContacts,
  List<EmailSafetyContact> emailContacts,
) {
  final app = appContacts
      .where((c) =>
          c.status == SafetyContactStatus.pending ||
          c.status == SafetyContactStatus.accepted)
      .length;
  return app + emailContacts.where((c) => c.takesSlot).length;
}

/// The two panic PIN hashes, kept owner-only under
/// `users/{uid}/private/safety`.
///
/// There are no alarm options: a panic is silent. Documents written before
/// that may still carry siren and flash fields; they are ignored.
@immutable
class SafetySettings {
  const SafetySettings({
    this.pinSalt,
    this.safePinHash,
    this.duressPinHash,
  });

  factory SafetySettings.fromMap(Map<String, dynamic>? map) {
    if (map == null) return defaults;
    return SafetySettings(
      pinSalt: map['pinSalt'] as String?,
      safePinHash: map['safePinHash'] as String?,
      duressPinHash: map['duressPinHash'] as String?,
    );
  }

  static const SafetySettings defaults = SafetySettings();

  final String? pinSalt;
  final String? safePinHash;
  final String? duressPinHash;

  /// Whether both PINs are set. When they are not, an alert ends without
  /// one — a user must never be left unable to end their own alert.
  bool get hasPins =>
      (pinSalt?.isNotEmpty ?? false) &&
      (safePinHash?.isNotEmpty ?? false) &&
      (duressPinHash?.isNotEmpty ?? false);

  SafetySettings copyWith({
    String? pinSalt,
    String? safePinHash,
    String? duressPinHash,
  }) {
    return SafetySettings(
      pinSalt: pinSalt ?? this.pinSalt,
      safePinHash: safePinHash ?? this.safePinHash,
      duressPinHash: duressPinHash ?? this.duressPinHash,
    );
  }

  Map<String, dynamic> toMap() => {
        'pinSalt': pinSalt,
        'safePinHash': safePinHash,
        'duressPinHash': duressPinHash,
      };
}

/// A position attached to a panic event. [isLastKnown] is true when a fresh
/// fix did not arrive inside the dispatch cap and the OS's cached one was used.
@immutable
class PanicPosition {
  const PanicPosition({
    required this.lat,
    required this.lng,
    required this.accuracy,
    this.isLastKnown = false,
  });

  final double lat;
  final double lng;
  final double accuracy;
  final bool isLastKnown;

  Map<String, dynamic> toMap() => {
        'lat': lat,
        'lng': lng,
        'accuracy': accuracy,
        'isLastKnown': isLastKnown,
      };
}

/// What the device knows at the moment a panic is dispatched.
@immutable
class PanicDraft {
  const PanicDraft({
    required this.userId,
    required this.position,
    required this.batteryPercent,
    required this.clientRaisedAt,
  });

  final String userId;

  /// Null when location is denied or no fix exists at all. The alert still
  /// goes; see the "location permission denied" row of spec A.10.
  final PanicPosition? position;
  final int? batteryPercent;
  final DateTime clientRaisedAt;
}

/// The result of committing a panic event.
///
/// [delivered] completes once the server has the document — true — or with
/// false if the write was rejected. While it is pending the event is only in
/// the phone's offline queue, and the UI must not say it was sent.
@immutable
class PanicRaised {
  const PanicRaised({required this.eventId, required this.delivered});

  final String eventId;
  final Future<bool> delivered;
}

/// A contact who pressed "I'm responding".
@immutable
class PanicAcknowledgement {
  const PanicAcknowledgement({
    required this.uid,
    required this.displayName,
    this.acknowledgedAt,
  });

  final String uid;
  final String displayName;
  final DateTime? acknowledgedAt;
}
