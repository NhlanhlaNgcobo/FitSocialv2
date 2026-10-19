import '../../main/domain/app_models.dart' show PostPrompt;
import '../../main/domain/daily_prompts.dart';
import '../../pulse/domain/pulse_models.dart';

/// Rules every Note shares.
///
/// Instagram's numbers, on purpose: 60 characters is a line you can read in
/// the tray without opening anything, and a day is long enough that the
/// people who check in once still catch it.
abstract final class NoteTiming {
  static const int maxLength = 60;
  static const Duration lifetime = Duration(hours: 24);
}

/// One person's answer to the day's question, shown as a bubble over their
/// avatar in the Pulse tray.
///
/// A Note only exists once somebody answers. The question itself is never
/// stored or shown to anyone else: it sits over the asker's own avatar, for
/// them alone, until they answer it or the day rolls over.
///
/// One per person. Answering again replaces the last one, which is what keeps
/// the tray to a single bubble per avatar.
class FitNote {
  const FitNote({
    required this.authorId,
    required this.authorName,
    required this.noteId,
    required this.text,
    required this.promptId,
    required this.promptText,
    required this.createdAt,
    required this.expiresAt,
    this.authorAvatarUrl,
  });

  /// Also the document id: `notes/{authorId}`.
  final String authorId;
  final String authorName;
  final String? authorAvatarUrl;

  /// Fresh on every answer. Hearts carry it, so a heart left on yesterday's
  /// answer does not count towards today's.
  final String noteId;

  /// The answer, at most [NoteTiming.maxLength] characters.
  final String text;

  /// The day key and wording of the question it answers, copied on so the
  /// bubble still makes sense after the question rolls over.
  final String promptId;
  final String promptText;

  final DateTime createdAt;
  final DateTime expiresAt;

  bool isExpiredAt(DateTime now) => !expiresAt.isAfter(now);

  /// Whether this answers the question asked on [promptId].
  bool answers(String promptId) => this.promptId == promptId;
}

/// What a person typed in answer to [prompt].
class NoteDraft {
  const NoteDraft({required this.prompt, required this.text});

  final PostPrompt prompt;
  final String text;

  String get trimmed => text.trim();

  bool get isPublishable =>
      trimmed.isNotEmpty && trimmed.length <= NoteTiming.maxLength;
}

/// Someone who hearted a Note. The author sees the list.
class NoteHeart {
  const NoteHeart({
    required this.userId,
    required this.userName,
    required this.noteId,
    this.userAvatarUrl,
    this.createdAt,
  });

  final String userId;
  final String userName;
  final String? userAvatarUrl;
  final String noteId;
  final DateTime? createdAt;
}

/// Today's question, which rolls over at local midnight.
PostPrompt todaysQuestion(DateTime now) => DailyPrompts.forDay(now);

/// One avatar in the tray: a Pulse ring, a Note bubble, or both.
class TrayTile {
  const TrayTile({
    required this.authorId,
    required this.authorName,
    this.authorAvatarUrl,
    this.pulse,
    this.note,
  });

  final String authorId;
  final String authorName;
  final String? authorAvatarUrl;

  /// Null when they have nothing live — the avatar then has no ring.
  final PulseTrayEntry? pulse;

  /// Null when they have not answered, or the answer has run out.
  final FitNote? note;

  String get displayLabel {
    final first = authorName.trim().split(' ').first;
    return first.isEmpty ? authorName : first;
  }
}

/// Joins everyone else's Pulses and Notes into one row of avatars.
///
/// Your own tile is not in the result: the tray always draws it first, from
/// its own data, whether or not you have anything live. The rest, left to
/// right:
///
/// 1. unseen Pulses, in the order the Pulse tray already put them;
/// 2. Notes from people with nothing unseen, newest first — a fresh answer is
///    news too, and it should not sit behind a ring already watched;
/// 3. the remaining watched Pulses.
///
/// Somebody with both a Pulse and a Note gets one tile carrying both. An
/// expired Note is dropped here as well as by the query, for the same reason
/// [buildPulseTray] drops expired Pulses: the server sweep is not prompt.
List<TrayTile> buildTrayTiles({
  required List<PulseTrayEntry> pulses,
  required List<FitNote> notes,
  required String? currentUserId,
  required DateTime now,
}) {
  final notesByAuthor = <String, FitNote>{
    for (final note in notes)
      if (!note.isExpiredAt(now)) note.authorId: note,
  };

  TrayTile fromPulse(PulseTrayEntry entry) => TrayTile(
        authorId: entry.authorId,
        authorName: entry.authorName,
        authorAvatarUrl: entry.authorAvatarUrl,
        pulse: entry,
        note: notesByAuthor[entry.authorId],
      );

  final unseen = <TrayTile>[];
  final watched = <TrayTile>[];
  final withPulse = <String>{};
  for (final entry in pulses) {
    if (entry.isOwn) continue;
    withPulse.add(entry.authorId);
    (entry.hasUnseen ? unseen : watched).add(fromPulse(entry));
  }

  // A watched ring with a fresh Note moves up among the Notes: the bubble is
  // the new thing there.
  final noted = <TrayTile>[
    for (final note in notesByAuthor.values)
      if (note.authorId != currentUserId && !withPulse.contains(note.authorId))
        TrayTile(
          authorId: note.authorId,
          authorName: note.authorName,
          authorAvatarUrl: note.authorAvatarUrl,
          note: note,
        ),
    ...watched.where((tile) => tile.note != null),
  ]..sort((a, b) => b.note!.createdAt.compareTo(a.note!.createdAt));

  return [
    ...unseen,
    ...noted,
    ...watched.where((tile) => tile.note == null),
  ];
}
