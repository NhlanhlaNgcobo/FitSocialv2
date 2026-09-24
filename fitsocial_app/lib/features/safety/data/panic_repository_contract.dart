import '../domain/safety_alerts.dart';
import '../domain/safety_models.dart';

/// Backend side of a panic event. See spec A.2 and A.6.
///
/// Recipients are deliberately absent from every method. The client names no
/// one: the Cloud Function reads the raiser's accepted contacts itself, and
/// that is the enforcement point for the whole consent design.
abstract class PanicRepository {
  /// Commits a new `panicEvents` document.
  ///
  /// Completes once the write is acknowledged by the server or is sitting in
  /// the offline queue — whichever comes first — and never waits longer than
  /// it takes to be queued. [PanicRaised.delivered] reports the server
  /// acknowledgement separately.
  ///
  /// Throws only if the write could not even be queued.
  Future<PanicRaised> raise(PanicDraft draft);

  /// The user entered their safe PIN: close the event. Works on an active
  /// event and on one left open by the duress PIN.
  Future<void> resolve(String eventId);

  /// Replaces the event's single live position. Written every 30 seconds for
  /// as long as the event is open — through a duress cancel, and until the
  /// safe PIN ends it.
  Future<void> updatePosition(String eventId, SharedPosition position);

  /// [userId]'s events that are still open (active or duress), newest first.
  /// How live sharing resumes after the app restarts, and what the safe PIN
  /// closes when it is entered later.
  Future<List<String>> openEventIds(String userId);

  /// The user entered their duress PIN: keep the event open, flagged.
  Future<void> markDuress(String eventId);

  /// Contacts who pressed "I'm responding", live.
  Stream<List<PanicAcknowledgement>> watchAcknowledgements(String eventId);

  /// How many accepted safety contacts [userId] has. What "Alerting N
  /// contacts" is drawn from — a count of who the alert was addressed to,
  /// never a confirmation that anyone received it.
  Future<int> acceptedContactCount(String userId);
}
