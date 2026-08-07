import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_repository_contract.dart';
import '../data/auth_repository.dart';
import '../data/user_profile_repository_contract.dart';
import '../data/user_profile_repository.dart';
import '../domain/auth_models.dart';

enum AuthStage {
  /// Cold-start bootstrap: checking Firebase for a restored session.
  initializing,
  unauthenticated,
  profileSetup,
  authenticated,
}

class AppSession extends ChangeNotifier {
  AppSession({
    required this.authRepository,
    required this.userProfileRepository,
  }) {
    _bootstrap();
  }

  final AuthRepository authRepository;
  final UserProfileRepository userProfileRepository;
  AuthStage _stage = AuthStage.initializing;
  bool _isLoading = false;
  String? _email;
  UserProfileDraft? _profile;
  String? _errorMessage;

  AuthStage get stage => _stage;
  bool get isLoading => _isLoading;
  String? get email => _email;
  UserProfileDraft? get profile => _profile;
  String? get errorMessage => _errorMessage;

  /// Rehydrates the session on cold start. Firebase Auth persists the
  /// signed-in user across launches; we ask for it, load the profile, and
  /// route straight to the app (or profile setup) instead of the welcome
  /// screen.
  Future<void> _bootstrap() async {
    final restoredEmail = authRepository.currentUserEmail();
    if (restoredEmail == null) {
      _stage = AuthStage.unauthenticated;
      notifyListeners();
      return;
    }

    _email = restoredEmail;
    try {
      _profile = await userProfileRepository.loadCurrentProfile();
      _stage =
          _profile != null ? AuthStage.authenticated : AuthStage.profileSetup;
    } catch (_) {
      // Profile load failed (offline/permission) but the auth session is
      // valid — keep the user in, let the app retry loading data.
      _stage = AuthStage.authenticated;
    }
    notifyListeners();
  }

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    if (email.trim().isEmpty || password.trim().isEmpty) return;
    _setLoading(true);
    _errorMessage = null;
    try {
      _email = await authRepository.signInWithEmail(
        email: email,
        password: password,
      );
      _profile = await userProfileRepository.loadCurrentProfile();
      _stage = AuthStage.profileSetup;
      if (_profile != null) {
        _stage = AuthStage.authenticated;
      }
    } catch (error) {
      _errorMessage = error.toString();
    } finally {
      _setLoading(false, shouldNotify: false);
      notifyListeners();
    }
  }

  Future<void> signUpWithEmail({
    required String email,
    required String password,
  }) async {
    if (email.trim().isEmpty || password.trim().isEmpty) return;
    _setLoading(true);
    _errorMessage = null;
    try {
      _email = await authRepository.signUpWithEmail(
        email: email,
        password: password,
      );
      _profile = await userProfileRepository.loadCurrentProfile();
      _stage = AuthStage.profileSetup;
      if (_profile != null) {
        _stage = AuthStage.authenticated;
      }
    } catch (error) {
      _errorMessage = error.toString();
    } finally {
      _setLoading(false, shouldNotify: false);
      notifyListeners();
    }
  }

  Future<void> continueWithProvider(String providerName) async {
    _setLoading(true);
    _errorMessage = null;
    try {
      _email = await authRepository.continueWithProvider(providerName);
      _profile = await userProfileRepository.loadCurrentProfile();
      _stage = AuthStage.profileSetup;
      if (_profile != null) {
        _stage = AuthStage.authenticated;
      }
    } catch (error) {
      _errorMessage = error.toString();
    } finally {
      _setLoading(false, shouldNotify: false);
      notifyListeners();
    }
  }

  /// Saves the profile. Returns true only when the write (including any avatar
  /// upload) actually succeeded — callers must not treat completion as success,
  /// or a failed save looks identical to a saved one.
  ///
  /// Every field is written on every call. A caller editing one of them must
  /// pass the current values of the rest, or they are cleared.
  Future<bool> completeProfile({
    required String displayName,
    required String handle,
    required String bio,
    required String location,
    String? avatarLocalPath,
    String pronouns = '',
    String links = '',
  }) async {
    if (displayName.trim().isEmpty || handle.trim().isEmpty) {
      _errorMessage = 'Display name and handle are both required.';
      notifyListeners();
      return false;
    }
    _setLoading(true);
    _errorMessage = null;
    try {
      _profile = await userProfileRepository.saveProfile(
        displayName: displayName.trim(),
        handle: handle.trim(),
        bio: bio.trim(),
        location: location.trim(),
        avatarLocalPath: avatarLocalPath,
        pronouns: pronouns.trim(),
        links: links.trim(),
      );
      _stage = AuthStage.authenticated;
      return true;
    } catch (error) {
      _errorMessage = error.toString();
      return false;
    } finally {
      _setLoading(false, shouldNotify: false);
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    _errorMessage = null;
    try {
      await authRepository.signOut();
      _email = null;
      _profile = null;
      _stage = AuthStage.unauthenticated;
      _isLoading = false;
    } catch (error) {
      _errorMessage = error.toString();
    } finally {
      notifyListeners();
    }
  }

  void clearError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    notifyListeners();
  }


  void _setLoading(bool value, {bool shouldNotify = true}) {
    _isLoading = value;
    if (shouldNotify) {
      notifyListeners();
    }
  }
}

final appSessionProvider = ChangeNotifierProvider<AppSession>((ref) {
  return AppSession(
    authRepository: ref.watch(authRepositoryProvider),
    userProfileRepository: ref.watch(userProfileRepositoryProvider),
  );
});
