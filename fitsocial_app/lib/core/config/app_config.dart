enum BackendMode {
  firebase,
}

class AppConfig {
  const AppConfig({
    required this.backendMode,
    this.enableAnalytics = false,
  });

  final BackendMode backendMode;
  final bool enableAnalytics;

  bool get usesFirebase => backendMode == BackendMode.firebase;
}

const appConfig = AppConfig(
  backendMode: BackendMode.firebase,
  enableAnalytics: false,
);
