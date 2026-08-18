import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bootstrap/bootstrap_status.dart';

/// Where a crash on a tester's phone goes.
///
/// This exists because of a specific gap: during external testing the people
/// running the app are not in the room, have no logcat, and will report a
/// crash as "it closed". Without this, that report is unactionable. With it,
/// the same event arrives as a stack trace against a build number.
///
/// An interface rather than direct calls to [FirebaseCrashlytics] so the widget
/// tests — which run with no Firebase app initialised — can hold a session
/// without touching the plugin. [NoopCrashReporter] is what they get.
abstract class CrashReporter {
  /// Ties subsequent reports to an account.
  ///
  /// Deliberately the uid and never the email address: it is enough to ask a
  /// tester "what happened around 14:20?" once their report has been matched,
  /// and it keeps a contact detail out of a dashboard that exists to hold
  /// stack traces. Pass null on sign-out.
  void setUserId(String? userId);

  /// Reports something the app caught and handled — a failed upload, a save
  /// that threw — without ending the session.
  ///
  /// Fatal crashes do not come through here; they arrive via the handlers
  /// installed by [installCrashHandlers].
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    String? reason,
  });
}

class FirebaseCrashReporter implements CrashReporter {
  const FirebaseCrashReporter();

  FirebaseCrashlytics get _crashlytics => FirebaseCrashlytics.instance;

  @override
  void setUserId(String? userId) {
    unawaited(_crashlytics.setUserIdentifier(userId ?? ''));
  }

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    String? reason,
  }) {
    return _crashlytics.recordError(error, stack, reason: reason);
  }
}

/// Swallows everything. Used in tests, and whenever Firebase is not configured
/// — a crash reporter that throws on a machine with no `firebase_options.dart`
/// would be its own outage.
class NoopCrashReporter implements CrashReporter {
  const NoopCrashReporter();

  @override
  void setUserId(String? userId) {}

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    String? reason,
  }) async {}
}

final crashReporterProvider = Provider<CrashReporter>((ref) {
  final status = ref.watch(bootstrapStatusProvider);
  if (status.canUseFirebase) return const FirebaseCrashReporter();
  return const NoopCrashReporter();
});

/// Routes uncaught errors to Crashlytics. Call once, from the bootstrap, after
/// `Firebase.initializeApp`.
///
/// Two handlers, because Flutter has two doors an uncaught error can leave by
/// and installing only the first is the usual reason a dashboard looks
/// suspiciously quiet:
///
///  * [FlutterError.onError] catches what the framework raises inside build,
///    layout and paint.
///  * [PlatformDispatcher.onError] catches everything else that reaches the
///    zone uncaught — a failed await in a button handler, most commonly.
///
/// Collection is off in debug builds. The dashboard is being watched during
/// testing to find what testers hit, and a developer's own hot-reload noise
/// would bury exactly that.
Future<void> installCrashHandlers() async {
  final crashlytics = FirebaseCrashlytics.instance;
  await crashlytics.setCrashlyticsCollectionEnabled(!kDebugMode);

  FlutterError.onError = (details) {
    // Keep the console output: this is what makes an error visible on the
    // laptop of whoever is running the app right now.
    FlutterError.presentError(details);
    crashlytics.recordFlutterFatalError(details);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    crashlytics.recordError(error, stack, fatal: true);
    return true;
  };
}
