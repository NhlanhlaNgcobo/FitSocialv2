import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The one `flutter_local_notifications` instance, initialised once.
///
/// More than one feature posts local notifications — the rest timer, the
/// workout left running in the background — and the plugin keeps a single tap
/// callback: whichever feature called `initialize` last would silently own
/// every tap. So nobody calls `initialize` but this, and a notification says
/// where its tap goes by carrying an in-app route as its payload.
class LocalNotificationsHub {
  LocalNotificationsHub({FlutterLocalNotificationsPlugin? plugin})
      : plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin plugin;

  /// Routes a local notification may open. Written by this app, but checked
  /// all the same — the day a payload arrives from anywhere else is not the
  /// day to find out anything at all could be navigated to.
  static const routes = {'/workout-session', '/log-workout'};

  final _taps = StreamController<String>.broadcast();

  /// Routes from notifications tapped while the app was running.
  Stream<String> get taps => _taps.stream;

  Future<bool>? _ready;
  bool _askedPermission = false;

  AndroidFlutterLocalNotificationsPlugin? get android =>
      plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  IOSFlutterLocalNotificationsPlugin? get ios =>
      plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();

  /// Initialises the plugin on first call. False where notifications cannot
  /// be posted at all. Never throws.
  Future<bool> ready() => _ready ??= () async {
        try {
          await plugin.initialize(
            settings: const InitializationSettings(
              android: AndroidInitializationSettings('ic_stat_fitsocial'),
              iOS: DarwinInitializationSettings(
                // Asked for at a moment that explains itself, not at start-up.
                requestAlertPermission: false,
                requestBadgePermission: false,
                requestSoundPermission: false,
              ),
            ),
            onDidReceiveNotificationResponse: (response) {
              final route = _validRoute(response.payload);
              if (route != null) _taps.add(route);
            },
          );
          return true;
        } catch (error) {
          debugPrint('Local notifications unavailable: $error');
          return false;
        }
      }();

  /// The route of the notification that launched the app, when one did.
  Future<String?> launchRoute() async {
    if (!await ready()) return null;
    try {
      final details = await plugin.getNotificationAppLaunchDetails();
      if (details == null || !details.didNotificationLaunchApp) return null;
      return _validRoute(details.notificationResponse?.payload);
    } catch (error) {
      debugPrint('Could not read the launching notification: $error');
      return null;
    }
  }

  /// Asks for permission to notify, once per launch. Never throws.
  Future<void> requestPermission() async {
    if (_askedPermission) return;
    _askedPermission = true;
    if (!await ready()) return;
    try {
      await android?.requestNotificationsPermission();
      await ios?.requestPermissions(alert: true, sound: true);
    } catch (error) {
      debugPrint('Could not ask for notification permission: $error');
    }
  }

  static String? _validRoute(String? payload) =>
      payload != null && routes.contains(payload) ? payload : null;

  void dispose() => _taps.close();
}

/// Null on platforms with no local notifications: the web, and the desktop
/// builds the tests run on.
final localNotificationsHubProvider = Provider<LocalNotificationsHub?>((ref) {
  if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return null;
  final hub = LocalNotificationsHub();
  ref.onDispose(hub.dispose);
  return hub;
});
