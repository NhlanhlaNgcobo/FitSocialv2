import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../domain/safety_models.dart';

/// Where the phone is, for a panic event.
///
/// Neither method asks for permission. Panic is not the moment for a system
/// dialog; permission is requested when safety is set up, and if it was
/// refused the alert goes without coordinates.
abstract class PanicLocator {
  /// A fresh fix. The controller caps how long it waits.
  Future<PanicPosition?> current();

  /// The OS's cached fix, however old.
  Future<PanicPosition?> lastKnown();

  /// A continuous stream of fixes that keeps running with the screen locked
  /// and the app in the background, for as long as it is listened to.
  ///
  /// Must be started while the app is in the foreground — which a panic
  /// always is. Started that way, "while using the app" permission is enough
  /// on both platforms: Android keeps it alive as a foreground service with a
  /// visible notification, iOS through the location background mode with its
  /// blue indicator. Neither needs "Always" permission.
  Stream<PanicPosition> track();
}

class GeolocatorPanicLocator implements PanicLocator {
  const GeolocatorPanicLocator();

  Future<bool> _allowed() async {
    final permission = await Geolocator.checkPermission();
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  @override
  Future<PanicPosition?> current() async {
    if (!await _allowed()) return null;
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
    return PanicPosition(lat: p.latitude, lng: p.longitude, accuracy: p.accuracy);
  }

  @override
  Stream<PanicPosition> track() {
    return Geolocator.getPositionStream(locationSettings: _trackingSettings())
        .map((p) => PanicPosition(
              lat: p.latitude,
              lng: p.longitude,
              accuracy: p.accuracy,
            ));
  }

  LocationSettings _trackingSettings() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 0,
          intervalDuration: const Duration(seconds: 15),
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            // Android will not run background location without a visible
            // notification, and no app can hide it. Worded neutrally on
            // purpose: someone who has taken the phone should not read
            // "sending your location to your contacts" on the lock screen.
            notificationTitle: 'FitSocial',
            notificationText: 'Location in use',
            notificationChannelName: 'Location in use',
            enableWakeLock: true,
            setOngoing: true,
          ),
        );
      case TargetPlatform.iOS:
        return AppleSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 0,
          allowBackgroundLocationUpdates: true,
          pauseLocationUpdatesAutomatically: false,
          showBackgroundLocationIndicator: true,
        );
      default:
        return const LocationSettings(accuracy: LocationAccuracy.high);
    }
  }

  @override
  Future<PanicPosition?> lastKnown() async {
    if (!await _allowed()) return null;
    final p = await Geolocator.getLastKnownPosition();
    if (p == null) return null;
    return PanicPosition(
      lat: p.latitude,
      lng: p.longitude,
      accuracy: p.accuracy,
      isLastKnown: true,
    );
  }
}
