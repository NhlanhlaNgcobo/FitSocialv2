import '../../main/domain/activity_kind.dart';
import '../../main/domain/app_models.dart';

/// Where a draft came from.
///
/// The list has to say something different about each: an offline recording is
/// waiting on a connection, an imported one is waiting on the runner deciding
/// they want it at all.
enum RunDraftSource {
  /// This app's own GPS or treadmill engine recorded it, and it was held back
  /// because there was no connection when the finish sheet closed.
  recorded('recorded'),

  /// Read out of Health Connect — a run a watch or another app recorded, that
  /// FitSocial never saw happen.
  healthConnect('health_connect');

  const RunDraftSource(this.wireName);

  /// What goes in the file. Named rather than derived from [name] so renaming
  /// a constant cannot silently orphan every draft already on disk.
  final String wireName;

  /// Unknown values read as [recorded] rather than being dropped: that is what
  /// every draft written before this field existed is, and a draft the runner
  /// can still post beats one that vanished over a label.
  static RunDraftSource fromWire(Object? value) {
    for (final source in values) {
      if (source.wireName == value) return source;
    }
    return RunDraftSource.recorded;
  }
}

/// A finished run held on this phone because it was recorded out of signal.
///
/// A superset of [RunLogDraft]: everything needed to replay the save later,
/// plus what a drafts list has to show and what publishing has to be careful
/// about. The run itself is already over and its numbers are final — nothing
/// in here is editable, it is a recording waiting for a connection.
class RunDraft {
  const RunDraft({
    required this.id,
    required this.savedAt,
    required this.distanceKm,
    required this.elapsed,
    required this.averagePace,
    required this.shareToFeed,
    this.routePoints = const [],
    this.startedAt,
    this.photoPath,
    this.photoUnavailable = false,
    this.heartRate,
    this.publishAttemptedAt,
    this.source = RunDraftSource.recorded,
    this.externalId,
    this.activityKind = ActivityKind.run,
    this.elevationGainMeters,
  });

  /// Bumped whenever the stored shape changes in a way older files can't be
  /// read as. [fromJson] rejects anything it doesn't recognise rather than
  /// guessing, so a draft from a future version is skipped, not misread.
  ///
  /// [source], [externalId] and [activityKind] were added without moving this,
  /// on purpose.
  /// Both are optional with defaults that mean exactly what a file written
  /// before them meant, so an old draft reads correctly here and a new one
  /// reads correctly on an older build. Bumping would have made every offline
  /// draft already sitting on a phone unreadable — losing runs to announce a
  /// field nothing needs.
  static const int schemaVersion = 1;

  final String id;

  /// When the run was put in drafts — what the list sorts and labels by.
  final DateTime savedAt;

  final double distanceKm;
  final Duration elapsed;
  final String averagePace;

  /// What the runner chose on the finish sheet, honoured at publish time
  /// rather than now. A private draft still becomes a `runs/` document; it
  /// just never becomes a post.
  final bool shareToFeed;

  /// GPS trace of the run. Empty for treadmill runs, which have no recorded
  /// route — same contract as [RunLogDraft.routePoints].
  final List<RoutePoint> routePoints;

  final DateTime? startedAt;

  /// Absolute path of *our* copy of the backdrop, inside the drafts
  /// directory — never the picker's path, which the OS is free to evict.
  final String? photoPath;

  /// The runner chose a photo and it could not be copied (already evicted,
  /// disk full). Kept as a fact rather than silently dropped so the row can
  /// say so instead of looking like a run nobody picked a photo for.
  final bool photoUnavailable;

  final HeartRateSummary? heartRate;

  /// Stamped just before the publish call goes out, cleared only by the draft
  /// file being deleted on success.
  ///
  /// A draft that still carries this on a later launch means the process died
  /// between the save landing and the file being removed — so the run may
  /// already be on the feed. The list surfaces that rather than letting a
  /// second tap create a duplicate; see `RunDraftController.publish`.
  final DateTime? publishAttemptedAt;

  /// Where this run came from. Defaults to [RunDraftSource.recorded], which is
  /// what every draft written before importing existed is.
  final RunDraftSource source;

  /// The id the source system knows this run by — a Health Connect record
  /// uuid. Null for anything this app recorded itself.
  ///
  /// Kept on the draft as well as in the import ledger so a draft that
  /// survives the ledger being lost can still be recognised as already-seen.
  final String? externalId;

  /// True once a publish has been attempted and the draft outlived it.
  bool get mayHavePublished => publishAttemptedAt != null;

  /// True for a run FitSocial did not record — no route, and a different story
  /// to tell about why it is sitting in a list.
  bool get isImported => source != RunDraftSource.recorded;

  /// Which GPS activity this recording was. Defaults to a run, which is what
  /// every draft written before hikes and rides existed holds.
  final ActivityKind activityKind;

  /// Total climb, in metres, or null when nothing measured it.
  final int? elevationGainMeters;

