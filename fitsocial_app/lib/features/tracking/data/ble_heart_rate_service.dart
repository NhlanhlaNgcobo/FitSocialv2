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

  /// Scans for devices advertising the Heart Rate service.
  /// Emits the accumulated result list as devices are found.
  Stream<List<HeartRateDevice>> scan(
      {Duration timeout = const Duration(seconds: 10)}) async* {
    final found = <String, HeartRateDevice>{};
    await FlutterBluePlus.startScan(
      withServices: [_heartRateService],
      timeout: timeout,
    );
    await for (final results in FlutterBluePlus.scanResults) {
      for (final r in results) {
        found[r.device.remoteId.str] =
            HeartRateDevice(device: r.device, rssi: r.rssi);
      }
      yield found.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi));
      if (!FlutterBluePlus.isScanningNow) break;
    }
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
