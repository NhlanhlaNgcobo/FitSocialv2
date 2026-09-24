import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../core/config/functions_region.dart';
import '../domain/safety_alerts.dart';
import '../domain/safety_models.dart';
import 'panic_repository_contract.dart';
import 'safety_repository_contract.dart';

DateTime? _date(Object? raw) => raw is Timestamp ? raw.toDate() : null;

double _double(Object? raw) => raw is num ? raw.toDouble() : 0;

int? _int(Object? raw) => raw is num ? raw.toInt() : null;

/// Firestore-backed safety contacts and settings.
///
/// Layout:
///   users/{uid}/private/safety              — settings and PIN hashes
///   users/{uid}/safetyContacts/{contactUid} — people I asked
///   users/{uid}/safetyContactOf/{ownerUid}  — people who asked me (mirror)
///
/// Only the invite and the withdrawal are client writes. Accept, decline and
/// revoke go through callables in functions/safety.js, which write both sides.
class FirestoreSafetyRepository implements SafetyRepository {
  FirestoreSafetyRepository(this._firestore, {FirebaseFunctions? functions})
      : _functions = functions;

  final FirebaseFirestore _firestore;
  final FirebaseFunctions? _functions;

  FirebaseFunctions get _fns => _functions ?? appFunctions;

  DocumentReference<Map<String, dynamic>> _settings(String uid) =>
      _firestore.collection('users').doc(uid).collection('private').doc('safety');

  CollectionReference<Map<String, dynamic>> _contacts(String uid) =>
      _firestore.collection('users').doc(uid).collection('safetyContacts');

  CollectionReference<Map<String, dynamic>> _contactOf(String uid) =>
      _firestore.collection('users').doc(uid).collection('safetyContactOf');

  @override
  Stream<SafetySettings> watchSettings(String userId) => _settings(userId)
      .snapshots()
      .map((doc) => SafetySettings.fromMap(doc.data()));

  @override
  Future<void> saveSettings(String userId, SafetySettings settings) =>
      _settings(userId).set(settings.toMap(), SetOptions(merge: true));

  @override
  Stream<List<SafetyContact>> watchContacts(String userId) =>
      _contacts(userId).snapshots().map(_toContacts);

  @override
  Stream<List<SafetyContact>> watchContactOf(String userId) =>
      _contactOf(userId).snapshots().map(_toContacts);

  List<SafetyContact> _toContacts(QuerySnapshot<Map<String, dynamic>> snap) {
    return snap.docs.map((doc) {
      final d = doc.data();
      return SafetyContact(
        uid: doc.id,
        status: SafetyContactStatus.parse(d['status']),
        displayName: d['displayName'] as String? ?? '',
        handle: d['handle'] as String? ?? '',
        avatarUrl: d['avatarUrl'] as String?,
        invitedAt: _date(d['invitedAt']),
        respondedAt: _date(d['respondedAt']),
      );
    }).toList(growable: false);
  }

