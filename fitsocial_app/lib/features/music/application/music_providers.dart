import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main/domain/app_models.dart';
import '../data/apple_music_auth_service.dart';
import '../data/apple_music_config.dart';
import '../data/music_token_store.dart';
import '../data/pkce_oauth_client.dart';
import '../data/spotify_api_service.dart';
import '../data/spotify_app_remote_service.dart';
import '../data/spotify_config.dart';
import '../data/youtube_music_api_service.dart';
import '../data/youtube_music_config.dart';
import '../domain/music_brand.dart';

// --- Services ---

/// Token stores are namespaced per service so connecting one never disturbs
/// another's saved session.
final spotifyAuthProvider = Provider<PkceOAuthClient>((ref) {
  return PkceOAuthClient(
    config: SpotifyConfig.oauth,
    tokenStore: MusicTokenStore(serviceKey: 'spotify'),
  );
});

final youTubeMusicAuthProvider = Provider<PkceOAuthClient>((ref) {
  return PkceOAuthClient(
    config: YouTubeMusicConfig.oauth,
    tokenStore: MusicTokenStore(serviceKey: 'youtube_music'),
  );
});

final appleMusicAuthProvider = Provider<AppleMusicAuthService>((ref) {
  return AppleMusicAuthService(
    tokenStore: MusicTokenStore(serviceKey: 'apple_music'),
  );
});

final spotifyApiServiceProvider = Provider<SpotifyApiService>((ref) {
  return SpotifyApiService(authService: ref.watch(spotifyAuthProvider));
});

/// The bridge to the Spotify app on this phone.
///
/// Root-scoped on purpose: the connection has to outlive the player card, or
/// navigating away from the workout screen would tear down the link to the
/// process that is actually producing sound.
final spotifyAppRemoteServiceProvider = Provider<SpotifyAppRemoteService>((ref) {
  final service = SpotifyAppRemoteService();
  ref.onDispose(service.disconnect);
  return service;
});

final youTubeMusicApiServiceProvider = Provider<YouTubeMusicApiService>((ref) {
  return YouTubeMusicApiService(authService: ref.watch(youTubeMusicAuthProvider));
});

// --- Connection state ---

/// One music service's connection, as the UI needs to see it.
class MusicServiceConnection {
  const MusicServiceConnection({
    required this.service,
    this.isConnected = false,
    this.isBusy = false,
    this.accountName,
    this.avatarUrl,
    this.supportsPlayback = false,
    this.errorMessage,
  });

  final MusicProviderService service;
  final bool isConnected;
  final bool isBusy;
  final String? accountName;
  final String? avatarUrl;

  /// Whether this connection can drive the transport controls. Only Spotify
  /// Premium can today: Apple Music and YouTube Music expose no public remote
  /// playback API on Android.
  final bool supportsPlayback;

  final String? errorMessage;

  /// Held back deliberately rather than merely unconfigured — the UI shades
  /// these instead of explaining a setup step nobody is being asked to do.
  bool get isComingSoon => MusicBrand.of(service).comingSoon;

  /// False when this build has no credentials for the service yet, so the
  /// connect sheet can say what is missing instead of opening a dead page.
  bool get isAvailable {
    if (isComingSoon) return false;
    switch (service) {
      case MusicProviderService.spotify:
        return SpotifyConfig.oauth.isConfigured;
      case MusicProviderService.appleMusic:
        return AppleMusicConfig.isConfigured;
      case MusicProviderService.youtubeMusic:
        return YouTubeMusicConfig.oauth.isConfigured;
    }
  }

  String? get unavailableReason {
    if (isAvailable) return null;
    if (isComingSoon) return '${service.label} is coming soon.';
    switch (service) {
      case MusicProviderService.spotify:
        return 'Spotify is not set up in this build yet.';
      case MusicProviderService.appleMusic:
        return AppleMusicConfig.setupHint;
      case MusicProviderService.youtubeMusic:
        return 'YouTube Music needs a Google OAuth client ID before it can be '
            'connected.';
    }
  }

