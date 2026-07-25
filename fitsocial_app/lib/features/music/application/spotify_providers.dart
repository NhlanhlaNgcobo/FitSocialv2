import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/spotify_api_service.dart';
import '../data/spotify_auth_service.dart';
import '../data/spotify_token_store.dart';

final spotifyTokenStoreProvider = Provider<SpotifyTokenStore>((ref) {
  return SpotifyTokenStore();
});

final spotifyAuthServiceProvider = Provider<SpotifyAuthService>((ref) {
  return SpotifyAuthService(tokenStore: ref.watch(spotifyTokenStoreProvider));
});

final spotifyApiServiceProvider = Provider<SpotifyApiService>((ref) {
  return SpotifyApiService(authService: ref.watch(spotifyAuthServiceProvider));
});

/// Connection state for the Spotify account.
class SpotifyConnectionState {
  const SpotifyConnectionState({
    this.isConnected = false,
    this.isBusy = false,
    this.profile,
    this.errorMessage,
  });

  final bool isConnected;
  final bool isBusy;
  final SpotifyProfile? profile;
  final String? errorMessage;

  SpotifyConnectionState copyWith({
    bool? isConnected,
    bool? isBusy,
    SpotifyProfile? profile,
    String? errorMessage,
    bool clearProfile = false,
    bool clearError = false,
  }) {
    return SpotifyConnectionState(
      isConnected: isConnected ?? this.isConnected,
      isBusy: isBusy ?? this.isBusy,
      profile: clearProfile ? null : (profile ?? this.profile),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class SpotifyConnectionController extends StateNotifier<SpotifyConnectionState> {
  SpotifyConnectionController({
    required SpotifyAuthService authService,
    required SpotifyApiService apiService,
  })  : _auth = authService,
        _api = apiService,
        super(const SpotifyConnectionState()) {
    _restore();
  }

  final SpotifyAuthService _auth;
  final SpotifyApiService _api;

  /// Rehydrates a previously connected account on app start.
  Future<void> _restore() async {
    if (!await _auth.isConnected()) return;
    state = state.copyWith(isConnected: true);
    await _loadProfile();
  }

  Future<void> connect() async {
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      await _auth.connect();
      state = state.copyWith(isConnected: true, isBusy: false);
      await _loadProfile();
    } on SpotifyAuthException catch (e) {
      state = state.copyWith(isBusy: false, errorMessage: e.message);
    } catch (e) {
      state = state.copyWith(
        isBusy: false,
        errorMessage: 'Could not connect Spotify: $e',
      );
    }
  }

  Future<void> disconnect() async {
    state = state.copyWith(isBusy: true, clearError: true);
    await _auth.disconnect();
    state = const SpotifyConnectionState();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await _api.fetchProfile();
      state = state.copyWith(profile: profile);
    } on SpotifyApiException catch (e) {
      state = state.copyWith(errorMessage: e.message);
    } catch (_) {
      // Profile is decoration — a failure here shouldn't drop the connection.
    }
  }
}

final spotifyConnectionProvider =
    StateNotifierProvider<SpotifyConnectionController, SpotifyConnectionState>(
  (ref) => SpotifyConnectionController(
    authService: ref.watch(spotifyAuthServiceProvider),
    apiService: ref.watch(spotifyApiServiceProvider),
  ),
);

/// The connected user's Spotify playlists.
final spotifyMyPlaylistsProvider =
    FutureProvider<List<SpotifyPlaylist>>((ref) async {
  final connection = ref.watch(spotifyConnectionProvider);
  if (!connection.isConnected) return const [];
  return ref.watch(spotifyApiServiceProvider).fetchMyPlaylists();
});

/// Workout-appropriate playlists surfaced via Spotify search.
final spotifyWorkoutPlaylistsProvider =
    FutureProvider.family<List<SpotifyPlaylist>, String>((ref, query) async {
  final connection = ref.watch(spotifyConnectionProvider);
  if (!connection.isConnected) return const [];
  return ref.watch(spotifyApiServiceProvider).searchPlaylists(query);
});
