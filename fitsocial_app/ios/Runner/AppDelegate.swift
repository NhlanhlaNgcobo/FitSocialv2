import Flutter
import GoogleMaps
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // The iOS Maps SDK needs its key before any GMSMapView is created, which
    // for google_maps_flutter means before the Flutter engine runs.
    //
    // The key is read from Info.plist rather than hardcoded here, so it stays
    // out of source control: Info.plist resolves GMSApiKey from the
    // MAPS_API_KEY build setting (see ios/Flutter/*.xcconfig). Guarded because
    // provideAPIKey traps on an empty string — without a key the app still
    // launches and only the map view is unavailable.
    if let apiKey = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String,
       !apiKey.isEmpty,
       apiKey != "$(MAPS_API_KEY)" {
      GMSServices.provideAPIKey(apiKey)
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
