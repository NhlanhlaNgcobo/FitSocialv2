import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

import '../domain/active_workout.dart';
import 'active_workout_controller.dart';

/// Tells the user their rest is over when the app is not on screen.
///
/// On screen, `RestTimerBar` buzzes by itself, and a system notification on
/// top of it would be the same news twice. So an alert is only ever armed when
/// the app goes to the background with a rest still running, and taken down
/// the moment it comes back.
abstract interface class RestAlerts {
  /// Asks for permission to notify, once, at a moment that explains itself:
  /// the first rest of a session. Never throws.
  Future<void> requestPermission();

  /// Arms the "rest over" alert for [rest]. Does nothing for a rest that is
  /// already over. Replaces any alert armed before.
  Future<void> arm(RestTimer rest);

  /// Takes down whatever [arm] put up or scheduled.
  Future<void> disarm();
}

class NoopRestAlerts implements RestAlerts {
  const NoopRestAlerts();

  @override
  Future<void> requestPermission() async {}

  @override
  Future<void> arm(RestTimer rest) async {}

  @override
  Future<void> disarm() async {}
}

/// [RestAlerts] through `flutter_local_notifications`.
///
/// **Android.** While resting, a silent notification counts down on the lock
/// screen; at zero it is replaced, under the same id, by an alert that sounds.
/// The alert is an exact alarm where the user allows them (by default up to
/// Android 13). From Android 14 they are off by default, and an inexact alarm
/// can land a minute late — so there the app also fires the alert itself from
/// a timer, which keeps running while the process lives in the background,
/// and the inexact alarm is only a backstop for a process that was killed.
///
/// **iOS.** The app is suspended in the background, so it is a scheduled
/// notification alone, which iOS delivers on time. There is no countdown.
class LocalRestAlerts implements RestAlerts {
  LocalRestAlerts({
    FlutterLocalNotificationsPlugin? plugin,
    DateTime Function()? now,
  })  : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
        _now = now ?? DateTime.now;

  final FlutterLocalNotificationsPlugin _plugin;
  final DateTime Function() _now;

  /// One id for the countdown and the alert, so the alert replaces the
  /// countdown rather than sitting under it.
  static const _id = 7301;

  static const _countdownChannel = AndroidNotificationChannel(
    'rest_countdown',
    'Rest countdown',
    description: 'The time left between sets, while the app is closed',
    importance: Importance.low,
    playSound: false,
    enableVibration: false,
    showBadge: false,
  );

  static const _alertChannel = AndroidNotificationChannel(
    'rest_over',
    'Rest over',
    description: 'When the rest between sets is up',
    importance: Importance.high,
  );

  Future<bool>? _ready;
  Timer? _fallback;
  bool _askedPermission = false;

  Future<bool> _init() => _ready ??= () async {
        try {
          await _plugin.initialize(
            settings: const InitializationSettings(
              android: AndroidInitializationSettings('ic_stat_fitsocial'),
              iOS: DarwinInitializationSettings(
                // Asked for in requestPermission, not at start-up.
                requestAlertPermission: false,
                requestBadgePermission: false,
                requestSoundPermission: false,
              ),
            ),
          );
          final android = _android;
          await android?.createNotificationChannel(_countdownChannel);
          await android?.createNotificationChannel(_alertChannel);
          return true;
        } catch (error) {
          debugPrint('Rest alerts unavailable: $error');
          return false;
        }
      }();

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  IOSFlutterLocalNotificationsPlugin? get _ios =>
      _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();

  @override
  Future<void> requestPermission() async {
    if (_askedPermission) return;
    _askedPermission = true;
    if (!await _init()) return;
    try {
      await _android?.requestNotificationsPermission();
      await _ios?.requestPermissions(alert: true, sound: true);
    } catch (error) {
      debugPrint('Could not ask for notification permission: $error');
    }
  }

  static NotificationDetails get _alertDetails => NotificationDetails(
        android: AndroidNotificationDetails(
          _alertChannel.id,
          _alertChannel.name,
          channelDescription: _alertChannel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: 'ic_stat_fitsocial',
          category: AndroidNotificationCategory.alarm,
          // Gone once read: a stale "rest over" from an hour ago helps nobody.
          timeoutAfter: const Duration(minutes: 5).inMilliseconds,
        ),
        iOS: const DarwinNotificationDetails(
          presentSound: true,
          interruptionLevel: InterruptionLevel.timeSensitive,
        ),
      );

  static const _alertTitle = 'Rest over';
  static const _alertBody = 'Time for your next set.';

  @override
  Future<void> arm(RestTimer rest) async {
    await disarm();
    final remaining = rest.remaining(_now());
    if (remaining <= Duration.zero) return;
    if (!await _init()) return;

    try {
      final android = _android;
      var exact = true;
      if (android != null) {
        await _plugin.show(
          id: _id,
          title: 'Resting',
          body: 'Your next set is up when this reaches zero.',
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              _countdownChannel.id,
              _countdownChannel.name,
              channelDescription: _countdownChannel.description,
              importance: Importance.low,
              priority: Priority.low,
              icon: 'ic_stat_fitsocial',
              ongoing: true,
              autoCancel: false,
              onlyAlertOnce: true,
              silent: true,
              showWhen: true,
              when: rest.endsAt.millisecondsSinceEpoch,
              usesChronometer: true,
              chronometerCountDown: true,
              timeoutAfter: remaining.inMilliseconds + 1000,
            ),
          ),
        );
        exact = await android.canScheduleExactNotifications() ?? false;
      }

      await _plugin.zonedSchedule(
        id: _id,
        scheduledDate: tz.TZDateTime.from(rest.endsAt, tz.UTC),
        title: _alertTitle,
        body: _alertBody,
        notificationDetails: _alertDetails,
        androidScheduleMode: exact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
      );

      if (android != null && !exact) {
        _fallback = Timer(remaining, _fireNow);
      }
    } catch (error) {
      debugPrint('Could not arm the rest alert: $error');
    }
  }

  /// The alert, now — and the inexact alarm behind it called off, so it does
  /// not sound a second time a minute later.
  Future<void> _fireNow() async {
    _fallback = null;
    try {
      await _plugin.cancel(id: _id);
      await _plugin.show(
        id: _id,
        title: _alertTitle,
        body: _alertBody,
        notificationDetails: _alertDetails,
      );
    } catch (error) {
      debugPrint('Could not show the rest alert: $error');
    }
  }

  @override
  Future<void> disarm() async {
    _fallback?.cancel();
    _fallback = null;
    if (_ready == null) return; // Nothing was ever armed.
    try {
      await _plugin.cancel(id: _id);
    } catch (error) {
      debugPrint('Could not clear the rest alert: $error');
    }
  }

  void dispose() => _fallback?.cancel();
}

final restAlertsProvider = Provider<RestAlerts>((ref) {
  if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
    return const NoopRestAlerts();
  }
  final alerts = LocalRestAlerts();
  ref.onDispose(alerts.dispose);
  return alerts;
});

/// Arms the rest alert when the app leaves the screen and disarms it when it
/// comes back. Driven from the app's lifecycle observer.
class RestAlertLifecycle {
  RestAlertLifecycle(this._ref);

  final Ref _ref;

  void appBackgrounded() {
    final rest = _ref.read(activeWorkoutProvider)?.rest;
    if (rest == null) return;
    unawaited(_ref.read(restAlertsProvider).arm(rest));
  }

  void appForegrounded() {
    unawaited(_ref.read(restAlertsProvider).disarm());
  }
}

final restAlertLifecycleProvider = Provider<RestAlertLifecycle>((ref) {
  return RestAlertLifecycle(ref);
});
