import '../domain/safety_alerts.dart';
import '../domain/safety_models.dart';

/// Safety contacts and panic settings. See spec A.2 and A.3.
abstract class SafetyRepository {
  /// This user's panic settings and PIN hashes. Stored under
  /// `users/{uid}/private/safety`, NOT on the public user document the spec
  /// names: every signed-in user can read `users/{uid}`, and a four-digit PIN
  /// hash there would hand anyone both PINs — including which is the duress
  /// one — for 10,000 hashes' work.
  Stream<SafetySettings> watchSettings(String userId);

  Future<void> saveSettings(String userId, SafetySettings settings);

  /// People this user asked to watch over them, every status.
  Stream<List<SafetyContact>> watchContacts(String userId);

  /// People who asked this user, every status.
  Stream<List<SafetyContact>> watchContactOf(String userId);

  /// Opens a pending invite. Clears a declined or revoked row first, so the
  /// same person can be asked again.
  Future<void> invite(String userId, String contactUid);

  /// Withdraws a row of this user's own — an unanswered invite, or a contact
  /// they no longer want. The other side's mirror is removed by the server.
  Future<void> remove(String userId, String contactUid);

  /// The invitee's answer.
  Future<void> respond({required String ownerId, required bool accept});

  /// Ends the relationship from either side. When the contact is the one
  /// revoking, the owner is told.
  Future<void> revoke(String otherUid);

  /// This user's email contacts, every status.
  Stream<List<EmailSafetyContact>> watchEmailContacts(String userId);

  /// Adds someone without FitSocial and emails them a confirmation link.
  /// They are not alerted until they confirm. Returns whether the email was
  /// handed to the mail service.
  Future<bool> addEmailContact({required String name, required String email});

  Future<void> removeEmailContact(String contactId);
}

/// The recipient side of a panic event.
abstract class PanicAlertRepository {
  Stream<PanicAlert?> watchAlert(String eventId);

  Stream<List<PanicAcknowledgement>> watchAcknowledgements(String eventId);

  /// "I'm responding".
  Future<void> acknowledge({
    required String eventId,
    required String userId,
    required String displayName,
  });
}

/// Foreground location sharing. See spec A.4.
abstract class LocationShareRepository {
  /// Opens a share. Every viewer must be an accepted contact; the rules
  /// refuse the write otherwise. [duration] is capped at
  /// [LocationShare.maxDuration].
  Future<String> start({
    required String ownerId,
    required String ownerName,
    required List<String> viewerIds,
    required Duration duration,
  });

  /// Replaces the single `current` field. No per-tick history.
  Future<void> update(String shareId, SharedPosition position);

  Future<void> stop(String shareId);

  /// This user's active share, if any.
  Stream<LocationShare?> watchMine(String ownerId);

  /// Active shares this user may view.
  Stream<List<LocationShare>> watchSharedWithMe(String viewerId);

  Stream<LocationShare?> watch(String shareId);
}
