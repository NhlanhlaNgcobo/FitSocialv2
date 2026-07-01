import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';

import '../config/app_config.dart';
import 'bootstrap_status.dart';
import 'firebase_options_adapter.dart';

Future<BootstrapStatus> bootstrapApp() async {
  WidgetsFlutterBinding.ensureInitialized();

  // FirebaseInitProvider is disabled in AndroidManifest.xml so the native
  // Google Services plugin does not auto-initialize before this call.
  await Firebase.initializeApp(options: resolveFirebaseOptions());

  return const BootstrapStatus(
    backendMode: BackendMode.firebase,
    firebaseConfigured: true,
  );
}
