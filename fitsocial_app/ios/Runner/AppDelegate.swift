import Flutter
import GoogleMaps
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// The panic siren, torch and screen. Held for the life of the engine.
  private var panic: PanicBridge?

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

    // The siren ships as a Flutter asset (assets/sounds/panic_siren.wav), so
    // no Xcode resource entry is needed; the registrar knows where it landed.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PanicBridge") {
      panic = PanicBridge(
        messenger: registrar.messenger(),
        sirenAssetKey: registrar.lookupKey(forAsset: "assets/sounds/panic_siren.wav")
      )
    }
  }
}
