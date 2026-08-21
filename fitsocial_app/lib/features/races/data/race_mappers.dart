import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/race_models.dart';

/// Firestore document shape for the running calendar, in one place.
///
/// Split out from the repository so the ingest script's field names have a
/// single readable definition to be checked against, and so the mapping can be
/// tested without a Firestore instance.
///
/// Everything reads defensively. This collection is populated by a script and
/// by moderators promoting user submissions, so a document with a missing
/// distance list or a bad province code is a question of when, not if. A
/// listing that renders with one field missing beats a calendar that throws.
abstract final class RaceFields {
  static const String collection = 'raceEvents';
  static const String submissions = 'raceSubmissions';

  /// Per-user saved races: `users/{uid}/savedRaces/{eventId}`.
  static const String savedSubcollection = 'savedRaces';

  /// Per-user entry-link taps: `users/{uid}/entryTaps/{eventId}`.
  static const String tapsSubcollection = 'entryTaps';

  static const String eventId = 'eventId';
  static const String lastTapAt = 'lastTapAt';
  static const String taps = 'taps';
  static const String tapRef = 'ref';

  static const String name = 'name';
  static const String startAt = 'startAt';
  static const String endAt = 'endAt';
  static const String province = 'province';
  static const String city = 'city';
  static const String venueName = 'venueName';
  static const String addressLine = 'addressLine';
  static const String latitude = 'lat';
  static const String longitude = 'lng';
  static const String distances = 'distances';

  /// Denormalised [DistanceBucket] keys, so one `array-contains-any` serves the
  /// distance chips. Derived on write from [distances] — never edited by hand.
  static const String distanceBuckets = 'distanceBuckets';

  static const String tags = 'tags';
  static const String organiser = 'organiser';
  static const String description = 'description';
  static const String entryUrl = 'entryUrl';
  static const String entryPlatform = 'entryPlatform';
  static const String imageUrl = 'imageUrl';
  static const String status = 'status';
  static const String source = 'source';
  static const String verifiedAt = 'verifiedAt';

  /// Cheapest published fee in cents, denormalised for sorting by price later.
  static const String priceFromCents = 'priceFromCents';

  static const String kilometres = 'km';
  static const String label = 'label';
  static const String priceCents = 'priceCents';
  static const String startTime = 'startTime';
}

/// A fresh opaque token for one entry tap.
///
/// Random and meaningless outside our own database. It exists so that a partner
/// who can one day report conversions against a parameter we set has something
/// to report against — and being opaque is the point: it will travel on an
/// outbound URL, where a user identifier must never go, because a link that is
/// shared or logged would then disclose who tapped it.
///
/// [Random.secure] rather than [Random] so the token cannot be predicted from
/// another one, which is what stops somebody fabricating referral traffic that
/// looks like ours.
String newEntryTapRef() {
  const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final random = Random.secure();
  return String.fromCharCodes(
    Iterable.generate(
      16,
      (_) => alphabet.codeUnitAt(random.nextInt(alphabet.length)),
    ),
  );
}

