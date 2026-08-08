import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_repository_contract.dart';
import '../data/auth_repository.dart';
import '../data/user_profile_repository_contract.dart';
import '../data/user_profile_repository.dart';
import '../domain/auth_error_messages.dart';
import '../domain/auth_models.dart';
import '../domain/username.dart';

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
      _finishBootstrapUnauthenticated();
      return;
    }

    // The cached credential outlives the account it points at, so a session
    // deleted server-side still restores here. Ask Firebase before trusting it.
    if (!await authRepository.hasValidSession()) {
      await _discardStaleSession();
      return;
    }

    _email = restoredEmail;
    try {
      _profile = await userProfileRepository.loadCurrentProfile();
    } catch (_) {
      // Profile load failed (offline/permission) but the auth session is
      // valid — keep the user in, let the app retry loading data.
      _stage = AuthStage.authenticated;
      notifyListeners();
      return;
    }

    if (_profile == null) {
      // Authenticated with no profile document. Either the profile was deleted
      // out from under us, or a previous signup was abandoned before setup
      // finished. Neither is a usable account, and dropping straight into
      // "Set up profile" on launch strands the user there with no way back —
      // so start clean at the welcome screen instead.
      await _discardStaleSession();
      return;
    }

    _stage = AuthStage.authenticated;
    notifyListeners();
  }

  /// Clears a restored session that turned out to be unusable and lands on the
  /// welcome screen. The sign-out itself is best-effort: if it fails we still
  /// present the app as logged out rather than trapping the user.
  Future<void> _discardStaleSession() async {
    try {
      await authRepository.signOut();
    } catch (_) {
      // Ignored on purpose — see above.
    }
    _finishBootstrapUnauthenticated();
  }

  void _finishBootstrapUnauthenticated() {
    _email = null;
    _profile = null;
    _stage = AuthStage.unauthenticated;
    notifyListeners();
  }

  /// Signs in with whatever the user typed into the one login field.
  ///
  /// [identifier] is a username or an email address; [looksLikeEmail] decides
  /// which, and the two take genuinely different routes — an email goes
  /// straight to Firebase, a username has to be resolved by a Cloud Function
  /// first. Everything after that point is identical, which is why the caller
  /// does not need to know which happened.
  Future<void> signInWithIdentifier({
    required String identifier,
    required String password,
  }) async {
    final trimmed = identifier.trim();
    if (trimmed.isEmpty || password.trim().isEmpty) return;

    await _authenticate(() {
      if (looksLikeEmail(trimmed)) {
        return authRepository.signInWithEmail(
          email: trimmed,
          password: password,
        );
      }
      return authRepository.signInWithUsername(
        username: trimmed,
        password: password,
      );
    });
  }

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    if (email.trim().isEmpty || password.trim().isEmpty) return;
    await _authenticate(
      () => authRepository.signInWithEmail(email: email, password: password),
    );
  }

  Future<void> signUpWithEmail({
    required String email,
    required String password,
  }) async {
    if (email.trim().isEmpty || password.trim().isEmpty) return;
    await _authenticate(
      () => authRepository.signUpWithEmail(email: email, password: password),
    );
  }

  Future<void> continueWithProvider(String providerName) {
    return _authenticate(
      () => authRepository.continueWithProvider(providerName),
    );
  }

  /// The shared tail of every way into the app.
  ///
  /// [signIn] is whichever credential exchange was chosen; what follows —
  /// loading the profile, deciding between setup and the app proper, turning a
  /// thrown error into a sentence — is the same regardless, and was previously
  /// copied out once per sign-in method.
  Future<void> _authenticate(Future<String> Function() signIn) async {
    _setLoading(true);
    _errorMessage = null;
    try {
      _email = await signIn();
      _profile = await userProfileRepository.loadCurrentProfile();
      // No profile means the account exists but was never finished, so setup
      // is where they land rather than the feed.
      _stage = _profile == null
          ? AuthStage.profileSetup
          : AuthStage.authenticated;
    } catch (error) {
      _errorMessage = describeAuthError(error);
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
      _errorMessage = describeAuthError(error);
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
      _errorMessage = describeAuthError(error);
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
