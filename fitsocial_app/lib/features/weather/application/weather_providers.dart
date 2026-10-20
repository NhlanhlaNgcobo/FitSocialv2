import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../data/weather_service.dart';
import '../domain/weather.dart';

final weatherServiceProvider = Provider<WeatherService>((ref) {
  final service = WeatherService();
  ref.onDispose(service.dispose);
  return service;
});

/// Why the weather card has nothing to show, when it has nothing to show.
enum WeatherBlocker {
  /// Location is off at the OS level. Only the user can fix this.
  serviceDisabled,

  /// Not granted yet, and askable — the card offers a button.
  permissionDenied,

  /// Denied permanently. Asking again does nothing; it has to be Settings.
  permissionDeniedForever,
}

class WeatherLocationException implements Exception {
  const WeatherLocationException(this.blocker);

  final WeatherBlocker blocker;

  String get message => switch (blocker) {
        WeatherBlocker.serviceDisabled =>
          'Turn on location services to see conditions.',
        WeatherBlocker.permissionDenied =>
          'Allow location access to see local conditions.',
        WeatherBlocker.permissionDeniedForever =>
          'Location is blocked for FitSocial. Enable it in Settings to see '
              'conditions.',
      };

  @override
  String toString() => message;
}

/// Current conditions where the user is.
///
/// Deliberately does *not* prompt for location on its own. This sits on a tab
/// the user opened to look at their training, and a permission dialog they did
/// not ask for is the fastest way to get a permanent denial — which would then
/// block run tracking too, where location is not optional. The card shows a
/// button instead, and [requestWeatherLocation] is what asks.
///
/// Kept fresh on its own. The provider lives as long as the app, so a reading
/// taken at launch used to be what the card showed all day: open at 07:00,
/// look again at 14:00, and it was still the morning's temperature. Now a
/// reading older than [weatherStaleAfter] is replaced when the app comes back
/// to the foreground, and on a timer while it stays there. A failed reading
/// is retried on every return — that is also how coming back from turning
/// location on in Settings shows the weather without a tap.
///
/// The timer never fetches in the background: a location fix there needs a
/// permission this feature does not ask for, and would fail into the error
/// state. A tick that lands while the app is away is left to the resume.
///
/// While a refresh is in flight, and after one fails, the provider keeps the
/// last reading as its value — the screens show it with a note rather than
/// dropping back to a skeleton or an error.
final weatherProvider = FutureProvider<WeatherSnapshot>((ref) async {
  DateTime? fetchedAt;
  var failed = false;
  Timer? timer;

  bool isStale() =>
      fetchedAt != null &&
      DateTime.now().difference(fetchedAt) >= weatherStaleAfter;

  final lifecycle = AppLifecycleListener(
    onResume: () {
      if (failed || isStale()) ref.invalidateSelf();
    },
  );
  ref.onDispose(() {
    lifecycle.dispose();
    timer?.cancel();
  });

  try {
    final snapshot = await _readWeather(ref);
    fetchedAt = snapshot.updatedAt;
    timer = Timer(weatherStaleAfter, () {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        ref.invalidateSelf();
      }
    });
    return snapshot;
  } catch (_) {
    failed = true;
    rethrow;
  }
});

/// How old a reading may get before it is fetched again. Open-Meteo's current
/// conditions move in fifteen-minute steps; half an hour keeps the card honest
/// without a request every time the app is opened.
const Duration weatherStaleAfter = Duration(minutes: 30);

Future<WeatherSnapshot> _readWeather(Ref ref) async {
  final serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    throw const WeatherLocationException(WeatherBlocker.serviceDisabled);
  }

  final permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.deniedForever) {
    throw const WeatherLocationException(
      WeatherBlocker.permissionDeniedForever,
    );
  }
  if (permission == LocationPermission.denied) {
    throw const WeatherLocationException(WeatherBlocker.permissionDenied);
  }

  // Low accuracy on purpose: weather is a regional fact, and a coarse fix is
  // both faster and a smaller ask than pinpointing the user's street.
  final position = await Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.low,
      timeLimit: Duration(seconds: 15),
    ),
  );

  return ref
      .read(weatherServiceProvider)
      .fetch(latitude: position.latitude, longitude: position.longitude);
}

/// Asks for location, then re-runs [weatherProvider].
///
/// Returns whether permission ended up granted, so the caller can leave the
/// prompt in place rather than flashing a spinner that resolves to the same
/// message.
Future<bool> requestWeatherLocation(WidgetRef ref) async {
  final permission = await Geolocator.requestPermission();
  final granted = permission == LocationPermission.always ||
      permission == LocationPermission.whileInUse;

  if (granted) {
    ref.invalidate(weatherProvider);
  }
  return granted;
}
