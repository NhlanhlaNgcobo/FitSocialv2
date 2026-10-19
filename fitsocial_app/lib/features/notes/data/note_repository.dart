import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/bootstrap/bootstrap_status.dart';
import '../../auth/domain/auth_models.dart';
import '../domain/note_models.dart';
import 'firestore_note_repository.dart';
import 'note_repository_contract.dart';

final noteRepositoryProvider = Provider<NoteRepository>((ref) {
  final status = ref.watch(bootstrapStatusProvider);
  if (status.canUseFirebase) {
    return FirestoreNoteRepository(FirebaseFirestore.instance);
  }
  return const UnconfiguredNoteRepository();
});

/// Stand-in used when Firebase was never configured for this build: reads
/// come back empty, writes fail loudly — the same split as Pulses.
class UnconfiguredNoteRepository implements NoteRepository {
  const UnconfiguredNoteRepository();

  @override
  Stream<List<FitNote>> watchNotes(Set<String> authorIds) =>
      Stream.value(const []);

  @override
  Future<FitNote> publish(UserProfileDraft? profile, NoteDraft draft) =>
      throw StateError(_firebaseSetupMessage);

  @override
  Future<void> deleteNote() => throw StateError(_firebaseSetupMessage);

  @override
  Stream<List<NoteHeart>> watchHearts(String noteId) => Stream.value(const []);

  @override
  Stream<bool> watchMyHeart(String authorId, String noteId) =>
      Stream.value(false);

  @override
  Future<void> setHeart(
    FitNote note, {
    required bool hearted,
    UserProfileDraft? profile,
  }) =>
      throw StateError(_firebaseSetupMessage);

  @override
  Future<void> reply(FitNote note, String text, UserProfileDraft? profile) =>
      throw StateError(_firebaseSetupMessage);
}

const _firebaseSetupMessage =
    'Firebase is not configured. Run flutterfire configure to generate lib/firebase_options.dart.';
