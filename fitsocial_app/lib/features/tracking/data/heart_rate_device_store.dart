import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/heart_rate_models.dart';

/// The strap this phone is paired with, remembered between launches.
///
/// Stored on the device rather than on the user's Firestore document, and that
/// is deliberate. A BLE remote id is local to this phone — on iOS it is a
/// CoreBluetooth UUID minted per app *installation* — so syncing it would push
/// an identifier to a second phone where it resolves to nothing, and every
/// launch there would open with a reconnect that cannot succeed. On Android it
/// is the strap's MAC, a stable hardware identifier for something worn on the
/// body, which has no business in a document the client can read.
///
/// The cost is that pairing does not follow the user to a new phone. That is
/// the right answer: pairing a strap is a per-phone act.
///
/// [FlutterSecureStorage] for the reason [ThemeModeStore] gives — it is the
/// key/value store this app already has on both platforms, not because a device
/// id is a secret.
class HeartRateDeviceStore {
  const HeartRateDeviceStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  static const _idKey = 'hr_device_remote_id';
  static const _nameKey = 'hr_device_name';

  final FlutterSecureStorage _storage;

  /// The remembered strap, or null when there is none.
  ///
  /// Never throws: a keystore entry invalidated by a restore or a lock-screen
  /// change reads as "nothing remembered", which lands the user on the scan
  /// button — the same place they started. Refusing to open the screen would be
  /// worse.
  Future<RememberedHeartRateDevice?> read() async {
    try {
      final id = await _storage.read(key: _idKey);
      if (id == null || id.isEmpty) return null;
      final name = await _storage.read(key: _nameKey);
      return RememberedHeartRateDevice(
        remoteId: id,
        name: (name == null || name.isEmpty) ? 'Heart-rate strap' : name,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> save(RememberedHeartRateDevice device) async {
    try {
      await _storage.write(key: _idKey, value: device.remoteId);
      await _storage.write(key: _nameKey, value: device.name);
    } catch (_) {
      // The strap still works for this session; it just won't be remembered.
    }
  }

  /// Best-effort erase, for "Forget device".
  ///
  /// A throw here would leave the user looking at a strap they just asked to
  /// forget with no way to try again. [read] already treats an unreadable entry
  /// as nothing remembered, so a failed delete lands in the same place.
  Future<void> clear() async {
    try {
      await _storage.delete(key: _idKey);
      await _storage.delete(key: _nameKey);
    } catch (_) {
      // Abandoning it either way.
    }
  }
}

final heartRateDeviceStoreProvider = Provider<HeartRateDeviceStore>((ref) {
  return const HeartRateDeviceStore();
});
