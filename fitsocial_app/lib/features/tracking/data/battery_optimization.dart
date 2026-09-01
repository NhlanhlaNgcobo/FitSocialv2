import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// Android's battery-optimisation exemption — the one lever left when the
/// phone is delivering location too slowly to record a run.
///
/// The live-run position stream already asks for everything Dart can ask
/// for: PRIORITY_HIGH_ACCURACY at 1 Hz with no distance filter, a location
/// foreground service, and a partial wake lock. None of it overrides the
/// throttle Android applies to an app it has decided is battery-optimised, so
/// once RunFixStats reports a starved stream there is nothing left to tune in
/// this codebase — only a setting to change, several screens into Settings,
/// that nobody finds by being told about it in a banner.
///
/// On Samsung this exemption is exactly what App info → Battery calls
/// "Unrestricted"; One UI maps its Restricted / Optimised / Unrestricted
/// control onto the standard doze allowlist.
class BatteryOptimization {
  const BatteryOptimization();

  /// Whether the app is already exempt.
  ///
  /// True on every platform that has no such notion, so a caller can read this
  /// as "is there a setting worth offering" without testing the platform
  /// itself — and so the offer never appears on iOS, where it would be a lie.
  Future<bool> isExempt() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return true;
    try {
      return await Permission.ignoreBatteryOptimizations.isGranted;
    } on Exception {
      // No channel on the other end — a widget test, or a platform the plugin
      // has not registered on. "Exempt" is the safe answer either way: the
      // caller's only use for a false is to accuse the runner of a setting,
      // and it should not do that on a reading it never got.
      return true;
    }
  }

  /// Puts the exemption one tap away, and reports where that left things.
  ///
  /// Two routes, and today only the second one runs. The system Allow dialog
  /// needs REQUEST_IGNORE_BATTERY_OPTIMIZATIONS declared in the manifest, and
  /// this app deliberately does not declare it: Play treats it as a restricted
  /// permission, and the review it costs is not worth one saved tap. Without
  /// the declaration permission_handler resolves to `denied` and shows
  /// nothing, so every runner lands on the fallback — the app's own settings
  /// page, from which Battery is one tap and Unrestricted is two.
  ///
  /// The request is still attempted rather than skipped, so restoring that one
  /// manifest line is the whole change if the tap is ever judged worth it.
  ///
  /// The fallback cannot report an outcome: [openAppSettings] returns as soon
  /// as the screen is launched, long before the runner has touched anything.
  /// A false here therefore means "not exempt yet", not "refused" — the caller
  /// re-reads [isExempt] when the app comes back to the foreground.
  Future<bool> requestExemption() async {
    if (await isExempt()) return true;
    await Permission.ignoreBatteryOptimizations.request();
    if (await isExempt()) return true;
    await openAppSettings();
    return false;
  }
}
