import '../../auth/domain/auth_models.dart';
import '../domain/note_models.dart';

/// Storage for Notes — one short answer per person to the day's question.
abstract class NoteRepository {
  /// The current Note of each of [authorIds] that has one.
  ///
  /// The audience is passed in, as it is for Pulses: callers pass the people
  /// the viewer follows, plus the viewer. Expired Notes may still arrive —
  /// [buildTrayTiles] drops them.
  Stream<List<FitNote>> watchNotes(Set<String> authorIds);

  /// Posts [draft] as the signed-in user's Note, replacing any earlier one
  /// along with the hearts it collected.
  Future<FitNote> publish(UserProfileDraft? profile, NoteDraft draft);

  /// Takes the signed-in user's Note down.
  Future<void> deleteNote();

  /// Who hearted the signed-in user's Note [noteId], newest first.
  Stream<List<NoteHeart>> watchHearts(String noteId);

  /// Whether the signed-in user has hearted [authorId]'s Note [noteId].
  Stream<bool> watchMyHeart(String authorId, String noteId);

  /// Hearts or un-hearts [note], telling its author either way.
  Future<void> setHeart(FitNote note,
      {required bool hearted, UserProfileDraft? profile});

  /// Sends [text] to [note]'s author, privately, as a notification.
  Future<void> reply(FitNote note, String text, UserProfileDraft? profile);
}
