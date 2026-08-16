import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main/domain/app_models.dart';
import '../data/spotify_app_remote_service.dart';
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
/// The cost of that is why this exists at all. App Remote is push-based —
/// Spotify emits on every play, pause, skip and seek — so the common path
/// costs no polling whatsoever. Only a Web-API-only session falls back to
/// asking, and then at [kPresencePollInterval] rather than at 1 Hz.
class MusicPresenceController extends StateNotifier<MusicPresence> {
  MusicPresenceController({
    required SpotifyAppRemoteService appRemote,
    required MusicConnectionsState connections,
    required this.readWebApiSnapshot,
  })  : _appRemote = appRemote,
        super(MusicPresence.none) {
    _start(connections);
  }

  final SpotifyAppRemoteService _appRemote;

  /// Injected rather than reached for, so the fallback path can be exercised
  /// without a Spotify account.
  final Future<MusicPresence> Function() readWebApiSnapshot;

  StreamSubscription<void>? _remoteStates;
  Timer? _poll;

  Future<void> _start(MusicConnectionsState connections) async {
    if (!connections.isConnected(MusicProviderService.spotify)) {
      debugPrint('Music island: no Spotify connection — island stays hidden.');
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
    _poll?.cancel();
    super.dispose();
  }
}

final musicPresenceControllerProvider =
    StateNotifierProvider<MusicPresenceController, MusicPresence>((ref) {
  final connections = ref.watch(musicConnectionsProvider);
  final api = ref.watch(spotifyApiServiceProvider);

  return MusicPresenceController(
    appRemote: ref.watch(spotifyAppRemoteServiceProvider),
    connections: connections,
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
