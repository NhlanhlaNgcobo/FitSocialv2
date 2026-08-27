import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/tracking/application/heart_rate_connection_controller.dart';
import 'package:fitsocial_app/features/tracking/data/ble_heart_rate_service.dart';
import 'package:fitsocial_app/features/tracking/data/heart_rate_device_store.dart';
import 'package:fitsocial_app/features/tracking/domain/heart_rate_models.dart';

void main() {
  late _FakeLink link;
  late _FakeStore store;
  late List<Duration> waits;

  /// Builds the controller with the backoff waits recorded rather than served,
  /// so a test can assert the schedule without sitting through it.
  HeartRateConnectionController build() {
    return HeartRateConnectionController(
      link: link,
      store: store,
      delay: (duration) async => waits.add(duration),
    );
  }

  setUp(() {
    link = _FakeLink();
    store = _FakeStore();
    waits = [];
  });

  tearDown(() => link.dispose());

  test('with nothing remembered it opens disconnected and reaches for nothing',
      () async {
    final controller = build();
    addTearDown(controller.dispose);
    await pumpEventQueue();

    expect(controller.state.status, HeartRateConnectionStatus.disconnected);
    expect(link.connectCalls, isEmpty);
  });

  test('a remembered strap is reached for by name before it is linked',
      () async {
    store.saved = const RememberedHeartRateDevice(
      remoteId: 'AA:BB',
      name: 'Polar H10',
    );

    final controller = build();
    addTearDown(controller.dispose);
    await pumpEventQueue();

    // Named while still reconnecting: the id alone cannot be shown, which is
    // why the store keeps the name next to it.
    expect(controller.state.status, HeartRateConnectionStatus.reconnecting);
    expect(controller.state.deviceName, 'Polar H10');
    expect(link.connectCalls.single.autoConnect, isTrue);

    link.reportConnected('AA:BB', true);
    await pumpEventQueue();

    expect(controller.state.status, HeartRateConnectionStatus.connected);
    expect(link.subscribeCalls, ['AA:BB']);
  });

  test('connecting to a picked strap remembers it', () async {
    final controller = build();
    addTearDown(controller.dispose);
    await pumpEventQueue();

    await controller.connect(
      const DiscoveredHeartRateDevice(
        remoteId: 'CC:DD',
        name: 'Wahoo TICKR',
        rssi: -55,
      ),
    );

    expect(controller.state.status, HeartRateConnectionStatus.connected);
    // The user is watching, so this attempt fails fast rather than waiting
    // indefinitely on the OS.
    expect(link.connectCalls.single.autoConnect, isFalse);
    expect(store.saved?.remoteId, 'CC:DD');
    expect(store.saved?.name, 'Wahoo TICKR');
  });

  // The behaviour this whole component exists for. A GATT notification
  // subscription does not survive a disconnect, so a strap that reconnects is
  // linked but silent until it is subscribed again — "reconnected but no
  // readings" is the failure this test forbids.
  test('a drop reconnects and subscribes again, not just relinks', () async {
    store.saved =
        const RememberedHeartRateDevice(remoteId: 'AA:BB', name: 'Polar H10');
    final controller = build();
    addTearDown(controller.dispose);
    await pumpEventQueue();

    link.reportConnected('AA:BB', true);
    await pumpEventQueue();
    expect(link.subscribeCalls, hasLength(1));

    // The strap goes out of range.
    link.reportConnected('AA:BB', false);
    await pumpEventQueue();
    expect(controller.state.status, HeartRateConnectionStatus.reconnecting);

    // And comes back.
    link.reportConnected('AA:BB', true);
    await pumpEventQueue();

    expect(controller.state.status, HeartRateConnectionStatus.connected);
    expect(link.subscribeCalls, hasLength(2));
  });

  test('a strap that never answers backs off on a bounded schedule', () async {
    store.saved =
        const RememberedHeartRateDevice(remoteId: 'AA:BB', name: 'Polar H10');
    link.failConnect = true;

    final controller = build();
    addTearDown(controller.dispose);
    await pumpEventQueue();

    expect(
      waits,
      const [
        Duration(seconds: 2),
        Duration(seconds: 4),
        Duration(seconds: 8),
        Duration(seconds: 16),
        Duration(seconds: 30),
      ],
    );
    // Bounded: it lands somewhere a person can act on rather than retrying all
    // afternoon with the radio awake.
    expect(controller.state.status, HeartRateConnectionStatus.failed);
    expect(controller.state.message, isNotNull);
  });

  test('an adapter that is off is waited on, not retried against', () async {
    store.saved =
        const RememberedHeartRateDevice(remoteId: 'AA:BB', name: 'Polar H10');
    link.failConnect = true;
    link.adapterInitiallyOn = false;

    final controller = build();
    addTearDown(controller.dispose);
    await pumpEventQueue();

    expect(controller.state.status, HeartRateConnectionStatus.adapterOff);
    expect(link.connectCalls, isEmpty);
    expect(waits, isEmpty);

    // Coming back arms exactly one attempt, not one per toggle.
    link.failConnect = false;
    link.reportAdapter(true);
    await pumpEventQueue();

    expect(link.connectCalls, hasLength(1));
  });

  test('forgetting a strap stops it being reached for again', () async {
    store.saved =
        const RememberedHeartRateDevice(remoteId: 'AA:BB', name: 'Polar H10');
    final controller = build();
    addTearDown(controller.dispose);
    await pumpEventQueue();

    link.reportConnected('AA:BB', true);
    await pumpEventQueue();

    await controller.forget();
    expect(store.saved, isNull);
    expect(controller.state.status, HeartRateConnectionStatus.disconnected);
    expect(controller.state.deviceName, isNull);

    final before = link.connectCalls.length;
    link.reportConnected('AA:BB', false);
    await pumpEventQueue();

    expect(link.connectCalls, hasLength(before));
  });

  test('a scan that finds nothing releases the button and says so', () async {
    final controller = build();
    addTearDown(controller.dispose);
    await pumpEventQueue();

    await controller.scan();
    expect(controller.state.status, HeartRateConnectionStatus.scanning);

    // The radio stops having found nothing — the case that used to leave the
    // button disabled and reading "Scanning" until the screen was closed.
    await link.endScan();
    await pumpEventQueue();

    expect(controller.state.status, HeartRateConnectionStatus.disconnected);
    expect(controller.state.message, isNotNull);
  });

  test('an unreadable store reads as nothing remembered', () async {
    store.throwOnRead = true;
    final controller = build();
    addTearDown(controller.dispose);
    await pumpEventQueue();

    expect(controller.state.status, HeartRateConnectionStatus.disconnected);
    // Still usable: the runner can just pair again.
    await controller.scan();
    expect(controller.state.status, HeartRateConnectionStatus.scanning);
  });
}

