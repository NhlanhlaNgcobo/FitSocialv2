import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/observability/crash_reporter.dart';
import '../../notifications/application/push_registrar.dart';
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
    this.crashReporter = const NoopCrashReporter(),
    this.pushRegistrar = const NoopPushRegistrar(),
  }) {
    _bootstrap();
  }

  final AuthRepository authRepository;
  final UserProfileRepository userProfileRepository;

  /// Where crashes go. Defaults to a no-op so a test can build a session
  /// without a Firebase app behind it.
  final CrashReporter crashReporter;

  /// This device's push registration, which lives and dies with the session.
  ///
  /// It belongs here rather than beside the notification screen because the two
  /// moments that matter are both this class's: reaching [AuthStage.authenticated],
  /// and the instant before a sign-out. Defaults to a no-op for the same reason
  /// [crashReporter] does.
  final PushRegistrar pushRegistrar;
  AuthStage _stage = AuthStage.initializing;
  bool _isLoading = false;
  String? _email;
  UserProfileDraft? _profile;
  String? _errorMessage;

  /// A Google sign-in that stopped because the email already has a password.
  /// Finished by the next successful password login on that same address.
  ProviderLinkRequiredException? _pendingLink;

  /// Guards [reloadProfile] against overlapping reads — the profile page can
  /// ask more than once before the first answer lands.
  bool _isReloadingProfile = false;

  AuthStage get stage => _stage;
  bool get isLoading => _isLoading;
  String? get email => _email;
  UserProfileDraft? get profile => _profile;
  String? get errorMessage => _errorMessage;

  /// The email a social sign-in is waiting to be linked to, or null. The login
  /// screen watches it to put the password form in front of the user.
  String? get pendingLinkEmail => _pendingLink?.email;

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
    _identifyForCrashReports();
    try {
      _profile = await userProfileRepository.loadCurrentProfile();
    } catch (_) {
      // Profile load failed (offline/permission) but the auth session is
      // valid — keep the user in, let the app retry loading data.
      _setStage(AuthStage.authenticated);
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

    _setStage(AuthStage.authenticated);
    notifyListeners();
  }

  /// Clears a restored session that turned out to be unusable and lands on the
  /// welcome screen. The sign-out itself is best-effort: if it fails we still
  /// present the app as logged out rather than trapping the user.
  Future<void> _discardStaleSession() async {
    try {
      // Same ordering as signOut below, and for the same reason. The write will
      // often fail here anyway — the session being discarded is one the server
      // has already stopped honouring — but deleting the token on the device is
      // the half that still works, and it is the half that stops this phone
      // holding an address the dead account was being pushed at.
      await _unregisterPushQuietly();
      await authRepository.signOut();
    } catch (_) {
      // Ignored on purpose — see above.
    }
    _finishBootstrapUnauthenticated();
  }

  void _finishBootstrapUnauthenticated() {
    crashReporter.setUserId(null);
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

    await _authenticate(() async {
      final email = looksLikeEmail(trimmed)
          ? await authRepository.signInWithEmail(
              email: trimmed,
              password: password,
            )
          : await authRepository.signInWithUsername(
              username: trimmed,
              password: password,
            );
      await _finishPendingLink(email);
      return email;
    });
  }

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    if (email.trim().isEmpty || password.trim().isEmpty) return;
    await _authenticate(() async {
      final signedIn = await authRepository.signInWithEmail(
        email: email,
        password: password,
      );
      await _finishPendingLink(signedIn);
      return signedIn;
    });
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
    // A fresh attempt supersedes whatever the last one left waiting.
    _pendingLink = null;
    return _authenticate(
      () => authRepository.continueWithProvider(providerName),
    );
  }

  /// Attaches the provider a stalled social sign-in left behind, now that the
  /// password has proved who owns the account.
  ///
  /// Only when [signedInEmail] is the address the provider claimed: someone
  /// who gave up on Google and logged into a *different* account must not
  /// have that Google identity bolted onto it. Failure is logged and
  /// swallowed — the login itself worked, and they can still use the
  /// password; Google will simply ask again next time.
  Future<void> _finishPendingLink(String signedInEmail) async {
    final pending = _pendingLink;
    if (pending == null) return;
    _pendingLink = null;
    if (pending.email.toLowerCase() != signedInEmail.toLowerCase()) return;
    try {
      await pending.linkToCurrentUser();
    } catch (error) {
      debugPrint('Linking the social sign-in failed: $error');
    }
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
      _identifyForCrashReports();
      _profile = await userProfileRepository.loadCurrentProfile();
      // No profile means the account exists but was never finished, so setup
      // is where they land rather than the feed.
      _setStage(
        _profile == null ? AuthStage.profileSetup : AuthStage.authenticated,
      );
    } catch (error) {
      if (error is ProviderLinkRequiredException) _pendingLink = error;
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
      _setStage(AuthStage.authenticated);
      return true;
    } catch (error) {
      _errorMessage = describeAuthError(error);
      return false;
    } finally {
      _setLoading(false, shouldNotify: false);
      notifyListeners();
    }
  }

  /// Re-reads the profile document into the session.
  ///
  /// [_bootstrap] deliberately keeps a user signed in when the profile read
  /// fails — offline, or a permission blip — which leaves the session
  /// authenticated with no profile at all. The profile page then shows a
  /// placeholder name and no bio, and nothing would ever ask again for the rest
  /// of the launch. Screens that render the profile call this to close that gap.
  ///
  /// Failure is silent on purpose: this is a background repair, and the page it
  /// runs under is already showing something.
  Future<void> reloadProfile() async {
    if (_stage != AuthStage.authenticated || _isReloadingProfile) return;
    _isReloadingProfile = true;
    try {
      final loaded = await userProfileRepository.loadCurrentProfile();
      // A null here means the document is genuinely gone, not that the read
      // failed. Dropping what the session already holds would be a downgrade.
      if (loaded == null) return;
      _profile = loaded;
      notifyListeners();
    } catch (_) {
      // Still unreachable. The next visit to the profile asks again.
    } finally {
      _isReloadingProfile = false;
    }
  }

  /// Whether Settings should offer to add a password. See
  /// [AuthRepository.canAddPassword].
  bool get canAddPassword => authRepository.canAddPassword();

  /// Adds a password to the signed-in account. Returns true only when Firebase
  /// accepted it; on false, [errorMessage] says why.
  ///
  /// Uses [_setLoading] like the other account actions, but never changes the
  /// stage: the user is already in, and this only adds another way back.
  Future<bool> addPassword(String password) async {
    _setLoading(true);
    _errorMessage = null;
    try {
      await authRepository.addPassword(password);
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
      // BEFORE the sign-out, and awaited. Deleting the token document is a
      // Firestore write that the rules only permit to its owner, so once the
      // session is gone it is denied and the registration survives — and the
      // next person to sign in on this phone starts receiving the previous
      // user's notifications. The ordering here is the whole safeguard.
      await _unregisterPushQuietly();
      await authRepository.signOut();
      crashReporter.setUserId(null);
      _email = null;
      _profile = null;
      _pendingLink = null;
      _stage = AuthStage.unauthenticated;
      _isLoading = false;
    } catch (error) {
      _errorMessage = describeAuthError(error);
    } finally {
      notifyListeners();
    }
  }

  /// Permanently deletes the account and drops the session.
  ///
  /// Returns true only when the server confirmed the deletion. A false return
  /// leaves the user signed in with [errorMessage] set, which is the honest
  /// outcome: their data is still there and they may want to try again.
  ///
  /// There is no undo, and nothing here is optimistic — the session is not
  /// cleared until the call has come back.
  Future<bool> deleteAccount() async {
    _setLoading(true);
    _errorMessage = null;
    try {
      // The server-side sweep takes the token documents with everything else
      // under users/{uid}, so this is not what removes them. What it does is
      // release the token on the device, so this installation is not left
      // holding an address issued to an account that no longer exists.
      await _unregisterPushQuietly();
      await authRepository.deleteAccount();
      crashReporter.setUserId(null);
      _email = null;
      _profile = null;
      _stage = AuthStage.unauthenticated;
      return true;
    } catch (error) {
      _errorMessage = describeAuthError(error);
      return false;
    } finally {
      _setLoading(false, shouldNotify: false);
      notifyListeners();
    }
  }

  /// Tags crash reports with the uid, so a report from a tester can be matched
  /// to the account that hit it. Never the email — see [CrashReporter.setUserId].
  void _identifyForCrashReports() {
    crashReporter.setUserId(authRepository.currentUserId());
  }

  /// Moves the session to [stage], and puts this device on the push list the
  /// moment that stage is a signed-in one.
  ///
  /// Every transition goes through here rather than assigning [_stage] directly,
  /// so that a new way into the app — a third sign-in method, a new post-setup
  /// path — cannot quietly skip registration and leave that route's users with
  /// an inbox that fills up and a phone that never makes a sound.
  ///
  /// Does not notify. The call sites differ on when they want to, and several
  /// of them have more to set first.
  void _setStage(AuthStage stage) {
    _stage = stage;
    if (stage == AuthStage.authenticated) _registerForPush();
  }

  /// Registers this device for push, without waiting for it.
  ///
  /// Fire-and-forget on purpose. Registration can raise the system notification
  /// prompt, and awaiting it would hold the app on a loading spinner until the
  /// user had answered a dialog. [PushRegistrar] swallows its own failures, so
  /// there is no error here to lose.
  void _registerForPush() {
    final userId = authRepository.currentUserId();
    if (userId == null) return;

    // Caught here rather than left to the zone. This is deliberately not
    // awaited, so a throw would arrive as an unhandled async error with no
    // caller left to attach it to — reported as a crash, on a launch that
    // otherwise went fine.
    unawaited(
      pushRegistrar.register(userId).catchError((Object error) {
        debugPrint('Registering for push failed: $error');
        return false;
      }),
    );
  }

  /// Withdraws this device's push registration, swallowing any failure.
  ///
  /// Best-effort by design, and it has to be. A token that could not be deleted
  /// means one more notification may reach a phone whose owner has signed out
  /// of that account. A withdrawal allowed to throw means somebody offline
  /// cannot sign out at all — the operation it precedes never runs. The second
  /// is much the worse of the two, so this can never fail what follows it.
  Future<void> _unregisterPushQuietly() async {
    try {
      await pushRegistrar.unregister();
    } catch (error) {
      debugPrint('Withdrawing the push registration failed: $error');
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
    crashReporter: ref.watch(crashReporterProvider),
    pushRegistrar: ref.watch(pushRegistrarProvider),
  );
});
