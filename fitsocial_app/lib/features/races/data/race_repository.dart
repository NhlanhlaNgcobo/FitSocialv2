import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/bootstrap/bootstrap_status.dart';
import '../domain/race_models.dart';
import 'firestore_race_repository.dart';
import 'race_repository_contract.dart';

final raceRepositoryProvider = Provider<RaceRepository>((ref) {
  final status = ref.watch(bootstrapStatusProvider);
  if (status.canUseFirebase) {
    return FirestoreRaceRepository(FirebaseFirestore.instance);
  }
  return const UnconfiguredRaceRepository();
});

/// Stand-in used when Firebase was never configured for this build.
///
/// Reads come back empty so the calendar renders its empty state instead of
/// crashing. Writes throw: telling somebody their race submission was filed
/// when it went nowhere is worse than telling them it failed.
class UnconfiguredRaceRepository implements RaceRepository {
  const UnconfiguredRaceRepository();

  @override
  Future<List<RaceEvent>> fetchEvents({
    required RaceFilter filter,
    required DateTime now,
    int limit = 200,
  }) async =>
      const [];

  @override
  Future<RaceEvent?> fetchEvent(String eventId) async => null;

  @override
  Stream<List<RaceEvent>> watchSavedEvents(String userId) =>
      Stream.value(const []);

  @override
  Stream<Set<String>> watchSavedEventIds(String userId) =>
      Stream.value(const {});

  @override
  Future<void> setSaved({
    required String userId,
    required String eventId,
    required bool saved,
  }) {
    throw StateError(_firebaseSetupMessage);
  }

  /// Silently does nothing, unlike the other writes here.
  ///
  /// The other two throw because dropping somebody's save or submission without
  /// telling them would be worse than failing. A tap is different: it is
  /// measurement the user never asked for, and it must never come between them
  /// and the entry page.
  @override
  Future<void> recordEntryTap({
    required String userId,
    required String eventId,
    String? platform,
  }) async {}

  @override
  Future<void> submitRace({
    required String userId,
    required RaceSubmission submission,
  }) {
    throw StateError(_firebaseSetupMessage);
  }
}

const _firebaseSetupMessage =
    'Firebase is not configured. Run flutterfire configure to generate lib/firebase_options.dart.';