  @override
  Future<void> invite(String userId, String contactUid) async {
    final ref = _contacts(userId).doc(contactUid);
    // Rows are never updated by the client, so asking again after a decline
    // or revoke means clearing the old row first.
    final existing = await ref.get();
    if (existing.exists) {
      final status = SafetyContactStatus.parse(existing.data()?['status']);
      if (status == SafetyContactStatus.pending ||
          status == SafetyContactStatus.accepted) {
        return;
      }
      await ref.delete();
    }
    // Profile fields are filled in by the server from the real user docs.
    await ref.set({
      'contactUid': contactUid,
      'status': SafetyContactStatus.pending.name,
      'invitedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> remove(String userId, String contactUid) =>
      _contacts(userId).doc(contactUid).delete();

  @override
  Future<void> respond({required String ownerId, required bool accept}) async {
    await _fns
        .httpsCallable('respondToSafetyContact')
        .call<Map<String, dynamic>>({'ownerId': ownerId, 'accept': accept});
  }

  @override
  Future<void> revoke(String otherUid) async {
    await _fns
        .httpsCallable('revokeSafetyContact')
        .call<Map<String, dynamic>>({'otherUid': otherUid});
  }

  @override
  Stream<List<EmailSafetyContact>> watchEmailContacts(String userId) =>
      _firestore
          .collection('users')
          .doc(userId)
          .collection('emailContacts')
          .snapshots()
          .map((snap) => snap.docs.map((doc) {
                final d = doc.data();
                return EmailSafetyContact(
                  id: doc.id,
                  name: d['name'] as String? ?? '',
                  email: d['email'] as String? ?? '',
                  status: EmailContactStatus.parse(d['status']),
                  addedAt: _date(d['addedAt']),
                  confirmedAt: _date(d['confirmedAt']),
                );
              }).toList(growable: false));

  @override
  Future<bool> addEmailContact({
    required String name,
    required String email,
  }) async {
    final result = await _fns
        .httpsCallable('addEmailSafetyContact')
        .call<Map<String, dynamic>>({'name': name, 'email': email});
    return result.data['emailSent'] == true;
  }

  @override
  Future<void> removeEmailContact(String contactId) async {
    await _fns
        .httpsCallable('removeEmailSafetyContact')
        .call<Map<String, dynamic>>({'contactId': contactId});
  }
}

/// Firestore-backed panic events, for both the raiser and the recipients.
class FirestorePanicRepository
    implements PanicRepository, PanicAlertRepository {
  FirestorePanicRepository(this._firestore);

  /// How long [raise] waits for the server before settling for the offline
  /// queue. Short: the panic screen waits on this before showing the alert as active.
  static const Duration queueWait = Duration(milliseconds: 1500);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _events =>
      _firestore.collection('panicEvents');

  @override
  Future<PanicRaised> raise(PanicDraft draft) async {
    final ref = _events.doc();
    // The Firestore SDK puts the write in its local queue when set() is
    // called and sends it when it can; the future only completes on server
    // acknowledgement. So: wait briefly for the server, and otherwise return
    // with the write queued — it survives the app, not the uninstall.
    final write = ref.set({
      'userId': draft.userId,
      'status': PanicEventStatus.active.name,
      'duress': false,
      'location': draft.position?.toMap(),
      'batteryPercent': draft.batteryPercent,
      'notifiedUserIds': const <String>[],
      'raisedAt': FieldValue.serverTimestamp(),
      'closedAt': null,
      'clientRaisedAtMillis': draft.clientRaisedAt.millisecondsSinceEpoch,
    });
    final delivered = write.then((_) => true, onError: (Object _) => false);
    await Future.any<void>([
      delivered.then((_) {}),
      Future<void>.delayed(queueWait),
    ]);
    return PanicRaised(eventId: ref.id, delivered: delivered);
  }

  @override
  Future<void> resolve(String eventId) => _events.doc(eventId).update({
        'status': PanicEventStatus.resolved.name,
        'closedAt': FieldValue.serverTimestamp(),
      });

  @override
  Future<void> updatePosition(String eventId, SharedPosition position) =>
      _events.doc(eventId).update({
        'current': {
          'lat': position.lat,
          'lng': position.lng,
          'accuracy': position.accuracy,
          'batteryPercent': position.batteryPercent,
          'updatedAt': FieldValue.serverTimestamp(),
        },
      });

  @override
  Future<List<String>> openEventIds(String userId) async {
    final snap = await _events
        .where('userId', isEqualTo: userId)
        .where('status', whereIn: [
      PanicEventStatus.active.name,
      PanicEventStatus.duress.name,
    ]).get();
    // Sorted here rather than by the query, which would need a composite
    // index for a list that is almost always one long.
    final docs = [...snap.docs]..sort((a, b) {
        final ta = _date(a.data()['raisedAt']) ?? DateTime(0);
        final tb = _date(b.data()['raisedAt']) ?? DateTime(0);
        return tb.compareTo(ta);
      });
    return docs.map((d) => d.id).toList(growable: false);
  }

  @override
  Future<void> markDuress(String eventId) => _events.doc(eventId).update({
        'status': PanicEventStatus.duress.name,
        'duress': true,
      });

  /// FitSocial contacts who accepted plus email contacts who confirmed:
  /// everyone the alert is addressed to, however it reaches them.
  @override
  Future<int> acceptedContactCount(String userId) async {
    final user = _firestore.collection('users').doc(userId);
    final results = await Future.wait([
      user
          .collection('safetyContacts')
          .where('status', isEqualTo: SafetyContactStatus.accepted.name)
          .get(),
      user
          .collection('emailContacts')
          .where('status', isEqualTo: EmailContactStatus.confirmed.name)
          .get(),
    ]);
    return results[0].size + results[1].size;
  }

  @override
  Stream<List<PanicAcknowledgement>> watchAcknowledgements(String eventId) {
    return _events
        .doc(eventId)
        .collection('acknowledgements')
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => PanicAcknowledgement(
                  uid: doc.id,
                  displayName: doc.data()['displayName'] as String? ?? '',
                  acknowledgedAt: _date(doc.data()['acknowledgedAt']),
                ))
            .toList(growable: false));
  }

  @override
  Stream<PanicAlert?> watchAlert(String eventId) {
    return _events.doc(eventId).snapshots().map((doc) {
      final d = doc.data();
      if (d == null) return null;
      final loc = d['location'];
      final live = d['current'];
      final alerted = d['notifiedContacts'];
      return PanicAlert(
        eventId: doc.id,
        userId: d['userId'] as String? ?? '',
        userName: d['userName'] as String? ?? 'Someone',
        userAvatarUrl: d['userAvatarUrl'] as String?,
        status: PanicEventStatus.parse(d['status']),
        position: loc is Map
            ? PanicPosition(
                lat: _double(loc['lat']),
                lng: _double(loc['lng']),
                accuracy: _double(loc['accuracy']),
                isLastKnown: loc['isLastKnown'] == true,
              )
            : null,
        current: live is Map
            ? SharedPosition(
                lat: _double(live['lat']),
                lng: _double(live['lng']),
                accuracy: _double(live['accuracy']),
                batteryPercent: _int(live['batteryPercent']),
                updatedAt: _date(live['updatedAt']),
              )
            : null,
        batteryPercent: _int(d['batteryPercent']),
        raisedAt: _date(d['raisedAt']),
        alerted: alerted is List
            ? alerted
                .whereType<Map>()
                .map((c) => AlertedContact(
                      uid: c['uid'] as String? ?? '',
                      displayName: c['displayName'] as String? ?? '',
                    ))
                .toList(growable: false)
            : const [],
      );
    });
  }

  @override
  Future<void> acknowledge({
    required String eventId,
    required String userId,
    required String displayName,
  }) {
    return _events.doc(eventId).collection('acknowledgements').doc(userId).set({
      'displayName': displayName,
      'acknowledgedAt': FieldValue.serverTimestamp(),
    });
  }
}

/// Firestore-backed location shares. `locationShares/{shareId}`.
class FirestoreLocationShareRepository implements LocationShareRepository {
  FirestoreLocationShareRepository(this._firestore, {DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final FirebaseFirestore _firestore;
  final DateTime Function() _now;

  CollectionReference<Map<String, dynamic>> get _shares =>
      _firestore.collection('locationShares');

  @override
  Future<String> start({
    required String ownerId,
    required String ownerName,
    required List<String> viewerIds,
    required Duration duration,
  }) async {
    final capped = duration > LocationShare.maxDuration
        ? LocationShare.maxDuration
        : duration;
    final ref = _shares.doc();
    await ref.set({
      'ownerId': ownerId,
      'ownerName': ownerName,
      'viewerIds': viewerIds,
      'startedAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(_now().add(capped)),
      'endedAt': null,
      'status': LocationShareStatus.active.name,
    });
    return ref.id;
  }

  @override
  Future<void> update(String shareId, SharedPosition position) =>
      _shares.doc(shareId).update({
        'current': {
          'lat': position.lat,
          'lng': position.lng,
          'accuracy': position.accuracy,
          'batteryPercent': position.batteryPercent,
          'updatedAt': FieldValue.serverTimestamp(),
        },
      });

  @override
  Future<void> stop(String shareId) => _shares.doc(shareId).update({
        'status': LocationShareStatus.ended.name,
        'endedAt': FieldValue.serverTimestamp(),
      });

  @override
  Stream<LocationShare?> watchMine(String ownerId) => _shares
      .where('ownerId', isEqualTo: ownerId)
      .where('status', isEqualTo: LocationShareStatus.active.name)
      .snapshots()
      .map((snap) => snap.docs.isEmpty ? null : _toShare(snap.docs.first));

  @override
  Stream<List<LocationShare>> watchSharedWithMe(String viewerId) => _shares
      .where('viewerIds', arrayContains: viewerId)
      .where('status', isEqualTo: LocationShareStatus.active.name)
      .snapshots()
      .map((snap) => snap.docs.map(_toShare).toList(growable: false));

  @override
  Stream<LocationShare?> watch(String shareId) => _shares
      .doc(shareId)
      .snapshots()
      .map((doc) => doc.exists ? _toShare(doc) : null);

  LocationShare _toShare(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    final current = d['current'];
    return LocationShare(
      id: doc.id,
      ownerId: d['ownerId'] as String? ?? '',
      ownerName: d['ownerName'] as String?,
      viewerIds: (d['viewerIds'] as List?)?.whereType<String>().toList() ??
          const [],
      status: LocationShareStatus.parse(d['status']),
      startedAt: _date(d['startedAt']),
      expiresAt: _date(d['expiresAt']) ?? _now(),
      current: current is Map
          ? SharedPosition(
              lat: _double(current['lat']),
              lng: _double(current['lng']),
              accuracy: _double(current['accuracy']),
              batteryPercent: _int(current['batteryPercent']),
              updatedAt: _date(current['updatedAt']),
            )
          : null,
    );
  }
}
