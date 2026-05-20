# FitSocial App

Phase 1 foundation for the FitSocial Flutter app:

- app theme tokens
- router shell
- social bottom navigation
- reusable shared UI widgets
- placeholder feature screens matching the MVP plan

The workspace was scaffolded manually because `flutter create` did not complete in the current environment.

## Current Architecture

- `mock` backend mode is the active default
- auth flow is routed through repository contracts
- feed/profile/progress demo content is routed through repository contracts
- repository boundaries are ready for Firebase-backed implementations

## Firebase Next Steps

1. Run `flutter pub get`
2. Run `flutterfire configure`
3. Replace the `resolveFirebaseOptions()` placeholder in [firebase_options_adapter.dart](/C:/Users/NhlanhlaNgcobo/OneDrive/Desktop/Fitsocialv3/fitsocial_app/lib/core/bootstrap/firebase_options_adapter.dart) with `DefaultFirebaseOptions.currentPlatform`
4. Switch `backendMode` in [app_config.dart](/C:/Users/NhlanhlaNgcobo/OneDrive/Desktop/Fitsocialv3/fitsocial_app/lib/core/config/app_config.dart) from `BackendMode.mock` to `BackendMode.firebase`
5. Replace the remaining `UnimplementedError` sections in:
   - [firebase_auth_repository.dart](/C:/Users/NhlanhlaNgcobo/OneDrive/Desktop/Fitsocialv3/fitsocial_app/lib/features/auth/data/firebase_auth_repository.dart)
   - [firestore_content_repository.dart](/C:/Users/NhlanhlaNgcobo/OneDrive/Desktop/Fitsocialv3/fitsocial_app/lib/features/main/data/firestore_content_repository.dart)
