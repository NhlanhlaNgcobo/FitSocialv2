import '../../main/domain/app_models.dart';

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
  });

  /// Bumped whenever the stored shape changes in a way older files can't be
  /// read as. [fromJson] rejects anything it doesn't recognise rather than
  /// guessing, so a draft from a future version is skipped, not misread.
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

  /// True once a publish has been attempted and the draft outlived it.
  bool get mayHavePublished => publishAttemptedAt != null;

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
  }) {
    return RunDraft(
      id: id,
      savedAt: savedAt,
      distanceKm: distanceKm,
      elapsed: elapsed,
      averagePace: averagePace,
      shareToFeed: shareToFeed,
      routePoints: routePoints,
      startedAt: startedAt,
      photoPath: clearPhotoPath ? null : photoPath ?? this.photoPath,
      photoUnavailable: photoUnavailable ?? this.photoUnavailable,
      heartRate: heartRate,
      publishAttemptedAt: publishAttemptedAt ?? this.publishAttemptedAt,
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
      routePoints: RoutePoint.listFromFirestore(value['routePoints']),
      startedAt: _parseDate(value['startedAt']),
      photoPath: value['photoPath'] as String?,
      photoUnavailable: value['photoUnavailable'] as bool? ?? false,
      heartRate: HeartRateSummary.fromMap(value['heartRate']),
      publishAttemptedAt: _parseDate(value['publishAttemptedAt']),
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value is! String) return null;
    return DateTime.tryParse(value);
  }
}