/// Reads a calendar document into a [RaceEvent], or null when it is too broken
/// to show.
///
/// The two fields with no sensible fallback are the name and the start: a
/// listing with no date is not a listing. Everything else degrades.
RaceEvent? raceEventFromDoc(String id, Map<String, dynamic>? data) {
  if (data == null) return null;

  final name = data[RaceFields.name];
  if (name is! String || name.trim().isEmpty) return null;

  final startAt = _dateOf(data[RaceFields.startAt]);
  if (startAt == null) return null;

  // An unknown province code falls back to Gauteng rather than dropping the
  // event. Wrong-but-visible is recoverable by a moderator; invisible is not.
  final province =
      Province.byCode(data[RaceFields.province] as String?) ?? Province.gauteng;

  final rawDistances = data[RaceFields.distances];
  final distances = <RaceDistance>[];
  if (rawDistances is List) {
    for (final entry in rawDistances) {
      if (entry is! Map) continue;
      final km = entry[RaceFields.kilometres];
      if (km is! num || km <= 0) continue;
      final rawLabel = entry[RaceFields.label];
      final price = entry[RaceFields.priceCents];
      final time = entry[RaceFields.startTime];
      distances.add(
        RaceDistance(
          kilometres: km.toDouble(),
          label: rawLabel is String && rawLabel.trim().isNotEmpty
              ? rawLabel
              : _defaultDistanceLabel(km.toDouble()),
          priceCents: price is num ? price.toInt() : null,
          startTime: time is String && time.isNotEmpty ? time : null,
        ),
      );
    }
  }
  distances.sort((a, b) => a.kilometres.compareTo(b.kilometres));

  final tags = <RaceTag>{};
  final rawTags = data[RaceFields.tags];
  if (rawTags is List) {
    for (final entry in rawTags) {
      final tag = RaceTag.byKey(entry?.toString());
      if (tag != null) tags.add(tag);
    }
  }

  return RaceEvent(
    id: id,
    name: name.trim(),
    startAt: startAt,
    endAt: _dateOf(data[RaceFields.endAt]),
    venue: RaceVenue(
      name: _stringOrNull(data[RaceFields.venueName]),
      addressLine: _stringOrNull(data[RaceFields.addressLine]),
      city: _stringOrNull(data[RaceFields.city]) ?? province.label,
      province: province,
      latitude: _doubleOrNull(data[RaceFields.latitude]),
      longitude: _doubleOrNull(data[RaceFields.longitude]),
    ),
    distances: distances,
    organiser: _stringOrNull(data[RaceFields.organiser]),
    description: _stringOrNull(data[RaceFields.description]),
    tags: tags,
    entryUrl: _stringOrNull(data[RaceFields.entryUrl]),
    entryPlatform: _stringOrNull(data[RaceFields.entryPlatform]),
    imageUrl: _stringOrNull(data[RaceFields.imageUrl]),
    status: RaceStatus.byKey(data[RaceFields.status] as String?),
    source: RaceSource.byKey(data[RaceFields.source] as String?),
    verifiedAt: _dateOf(data[RaceFields.verifiedAt]),
  );
}

/// Writes a submission for moderation.
///
/// [userId] rides along so a moderator can see who filed it and so a user who
/// files ten bogus races can be found. It is not readable by clients.
Map<String, Object?> raceSubmissionToDoc(
  String userId,
  RaceSubmission submission,
) {
  return {
    'submittedBy': userId,
    'submittedAt': FieldValue.serverTimestamp(),
    'reviewState': 'pending',
    RaceFields.name: submission.name.trim(),
    RaceFields.startAt: Timestamp.fromDate(submission.startAt),
    RaceFields.city: submission.city.trim(),
    RaceFields.province: submission.province.code,
    if (submission.organiser != null)
      RaceFields.organiser: submission.organiser!.trim(),
    if (submission.entryUrl != null)
      RaceFields.entryUrl: submission.entryUrl!.trim(),
    if (submission.distancesNote != null)
      'distancesNote': submission.distancesNote!.trim(),
    if (submission.notes != null) 'notes': submission.notes!.trim(),
  };
}

/// A label for a distance the source did not name.
String _defaultDistanceLabel(double km) {
  final bucket = DistanceBucket.forKilometres(km);
  if (bucket == DistanceBucket.marathon) return 'Marathon';
  if (bucket == DistanceBucket.half) return 'Half Marathon';
  // Trim a trailing .0 so 10.0 reads as "10 km".
  final rounded =
      km == km.roundToDouble() ? km.round().toString() : km.toStringAsFixed(1);
  return '$rounded km';
}

DateTime? _dateOf(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  // ISO strings show up when a document was written by hand in the console.
  if (value is String) return DateTime.tryParse(value);
  return null;
}

String? _stringOrNull(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

double? _doubleOrNull(Object? value) => value is num ? value.toDouble() : null;
