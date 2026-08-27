import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

/// A nearby BLE device advertising the standard Heart Rate service.
class HeartRateDevice {
  const HeartRateDevice({required this.device, required this.rssi});

  final BluetoothDevice device;
  final int rssi;

  String get name =>
      device.platformName.isEmpty ? 'Unknown device' : device.platformName;
  String get id => device.remoteId.str;
}

/// Bluetooth LE integration for heart-rate wearables (chest straps and
/// smartwatches broadcasting the standard GATT Heart Rate service 0x180D).
class BleHeartRateService {
  static final Guid _heartRateService = Guid('180d');
  static final Guid _heartRateMeasurement = Guid('2a37');

  final _hrController = StreamController<int>.broadcast();
  StreamSubscription<List<int>>? _valueSub;
  BluetoothDevice? _connected;

  /// Live heart-rate readings (BPM) from the connected device.
  Stream<int> get heartRateStream => _hrController.stream;

  BluetoothDevice? get connectedDevice => _connected;

  /// Requests the Android 12+ Bluetooth runtime permissions.
  Future<bool> requestPermissions() async {
    final results = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();
    return results.values.every((s) => s.isGranted || s.isLimited);
  }

  Future<bool> isSupported() => FlutterBluePlus.isSupported;

  /// Scans for devices advertising the Heart Rate service, emitting the
  /// accumulated results as they are found and closing when the scan stops.
  ///
  /// Completion is driven by [FlutterBluePlus.isScanning] rather than by the
  /// result stream. A scan that times out having found nothing emits no
  /// results at all — so a loop waiting on `scanResults` for its exit signal
  /// waits forever, which is what used to leave the button stuck on
  /// "Scanning…" with no list and no message. The scanning flag always flips.
  Stream<List<HeartRateDevice>> scan({
    Duration timeout = const Duration(seconds: 10),
  }) {
    final found = <String, HeartRateDevice>{};
    final controller = StreamController<List<HeartRateDevice>>();
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
            found[result.device.remoteId.str] =
                HeartRateDevice(device: result.device, rssi: result.rssi);
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

  Future<void> stopScan() => FlutterBluePlus.stopScan();

  /// Connects and subscribes to Heart Rate Measurement notifications.
  Future<void> connect(BluetoothDevice device) async {
    await disconnect();
    await device.connect(timeout: const Duration(seconds: 15));
    _connected = device;

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
    // left a connected device with nothing listening to it — and the next
    // connect attempt had to fight that stale link.
    await disconnect();
    throw Exception('This device does not expose heart-rate measurements.');
  }

  Future<void> disconnect() async {
    await _valueSub?.cancel();
    _valueSub = null;
    if (_connected != null) {
      try {
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

  void dispose() {
    disconnect();
    _hrController.close();
  }
}
