import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../domain/heart_rate_models.dart';

/// What the connection controller needs from a heart-rate strap.
///
/// Exists so the reconnect logic can be tested: `flutter_blue_plus` types
/// cannot be fabricated in a unit test, and this repo mocks by hand. Keeping
/// the interface plugin-free means [BleHeartRateService] stays the only file in
/// the app that imports the plugin, and a fake can stand in for all of it.
abstract class HeartRateLink {
  /// Live BPM. One stream for the life of the service, so a reconnect is
  /// invisible to whatever is reading it.
  Stream<int> get heartRateStream;

  /// Whether the Bluetooth adapter is on. Reconnecting while it is off is
  /// pointless, and retrying against it is how a retry loop becomes a storm.
  Stream<bool> get adapterOn;

  /// Whether [remoteId] is currently linked. Goes false on a drop, true again
  /// when the link is re-established — but a link is not the same as readings,
  /// which is why [subscribeNotifications] has to follow.
  Stream<bool> connectedChanges(String remoteId);

  Future<bool> isSupported();
  Future<bool> requestPermissions();

  Stream<List<DiscoveredHeartRateDevice>> scan({Duration timeout});
  Future<void> stopScan();

  /// Opens a link to [remoteId].
  ///
  /// With [autoConnect] the call returns before the link exists and the OS
  /// keeps trying indefinitely; without it, it waits and fails fast.
  Future<void> connectById(String remoteId, {bool autoConnect});

  /// Discovers services and subscribes to heart-rate notifications.
  ///
  /// Separate from connecting because a GATT subscription does not survive a
  /// disconnect: a strap that reconnects on its own is linked but silent until
  /// this runs again.
  Future<void> subscribeNotifications(String remoteId);

  Future<void> disconnect();

  void dispose();
}

/// Bluetooth LE integration for heart-rate wearables (chest straps and
/// smartwatches broadcasting the standard GATT Heart Rate service 0x180D).
class BleHeartRateService implements HeartRateLink {
  static final Guid _heartRateService = Guid('180d');
  static final Guid _heartRateMeasurement = Guid('2a37');

  final _hrController = StreamController<int>.broadcast();
  StreamSubscription<List<int>>? _valueSub;
  BluetoothDevice? _connected;

  @override
  Stream<int> get heartRateStream => _hrController.stream;

  @override
  Stream<bool> get adapterOn => FlutterBluePlus.adapterState
      .map((state) => state == BluetoothAdapterState.on)
      .distinct();

  @override
  Stream<bool> connectedChanges(String remoteId) {
    return BluetoothDevice.fromId(remoteId)
        .connectionState
        .map((state) => state == BluetoothConnectionState.connected)
        .distinct();
  }

  BluetoothDevice? get connectedDevice => _connected;

  /// Requests the Android 12+ Bluetooth runtime permissions.
  @override
  Future<bool> requestPermissions() async {
    final results = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();
    return results.values.every((s) => s.isGranted || s.isLimited);
  }

  @override
  Future<bool> isSupported() => FlutterBluePlus.isSupported;

