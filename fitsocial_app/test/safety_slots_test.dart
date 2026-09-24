import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/safety/domain/safety_models.dart';

SafetyContact _app(String uid, SafetyContactStatus status) => SafetyContact(
      uid: uid,
      status: status,
      displayName: uid,
      handle: uid,
    );

EmailSafetyContact _email(String id, EmailContactStatus status) =>
    EmailSafetyContact(id: id, name: id, email: '$id@example.com', status: status);

void main() {
  test('three slots are shared by FitSocial and email contacts', () {
    expect(maxAcceptedSafetyContacts, 3);
    final used = usedSafetySlots(
      [
        _app('a', SafetyContactStatus.accepted),
        _app('b', SafetyContactStatus.pending),
      ],
      [_email('mom', EmailContactStatus.confirmed)],
    );
    expect(used, 3);
  });

  test('declined, revoked and removed contacts free their slot', () {
    final used = usedSafetySlots(
      [
        _app('a', SafetyContactStatus.declined),
        _app('b', SafetyContactStatus.revoked),
      ],
      [
        _email('x', EmailContactStatus.declined),
        _email('y', EmailContactStatus.removed),
        _email('z', EmailContactStatus.pending),
      ],
    );
    expect(used, 1);
  });

  test('an unknown email status never counts as confirmed', () {
    expect(EmailContactStatus.parse('weird'), EmailContactStatus.removed);
    expect(
      _email('x', EmailContactStatus.parse('confirmed')).isConfirmed,
      isTrue,
    );
  });
}
