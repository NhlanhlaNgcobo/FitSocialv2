/// Heart-rate strap models, free of any `flutter_blue_plus` types.
///
/// The first `domain/` in this feature, and the reason is testability rather
/// than symmetry: connection state has to be constructible in a test, this repo
/// fakes everything by hand, and there is no way to fabricate a
/// `BluetoothDevice`. A state class cannot stay plugin-free while it lives
/// beside the plugin import in `data/`.
library;

/// Where the strap connection stands.
enum HeartRateConnectionStatus {
  /// No strap, and none being sought.
  disconnected,

  scanning,

  /// A connection the user just asked for.
  connecting,

  /// Connected *and* subscribed — readings are arriving.
  connected,

  /// A remembered strap being reached for, or a dropped one being recovered.
  /// Distinct from [connecting] because the user did not ask for it and should
  /// not be blamed for it taking a while.
  reconnecting,

  /// Bluetooth is off. Not a failure and not retried — there is nothing to
  /// retry against until the adapter comes back.
  adapterOff,

  /// Given up on. Carries a message and waits to be asked again.
  failed,
}

/// A strap seen in a scan.
class DiscoveredHeartRateDevice {
  const DiscoveredHeartRateDevice({
    required this.remoteId,
    required this.name,
    required this.rssi,
  });

  final String remoteId;
  final String name;

  /// Signal strength, negative dBm — closer to zero is nearer.
  final int rssi;
}

/// The strap this phone has been paired with, as it survives a relaunch.
///
/// The name is stored next to the id because the id alone cannot be shown: a
/// device not seen since boot has no platform name to read, and "Reconnecting
/// to…" has to say something.
class RememberedHeartRateDevice {
  const RememberedHeartRateDevice({required this.remoteId, required this.name});

  final String remoteId;
  final String name;
}

/// Everything the strap UI needs, in one value.
class HeartRateConnectionState {
  const HeartRateConnectionState({
    this.status = HeartRateConnectionStatus.disconnected,
    this.deviceName,
    this.remoteId,
    this.discovered = const [],
    this.message,
    this.attempt = 0,
  });

  final HeartRateConnectionStatus status;

  /// The strap being connected, reconnected to, or connected — whichever is
  /// current. Available before the link is, so a reconnect can be named.
  final String? deviceName;
  final String? remoteId;

  final List<DiscoveredHeartRateDevice> discovered;

  /// What went wrong, in words a runner can act on. Carried on the state rather
  /// than thrown, because the thing that fails is rarely the thing the user
  /// just tapped.
  final String? message;

  /// How many automatic reconnects have been spent on the current drop.
  final int attempt;

  bool get isBusy =>
      status == HeartRateConnectionStatus.scanning ||
      status == HeartRateConnectionStatus.connecting ||
      status == HeartRateConnectionStatus.reconnecting;

  /// True only when readings are actually arriving — a connected link that has
  /// not re-subscribed yet is not live, and the BPM on screen would be stale.
  bool get isLive => status == HeartRateConnectionStatus.connected;

  HeartRateConnectionState copyWith({
    HeartRateConnectionStatus? status,
    String? deviceName,
    String? remoteId,
    List<DiscoveredHeartRateDevice>? discovered,
    String? message,
    int? attempt,
    bool clearMessage = false,
    bool clearDevice = false,
  }) {
    return HeartRateConnectionState(
      status: status ?? this.status,
      deviceName: clearDevice ? null : (deviceName ?? this.deviceName),
      remoteId: clearDevice ? null : (remoteId ?? this.remoteId),
      discovered: discovered ?? this.discovered,
      message: clearMessage ? null : (message ?? this.message),
      attempt: attempt ?? this.attempt,
    );
  }
}
