import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main/domain/app_models.dart';
import '../data/apple_music_auth_service.dart';
import '../data/apple_music_config.dart';
import '../data/cover_art_lookup_service.dart';
import '../data/media_session_service.dart';
import '../data/music_token_store.dart';
import '../data/pkce_oauth_client.dart';
import '../data/spotify_api_service.dart';
import '../data/spotify_app_remote_service.dart';
import '../data/spotify_config.dart';
import '../data/youtube_music_api_service.dart';
import '../data/youtube_music_config.dart';
import '../domain/music_brand.dart';
import '../domain/music_feature_flags.dart';

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

/// Cover art by name, for tracks that arrived with no URL to share.
///
/// The media session — the path everyone is on — reports artwork as bytes
/// that cannot leave this phone. This is how a Pulse still gets a cover
/// another device can fetch, with no account behind it.
final coverArtLookupProvider = Provider<CoverArtLookupService>((ref) {
  return CoverArtLookupService();
});

/// The bridge to the Spotify app on this phone.
///
/// Root-scoped on purpose: the connection has to outlive the player card, or
/// navigating away from the workout screen would tear down the link to the
/// process that is actually producing sound.
final spotifyAppRemoteServiceProvider =
    Provider<SpotifyAppRemoteService>((ref) {
  final service = SpotifyAppRemoteService();
  ref.onDispose(service.disconnect);
  return service;
});

/// The phone's own media session — what is playing, and the buttons to
/// drive it — with no account behind it.
///
/// Root-scoped for the same reason as the App Remote bridge: it holds a single
/// platform-channel subscription that both the music island and the player
/// card read from, and opening that channel twice leaves one of them silent.
final mediaSessionServiceProvider = Provider<MediaSessionService>((ref) {
  return MediaSessionService();
});

/// Whether Android will let us read the phone's media session.
///
/// Notification access is granted on a system screen: there is no runtime
/// dialog to await, no result handed back to the caller, and no callback when
/// the switch is flipped. Coming back to the foreground is therefore the only
/// moment the answer can be re-read, and this re-reads it there.
///
/// App-wide rather than owned by the connect sheet. Everything that depends on
/// the media session watches this, so granting the toggle lights the feature up
/// on return instead of on the next cold start — which is what it used to take.
class MediaSessionPermissionController extends StateNotifier<bool>
    with WidgetsBindingObserver {
  MediaSessionPermissionController(this._service) : super(false) {
    WidgetsBinding.instance.addObserver(this);
    unawaited(refresh());
  }

  final MediaSessionService _service;

  /// Re-reads the switch. Safe to call at any time.
  Future<void> refresh() async {
    final granted = await _service.hasPermission();
    // The container may be gone by the time the channel answers.
    if (!mounted) return;
    state = granted;
  }

  // The parameter shadows StateNotifier's own `state`, which is why nothing in
  // here touches it — the name is fixed by the overridden method.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

/// Starts false and flips to the truth a moment later, rather than exposing an
/// AsyncValue: every reader of this is answering "can we show music yet", and
/// "not yet, still asking" and "no" call for exactly the same UI.
final mediaSessionPermissionProvider =
    StateNotifierProvider<MediaSessionPermissionController, bool>((ref) {
  return MediaSessionPermissionController(
    ref.watch(mediaSessionServiceProvider),
  );
});

/// Whether the app has any way at all to see what is playing.
///
/// Two independent sources, and no music UI may gate on only one of them: a
/// linked account, or notification access to whatever this phone is already
/// playing. The second needs no sign-in, which is the entire reason it exists —
/// gating the player on connections alone hid it from every user who took that
/// route, which is most of them.
final hasMusicSourceProvider = Provider<bool>((ref) {
  if (ref.watch(mediaSessionPermissionProvider)) return true;
  return ref.watch(musicAccountsEnabledProvider) &&
      ref.watch(musicConnectionsProvider).hasAnyConnection;
});

/// [kMusicAccountsEnabled], read through the container.
///
/// The const is the product decision; this is how the app asks about it. Going
/// through a provider means the account paths — OAuth, the Web API, the App
/// Remote bridge, the library sheet — can still be exercised under test with
/// one override, instead of their coverage being deleted along with the UI
/// that reaches them. Nothing in the app overrides it.
final musicAccountsEnabledProvider =
    Provider<bool>((ref) => kMusicAccountsEnabled);

final youTubeMusicApiServiceProvider = Provider<YouTubeMusicApiService>((ref) {
  return YouTubeMusicApiService(
      authService: ref.watch(youTubeMusicAuthProvider));
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
      case MusicProviderService.device:
        // Not a thing that can be connected — it is what plays when nothing
        // is. It never reaches the connect sheet, so this only answers a
        // stray lookup.
        return false;
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
      case MusicProviderService.device:
        return 'Music playing on this phone is read through Android, not '
            'connected to an account.';
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
        for (final service in MusicProviderService.connectable)
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
  MusicConnectionsController(this._ref)
      : super(MusicConnectionsState.initial()) {
    _restore();
  }

  final Ref _ref;

  /// Rehydrates previously connected accounts on app start.
  Future<void> _restore() async {
    // Nothing to rehydrate while accounts are off, and asking anyway would mean
    // a secure-storage read per service on every cold start for an answer
    // nothing is allowed to act on.
    if (!_ref.read(musicAccountsEnabledProvider)) return;
    for (final service in MusicProviderService.connectable) {
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
    // `device` has no auth flow to reach. Refused here rather than in the
    // switch below so it can never be marked connected on the way through.
    if (service == MusicProviderService.device) return;

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
        case MusicProviderService.device:
          // Unreachable: guarded above.
          return;
      }
      if (!mounted) return;
      _update(service, (c) => c.copyWith(isConnected: true, isBusy: false));
      _setPrimaryIfUnset(service);
      await _loadAccount(service);
    } on MusicAuthException catch (e) {
      if (!mounted) return;
      _update(
          service, (c) => c.copyWith(isBusy: false, errorMessage: e.message));
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
      case MusicProviderService.device:
        // A real invariant, not a gap: there is no token store behind the
        // phone's own media session, so anything asking this one for an
        // account has walked `values` where it meant `connectable`.
        throw StateError('MusicProviderService.device has no account to '
            'authenticate — iterate MusicProviderService.connectable.');
    }
  }

  /// Account details are decoration — a failure here must not drop a
  /// connection that is otherwise working.
  Future<void> _loadAccount(MusicProviderService service) async {
    try {
      switch (service) {
        case MusicProviderService.spotify:
          final profile =
              await _ref.read(spotifyApiServiceProvider).fetchProfile();
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
        case MusicProviderService.device:
          // No account behind it, so nothing to name.
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
