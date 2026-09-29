import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';

import '../config/app_config.dart';
import '../config/feature_flags.dart';
import '../observability/crash_reporter.dart';
import 'bootstrap_status.dart';
import 'firebase_options_adapter.dart';

/// How much of the user's data may be kept on the device for offline reads.
///
/// Stated rather than left to the SDK's 40 MB default, and larger than it: this
/// is a training log people open on the gym floor and on trail, where there is
/// often no signal at all. Documents are small — a year of posts, runs, meals
/// and workouts is comfortably inside this — so the ceiling exists to stop
/// unbounded growth, not to ration.
const int kFirestoreCacheBytes = 100 * 1024 * 1024;

Future<BootstrapStatus> bootstrapApp() async {
  WidgetsFlutterBinding.ensureInitialized();

  // FirebaseInitProvider is disabled in AndroidManifest.xml so the native
  // Google Services plugin does not auto-initialize before this call.
  await Firebase.initializeApp(options: resolveFirebaseOptions());

  // Immediately after Firebase is up and before anything else runs: an error
  // thrown during the rest of this function is exactly the kind that leaves a
  // tester with an app that will not start, and it has to be caught too.
  await installCrashHandlers();

  // Set before the first Firestore call — settings applied after the instance
  // has been used are ignored, so this belongs here and nowhere else.
  //
  // Persistence is already the default on mobile. Saying so out loud is the
  // point: offline reads are a feature this app relies on, not an accident of
  // the SDK's defaults, and a future change to them should break a line
  // someone chose rather than silently take the feature away.
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: kFirestoreCacheBytes,
  );

  // Remote Config's seed and cached values. A failure here costs only the
  // Build 11 features, which then read as off — never the launch.
  try {
    await initFeatureFlags();
  } catch (error, stack) {
    await const FirebaseCrashReporter()
        .recordError(error, stack, reason: 'feature flags init');
  }

  return const BootstrapStatus(
    backendMode: BackendMode.firebase,
    firebaseConfigured: true,
  );
}
