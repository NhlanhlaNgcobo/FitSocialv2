import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/ble_heart_rate_service.dart';
import '../data/heart_rate_device_store.dart';
import '../domain/heart_rate_models.dart';
import 'tracking_providers.dart';

/// Owns pairing, remembering and reconnecting a heart-rate strap.
///
/// Everything the strap UI used to hold as loose booleans on one screen lives
/// here instead, which is the point: those booleans were private to the Health
/// screen, so the run screens had no way to know a strap had dropped and went
/// on displaying the last reading as though it were live.
class HeartRateConnectionController
    extends StateNotifier<HeartRateConnectionState> {
  HeartRateConnectionController({
    required HeartRateLink link,
    required HeartRateDeviceStore store,
    Future<void> Function(Duration)? delay,
  })  : _link = link,
        _store = store,
        // Injected alongside the usual clock seam because a clock alone cannot
        // make a test skip a thirty-second wait, and an untestable backoff is
        // how reconnect storms ship.
        _delay = delay ?? Future<void>.delayed,
        super(const HeartRateConnectionState()) {
    _watchAdapter();
    unawaited(_restore());
  }

  /// Waits between reconnect attempts, then gives up. Bounded on purpose: a
  /// strap left in a drawer should not keep the radio busy all afternoon, and
  /// somebody who wants another go can ask for one.
  static const _backoff = <Duration>[
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 16),
    Duration(seconds: 30),
  ];

  final HeartRateLink _link;
  final HeartRateDeviceStore _store;
  final Future<void> Function(Duration) _delay;

  StreamSubscription<bool>? _adapterSub;
  StreamSubscription<bool>? _connectionSub;
  StreamSubscription<List<DiscoveredHeartRateDevice>>? _scanSub;

  bool _adapterOn = true;
  bool _forgotten = false;
  bool _attemptInFlight = false;

  /// Reconnects the remembered strap, if there is one.
  ///
  /// Idempotent and safe to call from every screen that shows a heart rate —
  /// which is how it gets called at all. Restoring from app start instead would
  /// wake a chest strap's radio because somebody opened the feed.
  Future<void> restoreIfRemembered() async {
    if (state.remoteId != null || _attemptInFlight) return;
    await _restore();
  }

  Future<void> _restore() async {
    RememberedHeartRateDevice? remembered;
    try {
      remembered = await _store.read();
    } catch (_) {
      // Nothing remembered, as far as this session is concerned. The store
      // guards this too, but restore runs unawaited from the constructor and a
      // throw here would surface as an unhandled async error rather than as a
      // screen asking the runner to pair again.
      return;
    }
    if (!mounted || remembered == null) return;
    _forgotten = false;
    state = state.copyWith(
      status: HeartRateConnectionStatus.reconnecting,
      deviceName: remembered.name,
      remoteId: remembered.remoteId,
      clearMessage: true,
    );
    _watchConnection(remembered.remoteId);
    await _attemptReconnect(remembered.remoteId);
  }

  /// Looks for nearby straps.
  Future<void> scan() async {
    if (!await _link.isSupported()) {
      if (!mounted) return;
      state = state.copyWith(
        status: HeartRateConnectionStatus.failed,
        message: 'Bluetooth LE is not available on this device.',
      );
      return;
    }
    if (!await _link.requestPermissions()) {
      if (!mounted) return;
      state = state.copyWith(
        status: HeartRateConnectionStatus.failed,
        message: 'Bluetooth permission was denied.',
      );
      return;
    }
    if (!mounted) return;

    state = state.copyWith(
      status: HeartRateConnectionStatus.scanning,
      discovered: const [],
      clearMessage: true,
    );

    await _scanSub?.cancel();
    _scanSub = _link.scan(timeout: const Duration(seconds: 10)).listen(
      (devices) {
        if (!mounted) return;
        state = state.copyWith(discovered: devices);
      },
      onError: (Object error) {
        if (!mounted) return;
        state = state.copyWith(
          status: HeartRateConnectionStatus.failed,
          message: 'Scan failed: $error',
        );
      },
      // The scan stream closes when the radio stops, including on a timeout
      // that found nothing — so this always runs, and the button always comes
      // back.
      onDone: () {
        if (!mounted) return;
        if (state.status != HeartRateConnectionStatus.scanning) return;
        state = state.copyWith(
          status: HeartRateConnectionStatus.disconnected,
          message: state.discovered.isEmpty
              ? 'No heart-rate monitors found. Check yours is on and worn.'
              : null,
        );
      },
    );
  }

  /// Connects to a strap the user picked, and remembers it.
  Future<void> connect(DiscoveredHeartRateDevice device) async {
    _forgotten = false;
    await _scanSub?.cancel();
    _scanSub = null;
    await _link.stopScan();
    if (!mounted) return;

    state = state.copyWith(
      status: HeartRateConnectionStatus.connecting,
      deviceName: device.name,
      remoteId: device.remoteId,
      clearMessage: true,
    );

    try {
      // Not autoConnect: the user is watching, so a fast failure they can act
      // on beats an attempt that waits indefinitely without saying so.
      await _link.connectById(device.remoteId, autoConnect: false);
      if (!mounted) return;
      await _link.subscribeNotifications(device.remoteId);
      if (!mounted) return;
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(
        status: HeartRateConnectionStatus.failed,
        message: 'Could not connect: $error',
      );
      return;
    }

    await _store.save(
      RememberedHeartRateDevice(remoteId: device.remoteId, name: device.name),
    );
    if (!mounted) return;
    _watchConnection(device.remoteId);
    state = state.copyWith(
      status: HeartRateConnectionStatus.connected,
      attempt: 0,
      clearMessage: true,
    );
  }

  /// Drops the strap and stops remembering it.
  Future<void> forget() async {
    _forgotten = true;
    await _connectionSub?.cancel();
    _connectionSub = null;
    await _scanSub?.cancel();
    _scanSub = null;
    await _link.disconnect();
    await _store.clear();
    if (!mounted) return;
    state = const HeartRateConnectionState();
  }

  /// Another go after the automatic attempts were spent.
  Future<void> retry() async {
    final remoteId = state.remoteId;
    if (remoteId == null) return;
    state = state.copyWith(attempt: 0, clearMessage: true);
    await _attemptReconnect(remoteId);
  }

  void _watchAdapter() {
    _adapterSub = _link.adapterOn.listen((on) {
      _adapterOn = on;
      if (!mounted) return;
      if (!on) {
        // Not a failure and not retried. There is nothing to retry against
        // until the adapter is back, and retrying anyway is exactly how a
        // reconnect loop turns into a storm.
        if (state.remoteId == null) return;
        state = state.copyWith(
          status: HeartRateConnectionStatus.adapterOff,
          message: 'Bluetooth is off.',
        );
        return;
      }
      // Back on: one attempt, not a fresh loop per toggle.
      if (state.status == HeartRateConnectionStatus.adapterOff) {
        final remoteId = state.remoteId;
        if (remoteId != null) {
          state = state.copyWith(attempt: 0, clearMessage: true);
          unawaited(_attemptReconnect(remoteId));
        }
      }
    });
  }

  void _watchConnection(String remoteId) {
    _connectionSub?.cancel();
    _connectionSub = _link.connectedChanges(remoteId).listen((connected) async {
      if (!mounted || _forgotten) return;
      if (connected) {
        // A link is not readings. GATT notification subscriptions do not
        // survive a disconnect, so a strap that reconnected on its own is
        // silent until this runs again — the difference between "reconnects"
        // and "reconnects and works".
        if (state.status == HeartRateConnectionStatus.connected) return;
        try {
          await _link.subscribeNotifications(remoteId);
        } catch (error) {
          if (!mounted) return;
          state = state.copyWith(
            status: HeartRateConnectionStatus.failed,
            message: 'Reconnected but could not read heart rate: $error',
          );
          return;
        }
        if (!mounted) return;
        state = state.copyWith(
          status: HeartRateConnectionStatus.connected,
          attempt: 0,
          clearMessage: true,
        );
        return;
      }

      if (state.status == HeartRateConnectionStatus.disconnected) return;
      state = state.copyWith(status: HeartRateConnectionStatus.reconnecting);
      unawaited(_attemptReconnect(remoteId));
    });
  }

  Future<void> _attemptReconnect(String remoteId) async {
    // One attempt at a time. The plugin serialises its own work, but queuing
    // behind it would let every drop stack another loop on top of the last.
    if (_attemptInFlight || _forgotten) return;
    _attemptInFlight = true;
    try {
      for (var attempt = 0; attempt < _backoff.length; attempt++) {
        if (!mounted || _forgotten) return;
        if (!_adapterOn) {
          state = state.copyWith(
            status: HeartRateConnectionStatus.adapterOff,
            message: 'Bluetooth is off.',
          );
          return;
        }

        state = state.copyWith(
          status: HeartRateConnectionStatus.reconnecting,
          attempt: attempt + 1,
        );

        try {
          // autoConnect hands the retrying to the OS, which does it on a
          // battery-friendly schedule and survives walking out of range and
          // back. It returns before the link exists, so the connection watcher
          // above is what actually reports success.
          await _link.connectById(remoteId, autoConnect: true);
          return;
        } catch (_) {
          // Fall through to the wait and try again.
        }

        await _delay(_backoff[attempt]);
      }

      if (!mounted || _forgotten) return;
      state = state.copyWith(
        status: HeartRateConnectionStatus.failed,
        message: 'Could not reach your heart-rate monitor. Check it is on and worn.',
      );
    } finally {
      _attemptInFlight = false;
    }
  }

  @override
  void dispose() {
    _adapterSub?.cancel();
    _connectionSub?.cancel();
    _scanSub?.cancel();
    super.dispose();
  }
}

/// Not autoDispose: the strap outlives the screen that paired it, and dropping
/// the link on the way back to the feed would mean reconnecting for every run.
final heartRateConnectionProvider = StateNotifierProvider<
    HeartRateConnectionController, HeartRateConnectionState>((ref) {
  return HeartRateConnectionController(
    link: ref.watch(bleHeartRateServiceProvider),
    store: ref.watch(heartRateDeviceStoreProvider),
  );
});
