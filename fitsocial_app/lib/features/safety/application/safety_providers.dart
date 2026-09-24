import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../auth/application/app_session.dart';
import '../../main/application/content_providers.dart'
    show currentUserIdProvider;
import '../data/safety_repositories.dart';
import '../domain/safety_alerts.dart';
import '../domain/safety_models.dart';
import 'location_share_controller.dart';
import 'panic_controller.dart';

/// The signed-in user's panic settings, live. Defaults while loading or
/// signed out — which leaves the alarm stoppable without a PIN, the safe
/// failure.
final safetySettingsProvider = StreamProvider<SafetySettings>((ref) {
  ref.watch(appSessionProvider);
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return Stream.value(SafetySettings.defaults);
  return ref.watch(safetyRepositoryProvider).watchSettings(uid);
});

/// People I asked to watch over me.
final safetyContactsProvider = StreamProvider<List<SafetyContact>>((ref) {
  ref.watch(appSessionProvider);
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(safetyRepositoryProvider).watchContacts(uid);
});

/// People who asked me.
final safetyContactOfProvider = StreamProvider<List<SafetyContact>>((ref) {
  ref.watch(appSessionProvider);
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(safetyRepositoryProvider).watchContactOf(uid);
});

/// Contacts without FitSocial, reached by email.
final emailSafetyContactsProvider =
    StreamProvider<List<EmailSafetyContact>>((ref) {
  ref.watch(appSessionProvider);
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(safetyRepositoryProvider).watchEmailContacts(uid);
});

/// How many of the three slots are taken, both kinds together. The add
/// buttons disable at [maxAcceptedSafetyContacts].
final usedSafetySlotsProvider = Provider<int>((ref) {
  return usedSafetySlots(
    ref.watch(safetyContactsProvider).valueOrNull ?? const [],
    ref.watch(emailSafetyContactsProvider).valueOrNull ?? const [],
  );
});

final acceptedSafetyContactsProvider = Provider<List<SafetyContact>>((ref) {
  final all = ref.watch(safetyContactsProvider).valueOrNull ?? const [];
  return all.where((c) => c.isAccepted).toList(growable: false);
});

/// One panic at a time, app-wide. Not auto-disposed: an alarm must never be
/// torn down because the widget that started it left the tree.
final panicControllerProvider =
    StateNotifierProvider<PanicController, PanicState>((ref) {
  return PanicController(
    repository: ref.watch(panicRepositoryProvider),
    device: ref.watch(panicDeviceProvider),
    locator: ref.watch(panicLocatorProvider),
    userId: () => ref.read(currentUserIdProvider),
    settings: () =>
        ref.read(safetySettingsProvider).valueOrNull ?? SafetySettings.defaults,
    onWrongPin: HapticFeedback.heavyImpact,
  );
});

final locationShareControllerProvider =
    StateNotifierProvider<LocationShareController, LocationShareState>((ref) {
  final device = ref.watch(panicDeviceProvider);
  return LocationShareController(
    repository: ref.watch(locationShareRepositoryProvider),
    positions: () => Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).map((p) =>
        PanicPosition(lat: p.latitude, lng: p.longitude, accuracy: p.accuracy)),
    battery: device.batteryPercent,
  );
});

/// Active shares I may view.
final sharedWithMeProvider = StreamProvider<List<LocationShare>>((ref) {
  ref.watch(appSessionProvider);
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(locationShareRepositoryProvider).watchSharedWithMe(uid);
});

final locationShareProvider =
    StreamProvider.family<LocationShare?, String>((ref, shareId) {
  return ref.watch(locationShareRepositoryProvider).watch(shareId);
});

/// A panic event, as the recipient sees it.
final panicAlertProvider =
    StreamProvider.family<PanicAlert?, String>((ref, eventId) {
  return ref.watch(panicAlertRepositoryProvider).watchAlert(eventId);
});

final panicAcknowledgementsProvider =
    StreamProvider.family<List<PanicAcknowledgement>, String>((ref, eventId) {
  return ref.watch(panicAlertRepositoryProvider).watchAcknowledgements(eventId);
});