class _ConnectCall {
  _ConnectCall(this.remoteId, this.autoConnect);
  final String remoteId;
  final bool autoConnect;
}

class _FakeLink implements HeartRateLink {
  final _hr = StreamController<int>.broadcast();
  final _adapter = StreamController<bool>.broadcast();
  final _connected = <String, StreamController<bool>>{};
  StreamController<List<DiscoveredHeartRateDevice>>? _scan;

  final connectCalls = <_ConnectCall>[];
  final subscribeCalls = <String>[];
  bool failConnect = false;

  /// What the adapter reports before anything toggles it. A broadcast stream
  /// drops events sent before the controller subscribes, so "off at launch" has
  /// to be set up rather than pushed.
  bool adapterInitiallyOn = true;

  void reportAdapter(bool on) => _adapter.add(on);

  void reportConnected(String remoteId, bool connected) {
    _connected.putIfAbsent(remoteId, StreamController<bool>.broadcast).add(connected);
  }

  Future<void> endScan() async => _scan?.close();

  void dispose() {
    _hr.close();
    _adapter.close();
    for (final c in _connected.values) {
      c.close();
    }
  }

  @override
  Stream<int> get heartRateStream => _hr.stream;

  // Defaults to on, so a test that never mentions the adapter is not silently
  // testing the adapter-off path.
  @override
  Stream<bool> get adapterOn async* {
    yield adapterInitiallyOn;
    yield* _adapter.stream;
  }

  @override
  Stream<bool> connectedChanges(String remoteId) {
    return _connected
        .putIfAbsent(remoteId, StreamController<bool>.broadcast)
        .stream;
  }

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<bool> requestPermissions() async => true;

  @override
  Stream<List<DiscoveredHeartRateDevice>> scan({Duration? timeout}) {
    _scan = StreamController<List<DiscoveredHeartRateDevice>>();
    return _scan!.stream;
  }

  @override
  Future<void> stopScan() async {}

  @override
  Future<void> connectById(String remoteId, {bool autoConnect = false}) async {
    connectCalls.add(_ConnectCall(remoteId, autoConnect));
    if (failConnect) throw Exception('not found');
  }

  @override
  Future<void> subscribeNotifications(String remoteId) async {
    subscribeCalls.add(remoteId);
  }

  @override
  Future<void> disconnect() async {}
}

class _FakeStore implements HeartRateDeviceStore {
  RememberedHeartRateDevice? saved;
  bool throwOnRead = false;

  @override
  Future<RememberedHeartRateDevice?> read() async {
    // The real store swallows this and returns null; the fake throws so the
    // controller's own tolerance is what gets tested.
    if (throwOnRead) throw Exception('keystore unavailable');
    return saved;
  }

  @override
  Future<void> save(RememberedHeartRateDevice device) async => saved = device;

  @override
  Future<void> clear() async => saved = null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
