import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_repository_contract.dart';
import '../data/auth_repository.dart';
import '../data/user_profile_repository_contract.dart';
import '../data/user_profile_repository.dart';
import '../domain/auth_models.dart';

enum AuthStage {
  unauthenticated,
  profileSetup,
  authenticated,
}

class AppSession extends ChangeNotifier {
  AppSession({
    required this.authRepository,
    required this.userProfileRepository,
  });

  final AuthRepository authRepository;
  final UserProfileRepository userProfileRepository;
  AuthStage _stage = AuthStage.unauthenticated;
  bool _isLoading = false;
  String? _email;
  UserProfileDraft? _profile;
  String? _errorMessage;

  AuthStage get stage => _stage;
  bool get isLoading => _isLoading;
  String? get email => _email;
  UserProfileDraft? get profile => _profile;
  String? get errorMessage => _errorMessage;

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

  Future<void> completeProfile({
    required String displayName,
    required String handle,
    required String bio,
    required String location,
  }) async {
    if (displayName.trim().isEmpty || handle.trim().isEmpty) return;
    _setLoading(true);
    _errorMessage = null;
    try {
      _profile = await userProfileRepository.saveProfile(
        displayName: displayName.trim(),
        handle: handle.trim(),
        bio: bio.trim(),
        location: location.trim(),
      );
      _stage = AuthStage.authenticated;
    } catch (error) {
      _errorMessage = error.toString();
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
