import 'app_models.dart';

/// One exercise card on the Log Workout form, exactly as typed.
///
/// Text rather than numbers: a half-typed "82," must come back as "82,", not
/// as 82 or as nothing.
class WorkoutLogFormRow {
  const WorkoutLogFormRow({
    required this.name,
    this.exerciseId,
    this.cardio = false,
    this.sets = '',
    this.reps = '',
    this.weight = '',
    this.minutes = '',
    this.distance = '',
  });

  static WorkoutLogFormRow? fromJson(Object? json) {
    if (json is! Map) return null;
    final name = (json['name'] as String?)?.trim() ?? '';
    if (name.isEmpty) return null;
    String text(String key) => (json[key] as String?) ?? '';
    return WorkoutLogFormRow(
      name: name,
      exerciseId: json['exerciseId'] as String?,
      cardio: json['cardio'] == true,
      sets: text('sets'),
      reps: text('reps'),
      weight: text('weight'),
      minutes: text('minutes'),
      distance: text('distance'),
    );
  }

  final String name;
  final String? exerciseId;
  final bool cardio;
  final String sets;
  final String reps;
  final String weight;
  final String minutes;
  final String distance;

  Map<String, Object?> toJson() => {
        'name': name,
        if (exerciseId != null) 'exerciseId': exerciseId,
        if (cardio) 'cardio': true,
        'sets': sets,
        'reps': reps,
        'weight': weight,
        'minutes': minutes,
        'distance': distance,
      };
}

/// Everything typed into Log Workout that has not been saved yet.
///
/// The form used to live only in the screen's memory. Leaving the app for a
/// few minutes is often enough for Android to reclaim it, and the tester came
/// back to an empty form — the workout log "disappeared". This is what is put
/// on disk instead, rewritten as the form changes, so coming back to the
/// screen picks up where it was left.
class WorkoutLogForm {
  const WorkoutLogForm({
    required this.savedAt,
    required this.loggedAt,
    this.title = '',
    this.duration = '',
    this.calories = '',
    this.notes = '',
    this.shareToFeed = true,
    this.backgroundPath,
    this.taggedUsers = const [],
    this.rows = const [],
  });

  /// How long an unsaved form is worth offering back. Past a day it is not
  /// "the workout I was just logging" any more, and finding it pre-filled
  /// would be a surprise rather than a rescue.
  static const maxAge = Duration(hours: 24);

  /// Null when [json] is not a form this build can read.
  static WorkoutLogForm? fromJson(Object? json) {
    if (json is! Map) return null;
    DateTime? at(String key) => switch (json[key]) {
          final num millis =>
            DateTime.fromMillisecondsSinceEpoch(millis.toInt()),
          _ => null,
        };
    final savedAt = at('savedAt');
    final loggedAt = at('loggedAt');
    if (savedAt == null || loggedAt == null) return null;
    String text(String key) => (json[key] as String?) ?? '';
    return WorkoutLogForm(
      savedAt: savedAt,
      loggedAt: loggedAt,
      title: text('title'),
      duration: text('duration'),
      calories: text('calories'),
      notes: text('notes'),
      shareToFeed: json['shareToFeed'] != false,
      backgroundPath: json['backgroundPath'] as String?,
      taggedUsers: TaggedUser.listFrom(json['taggedUsers']),
      rows: (json['rows'] as List<dynamic>?)
              ?.map(WorkoutLogFormRow.fromJson)
              .whereType<WorkoutLogFormRow>()
              .toList(growable: false) ??
          const [],
    );
  }

  /// When this was last written. What [isStale] is measured from.
  final DateTime savedAt;

  /// When the session happened, as the form's date chip says.
  final DateTime loggedAt;

  final String title;
  final String duration;
  final String calories;
  final String notes;
  final bool shareToFeed;
  final String? backgroundPath;
  final List<TaggedUser> taggedUsers;
  final List<WorkoutLogFormRow> rows;

  /// Whether anything was typed or picked. An untouched form is not worth
  /// saving, offering back, or announcing.
  bool get hasContent =>
      title.trim().isNotEmpty ||
      duration.trim().isNotEmpty ||
      calories.trim().isNotEmpty ||
      notes.trim().isNotEmpty ||
      backgroundPath != null ||
      rows.isNotEmpty;

  bool isStale(DateTime now) => now.difference(savedAt) > maxAge;

  Map<String, Object?> toJson() => {
        'savedAt': savedAt.millisecondsSinceEpoch,
        'loggedAt': loggedAt.millisecondsSinceEpoch,
        'title': title,
        'duration': duration,
        'calories': calories,
        'notes': notes,
        'shareToFeed': shareToFeed,
        if (backgroundPath != null) 'backgroundPath': backgroundPath,
        if (taggedUsers.isNotEmpty)
          'taggedUsers': taggedUsers.map((u) => u.toMap()).toList(),
        'rows': rows.map((r) => r.toJson()).toList(),
      };
}
