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
  // On from Build 11. What is sent is listed in AnalyticsEvent
  // (core/observability/app_analytics.dart): kinds and counts, never names,
  // typed text or coordinates. The Play Data Safety form must declare app
  // interactions accordingly.
  enableAnalytics: true,
);