  /// The draft as the save path wants it.
  ///
  /// [backgroundImagePath] is passed explicitly rather than read from
  /// [photoPath] because the caller is the one that checked the file still
  /// exists — this type cannot touch the disk.
  RunLogDraft toRunLogDraft({String? backgroundImagePath}) {
    return RunLogDraft(
      distanceKm: distanceKm,
      elapsed: elapsed,
      averagePace: averagePace,
      shareToFeed: shareToFeed,
      activityKind: activityKind,
      elevationGainMeters: elevationGainMeters,
      routePoints: routePoints,
      startedAt: startedAt,
      backgroundImagePath: backgroundImagePath,
      heartRate: heartRate,
    );
  }

  RunDraft copyWith({
    String? photoPath,
    bool clearPhotoPath = false,
    bool? photoUnavailable,
    DateTime? publishAttemptedAt,
    bool? shareToFeed,
  }) {
    return RunDraft(
      id: id,
      savedAt: savedAt,
      distanceKm: distanceKm,
      elapsed: elapsed,
      averagePace: averagePace,
      // The one field here a runner can still change. An imported run arrives
      // private because nobody chose to publish it; saying "post it to the
      // feed" from the list is that choice being made.
      shareToFeed: shareToFeed ?? this.shareToFeed,
      routePoints: routePoints,
      startedAt: startedAt,
      photoPath: clearPhotoPath ? null : photoPath ?? this.photoPath,
      photoUnavailable: photoUnavailable ?? this.photoUnavailable,
      heartRate: heartRate,
      publishAttemptedAt: publishAttemptedAt ?? this.publishAttemptedAt,
      source: source,
      externalId: externalId,
      activityKind: activityKind,
      elevationGainMeters: elevationGainMeters,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'v': schemaVersion,
      'id': id,
      'savedAt': savedAt.toIso8601String(),
      'distanceKm': distanceKm,
      'durationSeconds': elapsed.inSeconds,
      'averagePace': averagePace,
      'shareToFeed': shareToFeed,
      // The same `{lat, lng}` shape the route takes into Firestore, so the app
      // has one coordinate wire format rather than two that can drift.
      'routePoints':
          routePoints.map((point) => point.toMap()).toList(growable: false),
      if (startedAt != null) 'startedAt': startedAt!.toIso8601String(),
      if (photoPath != null) 'photoPath': photoPath,
      if (photoUnavailable) 'photoUnavailable': true,
      if (heartRate case final hr? when hr.hasData) 'heartRate': hr.toMap(),
      if (publishAttemptedAt != null)
        'publishAttemptedAt': publishAttemptedAt!.toIso8601String(),
      // Both omitted for a recorded run, so an ordinary offline draft's file
      // is byte-for-byte what it was before importing existed.
      if (source != RunDraftSource.recorded) 'source': source.wireName,
      if (externalId != null) 'externalId': externalId,
      // Omitted for a run, on the same terms and for the same reason: an
      // ordinary run's draft file does not change shape, and an older build
      // reading a hike draft publishes it as a run rather than discarding it.
      if (activityKind != ActivityKind.run)
        'activityKind': activityKind.wireName,
      if (elevationGainMeters != null)
        'elevationGainMeters': elevationGainMeters,
    };
  }

  /// Returns null when [value] isn't a readable draft.
  ///
  /// Null rather than a throw, matching [RoutePoint.fromMap] and
  /// [HeartRateSummary.fromMap]: one corrupt file on disk must cost one draft,
  /// never the whole list.
  static RunDraft? fromJson(Object? value) {
    if (value is! Map) return null;
    if ((value['v'] as num?)?.toInt() != schemaVersion) return null;

    final id = value['id'];
    if (id is! String || id.isEmpty) return null;

    final savedAt = _parseDate(value['savedAt']);
    if (savedAt == null) return null;

    final distanceKm = (value['distanceKm'] as num?)?.toDouble();
    if (distanceKm == null) return null;

    final seconds = (value['durationSeconds'] as num?)?.toInt();
    if (seconds == null || seconds < 0) return null;

    return RunDraft(
      id: id,
      savedAt: savedAt,
      distanceKm: distanceKm,
      elapsed: Duration(seconds: seconds),
      averagePace: value['averagePace'] as String? ?? '--',
      // A draft whose flag went missing is treated as private: publishing
      // something the runner did not ask to publish is the worse mistake.
      shareToFeed: value['shareToFeed'] as bool? ?? false,
      activityKind: ActivityKindX.fromWire(value['activityKind']),
      elevationGainMeters: (value['elevationGainMeters'] as num?)?.toInt(),
      routePoints: RoutePoint.listFromFirestore(value['routePoints']),
      startedAt: _parseDate(value['startedAt']),
      photoPath: value['photoPath'] as String?,
      photoUnavailable: value['photoUnavailable'] as bool? ?? false,
      heartRate: HeartRateSummary.fromMap(value['heartRate']),
      publishAttemptedAt: _parseDate(value['publishAttemptedAt']),
      source: RunDraftSource.fromWire(value['source']),
      externalId: value['externalId'] as String?,
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value is! String) return null;
    return DateTime.tryParse(value);
  }
}