  MusicServiceConnection copyWith({
    bool? isConnected,
    bool? isBusy,
    String? accountName,
    String? avatarUrl,
    bool? supportsPlayback,
    String? errorMessage,
    bool clearError = false,
    bool clearAccount = false,
  }) {
    return MusicServiceConnection(
      service: service,
      isConnected: isConnected ?? this.isConnected,
      isBusy: isBusy ?? this.isBusy,
      accountName: clearAccount ? null : (accountName ?? this.accountName),
      avatarUrl: clearAccount ? null : (avatarUrl ?? this.avatarUrl),
      supportsPlayback: supportsPlayback ?? this.supportsPlayback,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class MusicConnectionsState {
  const MusicConnectionsState({required this.services, this.primary});

  final Map<MusicProviderService, MusicServiceConnection> services;

  /// The service the player and playlist views act on when more than one is
  /// connected.
  final MusicProviderService? primary;

  MusicServiceConnection operator [](MusicProviderService service) =>
      services[service] ?? MusicServiceConnection(service: service);

  List<MusicProviderService> get connectedServices => services.values
      .where((c) => c.isConnected)
      .map((c) => c.service)
      .toList(growable: false);

  bool get hasAnyConnection => connectedServices.isNotEmpty;

  bool isConnected(MusicProviderService service) => this[service].isConnected;

  /// The connection the player should drive, if any.
  MusicServiceConnection? get activeConnection {
    final chosen = primary;
    if (chosen != null && isConnected(chosen)) return this[chosen];
    final connected = connectedServices;
    return connected.isEmpty ? null : this[connected.first];
  }

  static MusicConnectionsState initial() {
    return MusicConnectionsState(
      services: {
        for (final service in MusicProviderService.values)
          service: MusicServiceConnection(service: service),
      },
    );
  }

  MusicConnectionsState withService(MusicServiceConnection connection) {
    return MusicConnectionsState(
      services: {...services, connection.service: connection},
      primary: primary,
    );
  }

  MusicConnectionsState withPrimary(MusicProviderService? service) {
    return MusicConnectionsState(services: services, primary: service);
  }
}

/// Owns sign-in and sign-out for all three services.
class MusicConnectionsController extends StateNotifier<MusicConnectionsState> {
  MusicConnectionsController(this._ref) : super(MusicConnectionsState.initial()) {
    _restore();
  }

  final Ref _ref;

  /// Rehydrates previously connected accounts on app start.
  Future<void> _restore() async {
    for (final service in MusicProviderService.values) {
      // Each iteration resumes after an await, by which point the container
      // may be gone — and _authFor reads from it. Without this guard a sign-out
      // (or a torn-down test) mid-restore throws from a future nobody awaits.
      if (!mounted) return;
      final source = _authFor(service);
      if (!await source.isConnected()) continue;
      if (!mounted) return;
      _update(service, (c) => c.copyWith(isConnected: true));
      _setPrimaryIfUnset(service);
      await _loadAccount(service);
    }
  }

  Future<void> connect(MusicProviderService service) async {
    // A paused service must not reach its auth flow even if something calls
    // this directly — the shade in the sheet is presentation, not the gate.
    if (state[service].isComingSoon) return;

    _update(service, (c) => c.copyWith(isBusy: true, clearError: true));
    try {
      switch (service) {
        case MusicProviderService.spotify:
          await _ref.read(spotifyAuthProvider).connect();
          break;
        case MusicProviderService.youtubeMusic:
          await _ref.read(youTubeMusicAuthProvider).connect();
          break;
        case MusicProviderService.appleMusic:
          await _ref.read(appleMusicAuthProvider).connect();
          break;
      }
      if (!mounted) return;
      _update(service, (c) => c.copyWith(isConnected: true, isBusy: false));
      _setPrimaryIfUnset(service);
      await _loadAccount(service);
    } on MusicAuthException catch (e) {
      if (!mounted) return;
      _update(service, (c) => c.copyWith(isBusy: false, errorMessage: e.message));
    } catch (e) {
      if (!mounted) return;
      _update(
        service,
        (c) => c.copyWith(
          isBusy: false,
          errorMessage: 'Could not connect ${service.label}: $e',
        ),
      );
    }
  }

  Future<void> disconnect(MusicProviderService service) async {
    _update(service, (c) => c.copyWith(isBusy: true, clearError: true));
    try {
      if (service == MusicProviderService.spotify) {
        // Dropping the token without dropping the bridge would leave the app
        // still driving playback for an account it has signed out of.
        await _ref.read(spotifyAppRemoteServiceProvider).disconnect();
      }
      await _authFor(service).disconnect();
    } finally {
      // Whatever the token store did, the account must not be left showing as
      // connected with a spinner stuck on it.
      if (mounted) {
        state = state.withService(MusicServiceConnection(service: service));
      }
    }
    if (!mounted) return;
    if (state.primary == service) {
      final remaining = state.connectedServices;
      state = state.withPrimary(remaining.isEmpty ? null : remaining.first);
    }
  }

  void setPrimary(MusicProviderService service) {
    if (!state.isConnected(service)) return;
    state = state.withPrimary(service);
  }

  void clearError(MusicProviderService service) {
    _update(service, (c) => c.copyWith(clearError: true));
  }

  MusicAccessTokenSource _authFor(MusicProviderService service) {
    switch (service) {
      case MusicProviderService.spotify:
        return _ref.read(spotifyAuthProvider);
      case MusicProviderService.youtubeMusic:
        return _ref.read(youTubeMusicAuthProvider);
      case MusicProviderService.appleMusic:
        return _ref.read(appleMusicAuthProvider);
    }
  }

  /// Account details are decoration — a failure here must not drop a
  /// connection that is otherwise working.
  Future<void> _loadAccount(MusicProviderService service) async {
    try {
      switch (service) {
        case MusicProviderService.spotify:
          final profile = await _ref.read(spotifyApiServiceProvider).fetchProfile();
          if (!mounted) return;
          _update(
            service,
            (c) => c.copyWith(
              accountName: profile.displayName,
              avatarUrl: profile.imageUrl,
              supportsPlayback: profile.isPremium,
            ),
          );
          break;
        case MusicProviderService.youtubeMusic:
          final profile =
              await _ref.read(youTubeMusicApiServiceProvider).fetchProfile();
          if (!mounted) return;
          _update(
            service,
            (c) => c.copyWith(
              accountName: profile.displayName,
              avatarUrl: profile.imageUrl,
            ),
          );
          break;
        case MusicProviderService.appleMusic:
          // Reading the Apple Music account needs the developer token that
          // only the auth bridge holds, so there is nothing to fetch here.
          _update(service, (c) => c.copyWith(accountName: 'Apple Music'));
          break;
      }
    } catch (_) {
      // Leave the connection intact and unannotated.
    }
  }

  void _setPrimaryIfUnset(MusicProviderService service) {
    if (state.primary == null) state = state.withPrimary(service);
  }

  void _update(
    MusicProviderService service,
    MusicServiceConnection Function(MusicServiceConnection) transform,
  ) {
    state = state.withService(transform(state[service]));
  }
}

final musicConnectionsProvider =
    StateNotifierProvider<MusicConnectionsController, MusicConnectionsState>(
  MusicConnectionsController.new,
);

// --- Library reads ---

/// The connected user's Spotify playlists.
final spotifyMyPlaylistsProvider =
    FutureProvider<List<SpotifyPlaylist>>((ref) async {
  final connections = ref.watch(musicConnectionsProvider);
  if (!connections.isConnected(MusicProviderService.spotify)) return const [];
  return ref.watch(spotifyApiServiceProvider).fetchMyPlaylists();
});

/// The connected user's YouTube Music playlists.
final youTubeMusicPlaylistsProvider =
    FutureProvider<List<YouTubeMusicPlaylist>>((ref) async {
  final connections = ref.watch(musicConnectionsProvider);
  if (!connections.isConnected(MusicProviderService.youtubeMusic)) {
    return const [];
  }
  return ref.watch(youTubeMusicApiServiceProvider).fetchMyPlaylists();
});
