import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/bootstrap/bootstrap_status.dart';
import '../domain/safety_alerts.dart';
import '../domain/safety_models.dart';
import 'firestore_safety_repository.dart';
import 'panic_device.dart';
import 'panic_locator.dart';
import 'panic_repository_contract.dart';
import 'safety_repository_contract.dart';

final safetyRepositoryProvider = Provider<SafetyRepository>((ref) {
  if (ref.watch(bootstrapStatusProvider).canUseFirebase) {
    return FirestoreSafetyRepository(FirebaseFirestore.instance);
  }
  return const UnconfiguredSafetyRepository();
});

final _firestorePanicRepositoryProvider =
    Provider<FirestorePanicRepository>((ref) {
  return FirestorePanicRepository(FirebaseFirestore.instance);
});

final panicRepositoryProvider = Provider<PanicRepository>((ref) {
  if (ref.watch(bootstrapStatusProvider).canUseFirebase) {
    return ref.watch(_firestorePanicRepositoryProvider);
  }
  return const UnconfiguredPanicRepository();
});

final panicAlertRepositoryProvider = Provider<PanicAlertRepository>((ref) {
  if (ref.watch(bootstrapStatusProvider).canUseFirebase) {
    return ref.watch(_firestorePanicRepositoryProvider);
  }
  return const UnconfiguredPanicRepository();
});

final locationShareRepositoryProvider =
    Provider<LocationShareRepository>((ref) {
  if (ref.watch(bootstrapStatusProvider).canUseFirebase) {
    return FirestoreLocationShareRepository(FirebaseFirestore.instance);
  }
  return const UnconfiguredLocationShareRepository();
});

final panicDeviceProvider =
    Provider<PanicDevice>((ref) => const MethodChannelPanicDevice());

final panicLocatorProvider =
    Provider<PanicLocator>((ref) => const GeolocatorPanicLocator());

/// Stand-in for a build without Firebase: no contacts, default settings.
class UnconfiguredSafetyRepository implements SafetyRepository {
  const UnconfiguredSafetyRepository();

  @override
  Stream<SafetySettings> watchSettings(String userId) =>
      Stream.value(SafetySettings.defaults);
  @override
  Future<void> saveSettings(String userId, SafetySettings settings) async {}
  @override
  Stream<List<SafetyContact>> watchContacts(String userId) =>
      Stream.value(const []);
  @override
  Stream<List<SafetyContact>> watchContactOf(String userId) =>
      Stream.value(const []);
  @override
  Future<void> invite(String userId, String contactUid) =>
      throw UnsupportedError('Safety contacts need a backend.');
  @override
  Future<void> remove(String userId, String contactUid) async {}
  @override
  Future<void> respond({required String ownerId, required bool accept}) =>
      throw UnsupportedError('Safety contacts need a backend.');
  @override
  Future<void> revoke(String otherUid) async {}
  @override
  Stream<List<EmailSafetyContact>> watchEmailContacts(String userId) =>
      Stream.value(const []);
  @override
  Future<bool> addEmailContact({
    required String name,
    required String email,
  }) =>
      throw UnsupportedError('Safety contacts need a backend.');
  @override
  Future<void> removeEmailContact(String contactId) async {}
}

/// Without a backend a panic cannot be sent. [raise] throws, which the
/// controller reports as a failed delivery on the panic screen.
class UnconfiguredPanicRepository
    implements PanicRepository, PanicAlertRepository {
  const UnconfiguredPanicRepository();

  @override
  Future<PanicRaised> raise(PanicDraft draft) =>
      throw UnsupportedError('Panic alerts need a backend.');
  @override
  Future<void> resolve(String eventId) async {}
  @override
  Future<void> markDuress(String eventId) async {}
  @override
  Future<void> updatePosition(String eventId, SharedPosition position) async {}
  @override
  Future<List<String>> openEventIds(String userId) async => const [];
  @override
  Future<int> acceptedContactCount(String userId) async => 0;
  @override
  Stream<List<PanicAcknowledgement>> watchAcknowledgements(String eventId) =>
      Stream.value(const []);
  @override
  Stream<PanicAlert?> watchAlert(String eventId) => Stream.value(null);
  @override
  Future<void> acknowledge({
    required String eventId,
    required String userId,
    required String displayName,
  }) async {}
}

class UnconfiguredLocationShareRepository implements LocationShareRepository {
  const UnconfiguredLocationShareRepository();

  @override
  Future<String> start({
    required String ownerId,
    required String ownerName,
    required List<String> viewerIds,
    required Duration duration,
  }) =>
      throw UnsupportedError('Location sharing needs a backend.');
  @override
  Future<void> update(String shareId, SharedPosition position) async {}
  @override
  Future<void> stop(String shareId) async {}
  @override
  Stream<LocationShare?> watchMine(String ownerId) => Stream.value(null);
  @override
  Stream<List<LocationShare>> watchSharedWithMe(String viewerId) =>
      Stream.value(const []);
  @override
  Stream<LocationShare?> watch(String shareId) => Stream.value(null);
}
