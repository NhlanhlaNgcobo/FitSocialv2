import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/local_notifications_hub.dart';
import '../domain/active_workout.dart';
import '../domain/workout_log_form.dart';
import 'active_workout_controller.dart';
import 'workout_log_form_controller.dart';

/// Keeps a workout visible while the app is not.
///
/// A run being tracked sits in the notification shade the whole time the
/// phone is in a pocket, and testers expected a workout to do the same: leave
/// the app mid-session, come back, and find it still going. Without anything
/// on screen the workout was invisible the moment the app left the
/// foreground, and if Android reclaimed the app it looked lost — the session
/// was still on disk, but nothing said so or led back to it.
///
/// So when the app goes to the background with a workout open, this puts up
/// a notice that says so and opens it again when tapped:
///
///  * a live session gets an ongoing "Workout in progress" with its clock
///    running from the moment it started, which keeps time by itself with the
///    app asleep or gone, the way the session's own clock does;
///  * a Log Workout form not yet saved gets a reminder that it is waiting.
///
/// Taken down the moment the app is back, where the screen says it all.
abstract interface class WorkoutBackgroundNotice {
  /// Asks for permission to notify, once, at a moment that explains itself:
  /// a workout being started. Never throws.
  Future<void> requestPermission();

  Future<void> showSession(ActiveWorkout workout);

  Future<void> showUnsavedLog(WorkoutLogForm form);

  Future<void> hide();
}

class NoopWorkoutBackgroundNotice implements WorkoutBackgroundNotice {
  const NoopWorkoutBackgroundNotice();

  @override
  Future<void> requestPermission() async {}

  @override
  Future<void> showSession(ActiveWorkout workout) async {}

  @override
  Future<void> showUnsavedLog(WorkoutLogForm form) async {}

  @override
  Future<void> hide() async {}
}

/// [WorkoutBackgroundNotice] through the shared local-notifications plugin.
class LocalWorkoutBackgroundNotice implements WorkoutBackgroundNotice {
  LocalWorkoutBackgroundNotice(this._hub);

  final LocalNotificationsHub _hub;

  /// Its own id, apart from the rest countdown's 7301: resting is a moment
  /// inside the workout, and the two sit together rather than replacing one
  /// another.
  static const _id = 7302;

  static const _channel = AndroidNotificationChannel(
    'workout_in_progress',
    'Workout in progress',
    description: 'A workout you left open while the app was closed',
    importance: Importance.low,
    playSound: false,
    enableVibration: false,
    showBadge: false,
  );

  Future<bool>? _ready;

  Future<bool> _init() => _ready ??= () async {
        if (!await _hub.ready()) return false;
        try {
          await _hub.android?.createNotificationChannel(_channel);
          return true;
        } catch (error) {
          debugPrint('Workout notice unavailable: $error');
          return false;
        }
      }();

  static AndroidNotificationDetails _android({
    required bool ongoing,
    DateTime? clockFrom,
  }) =>
      AndroidNotificationDetails(
        _channel.id,
        _channel.name,
        channelDescription: _channel.description,
        importance: Importance.low,
        priority: Priority.low,
        icon: 'ic_stat_fitsocial',
        category: AndroidNotificationCategory.workout,
        ongoing: ongoing,
        autoCancel: !ongoing,
        onlyAlertOnce: true,
        silent: true,
        // The session's own clock, counting up in the shade without the app
        // having to wake and redraw it.
        showWhen: clockFrom != null,
        when: clockFrom?.millisecondsSinceEpoch,
        usesChronometer: clockFrom != null,
      );

  @override
  Future<void> requestPermission() => _hub.requestPermission();

  @override
  Future<void> showSession(ActiveWorkout workout) async {
    if (!await _init()) return;
    final sets = workout.doneSetCount;
    final title = workout.title.trim();
    try {
      await _hub.plugin.show(
        id: _id,
        title: workout.isPaused
            ? (title.isEmpty ? 'Workout paused' : '$title paused')
            : (title.isEmpty ? 'Workout in progress' : '$title in progress'),
        body: sets == 0
            ? 'Still timing. Tap to go back to it.'
            : '${sets == 1 ? '1 set' : '$sets sets'} done. Tap to go back '
                'to it.',
        notificationDetails: NotificationDetails(
          // The chronometer counts from "now less the time trained", so
          // pauses stay out of it; while paused there is no clock to run.
          android: _android(
            ongoing: true,
            clockFrom: workout.isPaused
                ? null
                : DateTime.now().subtract(workout.elapsed(DateTime.now())),
          ),
          iOS: const DarwinNotificationDetails(presentSound: false),
        ),
        payload: '/workout-session',
      );
    } catch (error) {
      debugPrint('Could not show the workout notice: $error');
    }
  }

  @override
  Future<void> showUnsavedLog(WorkoutLogForm form) async {
    if (!await _init()) return;
    final title = form.title.trim();
    try {
      await _hub.plugin.show(
        id: _id,
        title: 'Your workout is not saved yet',
        body: title.isEmpty
            ? 'Tap to finish logging it.'
            : 'Tap to finish logging $title.',
        notificationDetails: NotificationDetails(
          android: _android(ongoing: false),
          iOS: const DarwinNotificationDetails(presentSound: false),
        ),
        payload: '/log-workout',
      );
    } catch (error) {
      debugPrint('Could not show the workout notice: $error');
    }
  }

  @override
  Future<void> hide() async {
    // Not skipped when nothing was shown in this process: the notice may be
    // left over from one Android has since killed, and the app opening again
    // is exactly when it should go.
    if (!await _init()) return;
    try {
      await _hub.plugin.cancel(id: _id);
    } catch (error) {
      debugPrint('Could not clear the workout notice: $error');
    }
  }
}

final workoutBackgroundNoticeProvider =
    Provider<WorkoutBackgroundNotice>((ref) {
  final hub = ref.watch(localNotificationsHubProvider);
  if (hub == null) return const NoopWorkoutBackgroundNotice();
  return LocalWorkoutBackgroundNotice(hub);
});

/// Puts the notice up when the app leaves the screen and takes it down when
/// it comes back. Driven from the app's lifecycle observer.
class WorkoutNoticeLifecycle {
  WorkoutNoticeLifecycle(this._ref);

  final Ref _ref;

  void appBackgrounded() {
    // Written now, not when the debounce would have: this may be the last
    // moment the process gets.
    unawaited(_ref.read(workoutLogFormProvider.notifier).flush());

    final notice = _ref.read(workoutBackgroundNoticeProvider);
    final session = _ref.read(activeWorkoutProvider);
    if (session != null) {
      unawaited(notice.showSession(session));
      return;
    }
    final form = _ref.read(workoutLogFormProvider);
    if (form != null && form.hasContent) {
      unawaited(notice.showUnsavedLog(form));
    }
  }

  void appForegrounded() {
    unawaited(_ref.read(workoutBackgroundNoticeProvider).hide());
  }
}

final workoutNoticeLifecycleProvider = Provider<WorkoutNoticeLifecycle>((ref) {
  return WorkoutNoticeLifecycle(ref);
});
