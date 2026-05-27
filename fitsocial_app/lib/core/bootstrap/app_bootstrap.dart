import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';

import '../config/app_config.dart';
import 'bootstrap_status.dart';
import 'firebase_options_adapter.dart';

Future<BootstrapStatus> bootstrapApp() async {
  WidgetsFlutterBinding.ensureInitialized();

  final firebaseOptions = resolveFirebaseOptions();
  if (firebaseOptions == null) {
    return const BootstrapStatus(
      backendMode: BackendMode.firebase,
      firebaseConfigured: false,
    );
  }

  await Firebase.initializeApp(options: firebaseOptions);

  return const BootstrapStatus(
    backendMode: BackendMode.firebase,
    firebaseConfigured: true,
  );
}
