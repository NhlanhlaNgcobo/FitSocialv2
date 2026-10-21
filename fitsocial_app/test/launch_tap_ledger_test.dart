import 'package:fitsocial_app/features/notifications/data/launch_tap_ledger.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('a tap is followed once, and its replay from Recents is not', () async {
    final ledger = LaunchTapLedger();

    expect(await ledger.firstTime('msg-morning-meal'), isTrue);
    // The same intent handed back on every later cold start.
    expect(await ledger.firstTime('msg-morning-meal'), isFalse);
    expect(await ledger.firstTime('msg-morning-meal'), isFalse);
  });

  test('a new notification is followed after an old one', () async {
    final ledger = LaunchTapLedger();

    expect(await ledger.firstTime('msg-1'), isTrue);
    expect(await ledger.firstTime('msg-2'), isTrue);
  });

  test('a push without an id is named by when it was sent and where it goes',
      () {
    final sent = DateTime.utc(2026, 10, 21, 7, 30);
    expect(
      LaunchTapLedger.keyFor(messageId: 'abc', sentTime: sent, route: '/x'),
      'abc',
    );
    expect(
      LaunchTapLedger.keyFor(messageId: null, sentTime: sent, route: '/post/1'),
      '${sent.millisecondsSinceEpoch}|/post/1',
    );
  });
}