  /// Scans for devices advertising the Heart Rate service, emitting the
  /// accumulated results as they are found and closing when the scan stops.
  ///
  /// Completion is driven by [FlutterBluePlus.isScanning] rather than by the
  /// result stream. A scan that times out having found nothing emits no
  /// results at all, so a loop waiting on `scanResults` for its exit signal
  /// waits forever — which is what used to leave the button stuck reading
  /// "Scanning" with no list and no message. The scanning flag always flips.
  @override
  Stream<List<DiscoveredHeartRateDevice>> scan({
    Duration timeout = const Duration(seconds: 10),
  }) {
    final found = <String, DiscoveredHeartRateDevice>{};
    final controller = StreamController<List<DiscoveredHeartRateDevice>>();
    StreamSubscription<List<ScanResult>>? resultsSub;
    StreamSubscription<bool>? scanningSub;

    Future<void> release() async {
      await resultsSub?.cancel();
      await scanningSub?.cancel();
      resultsSub = null;
      scanningSub = null;
    }

    Future<void> finish() async {
      await release();
      if (!controller.isClosed) await controller.close();
    }

    controller.onListen = () async {
      try {
        await FlutterBluePlus.startScan(
          withServices: [_heartRateService],
          timeout: timeout,
        );
      } catch (error, stack) {
        if (!controller.isClosed) controller.addError(error, stack);
        await finish();
        return;
      }

      // Subscribed only once the scan is up: both of these re-emit their
      // latest value on listen, and beforehand that value is "not scanning",
      // which would close the stream the moment anybody listened to it.
      if (!FlutterBluePlus.isScanningNow) {
        await finish();
        return;
      }

      scanningSub =
          FlutterBluePlus.isScanning.where((scanning) => !scanning).listen(
                (_) => finish(),
              );

      resultsSub = FlutterBluePlus.onScanResults.listen(
        (results) {
          for (final result in results) {
            final name = result.device.platformName;
            found[result.device.remoteId.str] = DiscoveredHeartRateDevice(
              remoteId: result.device.remoteId.str,
              name: name.isEmpty ? 'Unknown device' : name,
              rssi: result.rssi,
            );
          }
          if (controller.isClosed) return;
          controller.add(
            found.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi)),
          );
        },
        onError: (Object error, StackTrace stack) {
          if (!controller.isClosed) controller.addError(error, stack);
          finish();
        },
      );
    };

    // Backing out of the screen cancels the subscription, and without this the
    // radio kept scanning until its own timeout fired.
    controller.onCancel = () async {
      await release();
      await stopScan();
    };

    return controller.stream;
  }

  @override
  Future<void> stopScan() => FlutterBluePlus.stopScan();

  @override
  Future<void> connectById(String remoteId, {bool autoConnect = false}) async {
    final device = BluetoothDevice.fromId(remoteId);
    _connected = device;
    // mtu must be null alongside autoConnect - the plugin asserts on it. No
    // loss here: a heart-rate notification is three bytes and fits inside the
    // default 23-byte MTU with room to spare.
    await device.connect(
      timeout: const Duration(seconds: 15),
      autoConnect: autoConnect,
      mtu: autoConnect ? null : 512,
    );
  }

  @override
  Future<void> subscribeNotifications(String remoteId) async {
    final device = BluetoothDevice.fromId(remoteId);
    _connected = device;
    await _valueSub?.cancel();
    _valueSub = null;

    final services = await device.discoverServices();
    for (final service in services) {
      if (service.uuid != _heartRateService) continue;
      for (final characteristic in service.characteristics) {
        if (characteristic.uuid != _heartRateMeasurement) continue;
        await characteristic.setNotifyValue(true);
        _valueSub = characteristic.onValueReceived.listen((data) {
          final bpm = _parseHeartRate(data);
          if (bpm > 0 && !_hrController.isClosed) _hrController.add(bpm);
        });
        return;
      }
    }

    // The link is already open by this point, so throwing straight out of here
    // left a connected device with nothing listening to it, and the next
    // attempt had to fight that stale link.
    await disconnect();
    throw Exception('This device does not expose heart-rate measurements.');
  }

  @override
  Future<void> disconnect() async {
    await _valueSub?.cancel();
    _valueSub = null;
    if (_connected != null) {
      try {
        // Also drops the device from the plugin's auto-connect set, which is
        // exactly what "forget this strap" has to mean.
        await _connected!.disconnect();
      } catch (_) {}
      _connected = null;
    }
  }

  /// Parses the GATT Heart Rate Measurement characteristic payload.
  int _parseHeartRate(List<int> data) {
    if (data.isEmpty) return 0;
    final flags = data[0];
    final is16bit = flags & 0x01 == 0x01;
    if (is16bit) {
      if (data.length < 3) return 0;
      return data[1] | (data[2] << 8);
    }
    if (data.length < 2) return 0;
    return data[1];
  }

  @override
  void dispose() {
    disconnect();
    _hrController.close();
  }
}
