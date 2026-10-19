import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/app_session.dart';
import '../../main/application/content_providers.dart'
    show currentUserIdProvider, followingIdsProvider;
import '../../main/domain/app_models.dart' show PostPrompt;
import '../../pulse/application/pulse_providers.dart';
import '../data/note_repository.dart';
import '../domain/note_models.dart';

/// Every current Note the signed-in user may see: the people they follow,
/// plus their own. The same audience as Pulses, from the same follow graph.
final activeNotesProvider = StreamProvider<List<FitNote>>((ref) {
  ref.watch(appSessionProvider);
  final currentUserId = ref.watch(currentUserIdProvider);
  if (currentUserId == null) return Stream.value(const <FitNote>[]);
  final following = ref.watch(followingIdsProvider).valueOrNull ?? const {};
  return ref
      .watch(noteRepositoryProvider)
      .watchNotes({...following, currentUserId});
});

/// The signed-in user's own live Note, or null.
final myNoteProvider = Provider<FitNote?>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  final notes = ref.watch(activeNotesProvider).valueOrNull ?? const [];
  final now = DateTime.now();
  for (final note in notes) {
    if (note.authorId == userId && !note.isExpiredAt(now)) return note;
  }
  return null;
});

/// Everyone else's avatars in the tray, Pulses and Notes joined.
///
/// Notes are treated as empty while they load, so the Pulse rings never wait
/// on them.
final trayTilesProvider = Provider<AsyncValue<List<TrayTile>>>((ref) {
  final pulses = ref.watch(pulseTrayProvider);
  final notes = ref.watch(activeNotesProvider).valueOrNull ?? const [];
  final currentUserId = ref.watch(currentUserIdProvider);
  return pulses.whenData(
    (entries) => buildTrayTiles(
      pulses: entries,
      notes: notes,
      currentUserId: currentUserId,
      now: DateTime.now(),
    ),
  );
});

/// Who hearted the signed-in user's Note.
final noteHeartsProvider =
    StreamProvider.autoDispose.family<List<NoteHeart>, String>((ref, noteId) {
  return ref.watch(noteRepositoryProvider).watchHearts(noteId);
});

/// Whether the signed-in user has hearted the Note [noteId] by [authorId].
///
/// Keyed by the two ids rather than the Note, which has no value equality:
/// a fresh snapshot of the same Note must find the same stream.
final myNoteHeartProvider = StreamProvider.autoDispose
    .family<bool, ({String authorId, String noteId})>((ref, key) {
  return ref
      .watch(noteRepositoryProvider)
      .watchMyHeart(key.authorId, key.noteId);
});

/// Write-side actions. Every read here is live, so nothing is invalidated.
class NoteActions {
  const NoteActions(this._ref);

  final Ref _ref;

  Future<FitNote> answer(PostPrompt prompt, String text) {
    final profile = _ref.read(appSessionProvider).profile;
    return _ref
        .read(noteRepositoryProvider)
        .publish(profile, NoteDraft(prompt: prompt, text: text));
  }

  Future<void> delete() => _ref.read(noteRepositoryProvider).deleteNote();

  Future<void> setHeart(FitNote note, {required bool hearted}) {
    final profile = _ref.read(appSessionProvider).profile;
    return _ref
        .read(noteRepositoryProvider)
        .setHeart(note, hearted: hearted, profile: profile);
  }

  Future<void> reply(FitNote note, String text) {
    final profile = _ref.read(appSessionProvider).profile;
    return _ref.read(noteRepositoryProvider).reply(note, text, profile);
  }
}

final noteActionsProvider = Provider<NoteActions>((ref) => NoteActions(ref));
