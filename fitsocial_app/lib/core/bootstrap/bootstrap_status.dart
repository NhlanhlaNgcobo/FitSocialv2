import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';

class BootstrapStatus {
  const BootstrapStatus({
    required this.backendMode,
    required this.firebaseConfigured,
  });

  final BackendMode backendMode;
  final bool firebaseConfigured;

  bool get canUseFirebase =>
      backendMode == BackendMode.firebase && firebaseConfigured;
}

final bootstrapStatusProvider = Provider<BootstrapStatus>((ref) {
  return BootstrapStatus(
    backendMode: appConfig.backendMode,
    firebaseConfigured: false,
  );
});
