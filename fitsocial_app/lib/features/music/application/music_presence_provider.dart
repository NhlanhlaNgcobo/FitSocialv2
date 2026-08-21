import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main/domain/app_models.dart';
import '../data/media_session_service.dart';
import '../data/spotify_app_remote_service.dart';
import '../domain/music_feature_flags.dart';
import '../domain/music_presence.dart';
import 'music_providers.dart';

/// How often the Web API fallback asks what is playing.
///
/// Twenty seconds, not the one second [MusicPlayerController] uses. That
/// controller drives a progress bar someone is looking at; this only decides
/// whether a pill is on screen, and it runs for the whole life of the app. The
/// full-rate controller still exists — it is mounted when the island is
/// expanded and disposed when it collapses.
const Duration kPresencePollInterval = Duration(seconds: 20);

/// What is playing, app-wide.
///
/// Root-scoped on purpose, unlike [musicPlayerControllerProvider]: the island
/// sits above every screen, so this has to outlive all of them.
///
/// The cost of that is why the source order matters. Both push-based paths —
/// the phone's media session and Spotify's App Remote — emit on every play,
/// pause, skip and seek, so the common path costs no polling whatsoever. Only
/// a Web-API-only session falls back to asking, and then at
/// [kPresencePollInterval] rather than at 1 Hz.
///
/// The media session is tried first because it is the only source that needs
/// no account: it reads whatever the phone is playing, in any app, for any
/// user. App Remote is kept behind it for the Spotify accounts that are on the
/// developer allowlist, where it can do more.
class MusicPresenceController extends StateNotifier<MusicPresence> {
  MusicPresenceController({
    required MediaSessionService session,
    required SpotifyAppRemoteService appRemote,
    required MusicConnectionsState connections,
    required bool mediaSessionGranted,
    required bool accountsEnabled,
    required this.readWebApiSnapshot,
  })  : _session = session,
        _appRemote = appRemote,
        _accountsEnabled = accountsEnabled,
        super(MusicPresence.none) {
    _start(connections, mediaSessionGranted);
  }

  final MediaSessionService _session;
  final SpotifyAppRemoteService _appRemote;

  /// Whether the Spotify fallbacks are part of the product. See
  /// [kMusicAccountsEnabled].
  final bool _accountsEnabled;

  /// Injected rather than reached for, so the fallback path can be exercised
  /// without a Spotify account.
  final Future<MusicPresence> Function() readWebApiSnapshot;

  StreamSubscription<void>? _remoteStates;
  StreamSubscription<MediaSessionState>? _sessionStates;
  Timer? _poll;

  Future<void> _start(
    MusicConnectionsState connections,
    bool mediaSessionGranted,
  ) async {
    // No account, no quota, works with every music app on the phone — so this
    // comes first, and when it is available nothing else is needed.
    //
    // Handed in rather than read here. This controller is root-scoped and
    // built once; asking the channel itself meant the answer was frozen at
    // whatever it was on the first frame, so a user who granted notification
    // access got nothing until the next cold start. Watching the permission
    // provider rebuilds this the moment the switch flips.
    if (mediaSessionGranted) {
      debugPrint('Music island: watching the phone media session.');
      _listenToMediaSession();
      return;
    }

    if (!_accountsEnabled) {
      debugPrint('Music island: no media-session permission, and accounts are '
          'off — island stays hidden until notification access is granted.');
      return;
    }

    if (!connections.isConnected(MusicProviderService.spotify)) {
      debugPrint('Music island: no media-session permission and no Spotify '
          'connection — island stays hidden.');
      return;
    }

    try {
      await _appRemote.ensureConnected();
      if (!mounted) return;
      debugPrint('Music island: watching App Remote for what is playing.');
      _listenToAppRemote();
    } catch (error) {
      debugPrint('Music island: no App Remote bridge ($error) — polling '
          'the Web API every ${kPresencePollInterval.inSeconds}s instead.');
      // No bridge — Spotify not installed, or playback happening on a Connect
      // device elsewhere. Fall back to asking, slowly.
      if (mounted) _startPolling();
    }
  }

  void _listenToMediaSession() {
    _poll?.cancel();
    _poll = null;
    _sessionStates?.cancel();
    _sessionStates = _session.states().listen(
      (event) => _emit(MusicPresence.fromSnapshot(event.snapshot)),
      onError: (Object error) {
        // The channel dropped. Nothing to fall back to that would not need an
        // account, so the island goes rather than showing a stale track.
        debugPrint('Music island: media session stream failed ($error).');
        _emit(MusicPresence.none);
      },
    );
  }

  void _listenToAppRemote() {
    _poll?.cancel();
    _poll = null;
    _remoteStates?.cancel();
    _remoteStates = _appRemote.playerStates().listen(
      (snapshot) => _emit(MusicPresence.fromSnapshot(snapshot)),
      onError: (Object error) {
        // The bridge dropped mid-session. Keep whatever was last on screen and
        // let the slow poll take over rather than blanking the island.
        debugPrint('Music island: App Remote stream failed ($error).');
        if (mounted) _startPolling();
      },
    );
  }

  void _startPolling() {
    _poll?.cancel();
    unawaited(_pollOnce());
    _poll = Timer.periodic(kPresencePollInterval, (_) => _pollOnce());
  }

  Future<void> _pollOnce() async {
    try {
      final presence = await readWebApiSnapshot();
      _emit(presence);
    } catch (error) {
      debugPrint('Music island: could not read what is playing ($error).');
    }
  }

  /// Drops an emission that says nothing new.
  ///
  /// App Remote fires on every seek, several times a second while scrubbing.
  /// Passing each one through would rebuild an overlay that sits above every
  /// screen in the app.
  void _emit(MusicPresence next) {
    if (!mounted) return;
    if (state.isSameAs(next)) return;
    // The one line worth having in a bug report: whether the island should be
    // on screen, and what it thinks is playing.
    debugPrint('Music island: live=${next.isLive} playing=${next.isPlaying} '
        'track="${next.title}"');
    state = next;
  }

  @override
  void dispose() {
    _remoteStates?.cancel();
    _sessionStates?.cancel();
    _poll?.cancel();
    super.dispose();
  }
}

final musicPresenceControllerProvider =
    StateNotifierProvider<MusicPresenceController, MusicPresence>((ref) {
  final connections = ref.watch(musicConnectionsProvider);
  final api = ref.watch(spotifyApiServiceProvider);

  return MusicPresenceController(
    session: ref.watch(mediaSessionServiceProvider),
    appRemote: ref.watch(spotifyAppRemoteServiceProvider),
    connections: connections,
    mediaSessionGranted: ref.watch(mediaSessionPermissionProvider),
    accountsEnabled: ref.watch(musicAccountsEnabledProvider),
    readWebApiSnapshot: () async =>
        MusicPresence.fromSnapshot(await api.fetchPlayerState()),
  );
});

/// What the island actually watches.
///
/// A plain read over [musicPresenceControllerProvider], for one reason: a
/// StateNotifierProvider can only be overridden with its own notifier type,
/// and that notifier needs a live Spotify bridge. Reading through a Provider
/// lets a test state what is playing in one line instead of standing up a
/// music service to say it.
final musicPresenceProvider = Provider<MusicPresence>(
  (ref) => ref.watch(musicPresenceControllerProvider),
);
