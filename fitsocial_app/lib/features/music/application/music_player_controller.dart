import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main/domain/app_models.dart';
import '../data/spotify_api_service.dart';
import '../data/spotify_app_remote_service.dart';
import '../domain/music_playback.dart';
import 'music_providers.dart';

/// How the player is reaching Spotify.
///
/// The two are not interchangeable and the UI has to be able to tell them
/// apart: App Remote can *start* music on this phone, the Web API can only
/// steer a session some other device already has running.
enum MusicPlaybackTransport {
  /// Nothing connected, or a service with no remote-control API at all.
  none,

  /// Spotify's App Remote bridge to the installed Spotify app. Playback
  /// starts here.
  appRemote,

  /// The Spotify Web API, driving a Spotify Connect device elsewhere.
  webApi,
}

class MusicPlayerState {
  const MusicPlayerState({
    this.service,
    this.snapshot,
    this.transport = MusicPlaybackTransport.none,
    this.isLoading = false,
    this.message,
  });

  /// The connected service the transport acts on, or null when nothing is
  /// connected — the player card is hidden in that case.
  final MusicProviderService? service;

  final MusicPlayerSnapshot? snapshot;
  final MusicPlaybackTransport transport;
  final bool isLoading;

  /// A user-fixable explanation: Spotify app missing, no active device,
  /// Premium required, or a service whose playback API isn't public.
  final String? message;

  bool get hasTrack => snapshot?.hasTrack ?? false;
  bool get isPlaying => snapshot?.isPlaying ?? false;
  bool get shuffleEnabled => snapshot?.shuffleEnabled ?? false;
  MusicRepeatMode get repeatMode => snapshot?.repeatMode ?? MusicRepeatMode.off;

  /// Whether the transport buttons should respond.
  bool get canControl =>
      transport != MusicPlaybackTransport.none && snapshot != null;

  /// Whether picking a playlist can actually start it. App Remote always can;
  /// the Web API needs a live device, which it discovers when asked.
  bool get canStartPlayback => transport != MusicPlaybackTransport.none;

  MusicPlayerState copyWith({
    MusicProviderService? service,
    MusicPlayerSnapshot? snapshot,
    MusicPlaybackTransport? transport,
    bool? isLoading,
    String? message,
    bool clearMessage = false,
    bool clearSnapshot = false,
  }) {
    return MusicPlayerState(
      service: service ?? this.service,
      snapshot: clearSnapshot ? null : (snapshot ?? this.snapshot),
      transport: transport ?? this.transport,
      isLoading: isLoading ?? this.isLoading,
      message: clearMessage ? null : (message ?? this.message),
    );
  }
}

/// Drives the transport controls against the connected service's player.
///
/// Prefers App Remote, which talks to the Spotify app installed on this phone
/// and is the only path that can start music from inside FitSocial. When that
/// bridge is unavailable — no Spotify app, or a free account — it falls back to
/// the Web API, which can still control a Spotify Connect device the user has
/// running elsewhere.
///
/// Commands are applied optimistically and reconciled with the next state
/// update, because a round trip takes long enough that a button which waits
/// for it feels broken.
class MusicPlayerController extends StateNotifier<MusicPlayerState> {
  MusicPlayerController({
    required SpotifyApiService spotify,
    required SpotifyAppRemoteService appRemote,
    required MusicConnectionsState connections,
  })  : _spotify = spotify,
        _appRemote = appRemote,
        _connections = connections,
        super(const MusicPlayerState()) {
    _start();
  }

  final SpotifyApiService _spotify;
  final SpotifyAppRemoteService _appRemote;
  final MusicConnectionsState _connections;

  Timer? _ticker;
  int _ticksSincePoll = 0;
  StreamSubscription<MusicPlayerSnapshot>? _remoteStates;

  /// The artwork reference the last fetch was issued for, so the same track
  /// does not re-request its cover on every state push.
  String? _artUriInFlight;

  /// The track URI the last shareable-artwork lookup was issued for. Separate
  /// from [_artUriInFlight] because the two are keyed differently: bytes belong
  /// to an image reference, the URL belongs to the track.
  String? _artUrlInFlight;

  /// Spotify takes a moment to acknowledge a seek or a volume change, so an
  /// update arriving straight after one still reports the *old* value.
  /// Honouring it would snap the slider back under the user's finger. These
  /// deadlines hold the local value until the service has caught up.
  DateTime? _holdPositionUntil;
  DateTime? _holdVolumeUntil;

  static const _pollEvery = 5;
  static const _holdAfterCommand = Duration(seconds: 3);

  void _start() {
    final active = _connections.activeConnection;
    if (active == null) {
      state = const MusicPlayerState();
      return;
    }

    if (active.service != MusicProviderService.spotify) {
      state = MusicPlayerState(
        service: active.service,
        message: '${active.service.label} has no public remote-playback API, '
            'so keep playback running in its own app. Your playlists still '
            'show up here.',
      );
      return;
    }

    // Start on the Web API and upgrade to App Remote when it lands, rather
    // than waiting for it. Bringing up the native bridge means waking another
    // app and can take seconds or time out entirely; blocking on it would
    // leave the card blank that whole time, when a plain HTTP read could have
    // filled it in immediately.
    state = MusicPlayerState(
      service: active.service,
      transport: MusicPlaybackTransport.webApi,
    );
    unawaited(refresh());
    unawaited(_upgradeToAppRemote());

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  /// Brings up the App Remote bridge in the background and hands it the
  /// transport once it is live.
  Future<void> _upgradeToAppRemote() async {
    try {
      await _appRemote.ensureConnected();
      if (!mounted) return;
      _listenToAppRemote();
      state = state.copyWith(
        transport: MusicPlaybackTransport.appRemote,
        clearMessage: true,
      );
    } on SpotifyRemoteException catch (e) {
      if (!mounted) return;
      // Not a dead end: a Connect device elsewhere can still be driven. Only
      // explain the missing bridge when nothing is playing — saying "install
      // Spotify" over a working session would be noise about a capability the
      // user is not currently reaching for.
      final isIdle = state.snapshot == null;
      state = state.copyWith(
        transport: MusicPlaybackTransport.webApi,
        message: isIdle ? e.message : null,
        clearMessage: !isIdle,
      );
    }
  }

  void _listenToAppRemote() {
    _remoteStates?.cancel();
    _remoteStates = _appRemote.playerStates().listen(
      (snapshot) {
        if (!mounted) return;
        state = state.copyWith(
          snapshot: _keepLocalEdits(snapshot),
          transport: MusicPlaybackTransport.appRemote,
          clearMessage: true,
        );
        unawaited(_loadArtwork(snapshot.track));
        unawaited(_loadShareableArtwork(snapshot.track));
      },
      onError: (Object error) {
        if (!mounted) return;
        // The bridge dropped. Keep the last known track on screen rather than
        // blanking the card mid-workout, and let the Web API take over.
        state = state.copyWith(
          transport: MusicPlaybackTransport.webApi,
          message: error is SpotifyRemoteException
              ? error.message
              : 'Lost the connection to Spotify.',
        );
        unawaited(refresh());
      },
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _remoteStates?.cancel();
    // Deliberately does *not* disconnect App Remote: the user leaving this
    // screen is not a reason to stop their music. The bridge is owned by a
    // root-scoped provider and torn down on sign-out instead.
    super.dispose();
  }

  /// Advances the progress bar locally between updates so it moves at one
  /// second per second, and polls the Web API when that is the live transport.
  void _tick() {
    if (state.transport == MusicPlaybackTransport.webApi) {
      _ticksSincePoll++;
      if (_ticksSincePoll >= _pollEvery) {
        _ticksSincePoll = 0;
        unawaited(refresh());
        return;
      }
    }

    final snapshot = state.snapshot;
    final track = snapshot?.track;
    if (snapshot == null || track == null || !snapshot.isPlaying) return;
    if (track.position >= track.duration) return;

    state = state.copyWith(
      snapshot: snapshot.copyWith(
        track: track.copyWith(
          position: track.position + const Duration(seconds: 1),
        ),
      ),
    );
  }

  /// Resolves App Remote cover art, which arrives as an opaque URI rather
  /// than a fetchable URL.
  Future<void> _loadArtwork(NowPlayingTrack? track) async {
    final uri = track?.albumArtUri;
    if (uri == null || uri.isEmpty || uri == _artUriInFlight) return;
    _artUriInFlight = uri;

    final bytes = await _appRemote.albumArt(uri);
    if (!mounted || bytes == null) return;

    // The track may have moved on while the bytes were in flight; applying
    // them then would put the wrong cover on screen.
    final current = state.snapshot;
    if (current?.track?.albumArtUri != uri) return;
    state = state.copyWith(
      snapshot: current!.copyWith(
        track: current.track!.copyWith(albumArtBytes: bytes),
      ),
    );
  }

  /// Looks up an https cover-art URL for a track App Remote reported.
  ///
  /// The bytes [_loadArtwork] resolves can only ever be drawn here. Anything
  /// that leaves this phone — a music Pulse, a presence row a friend sees —
  /// needs a URL their device can fetch, and the Web API is where that comes
  /// from. Without this, everything shared from the App Remote path names the
  /// song but carries no cover.
  Future<void> _loadShareableArtwork(NowPlayingTrack? track) async {
    // The Web API path already reports a URL with the track itself.
    if (track == null || track.albumArtUrl != null) return;

    final uri = track.uri;
    if (uri == null || uri.isEmpty || uri == _artUrlInFlight) return;
    _artUrlInFlight = uri;

    final String? url;
    try {
      url = await _spotify.fetchTrackArtworkUrl(uri);
    } catch (_) {
      // Artwork is decoration on a card whose job is playback: an expired
      // token or a dropped connection here is not worth a message, and the
      // next track change tries again.
      return;
    }
    if (!mounted || url == null) return;

    // The track may have moved on while the lookup was in flight.
    final current = state.snapshot;
    if (current?.track?.uri != uri) return;
    state = state.copyWith(
      snapshot: current!.copyWith(
        track: current.track!.copyWith(albumArtUrl: url),
      ),
    );
  }

  /// Pulls Web API player state. No-op on the App Remote path, which pushes.
  Future<void> refresh() async {
    if (state.service != MusicProviderService.spotify) return;
    if (state.transport == MusicPlaybackTransport.appRemote) return;
    try {
      final snapshot = await _spotify.fetchPlayerState();
      if (!mounted) return;
      if (snapshot == null) {
        state = state.copyWith(
          clearSnapshot: true,
          message: 'Nothing is playing. Pick a playlist below, or start a '
              'track in Spotify and the controls here take over.',
        );
        return;
      }
      state = state.copyWith(
        snapshot: _keepLocalEdits(snapshot),
        clearMessage: true,
      );
    } on SpotifyPlaybackUnavailable catch (e) {
      if (mounted) state = state.copyWith(message: e.message);
    } on SpotifyApiException catch (e) {
      if (mounted) state = state.copyWith(message: e.message);
    }
  }

  /// Overlays values the user just set onto a freshly reported snapshot, for
  /// as long as the service might still be reporting the pre-command state.
  MusicPlayerSnapshot _keepLocalEdits(MusicPlayerSnapshot incoming) {
    final local = state.snapshot;
    if (local == null) return incoming;

    final now = DateTime.now();
    var result = incoming;

    final holdPosition = _holdPositionUntil;
    final localTrack = local.track;
    final incomingTrack = incoming.track;
    // Only hold the position while the same track is still loaded — once it
    // has changed, the reported position is the truth.
    if (holdPosition != null &&
        now.isBefore(holdPosition) &&
        localTrack != null &&
        incomingTrack != null &&
        incomingTrack.isSameTrackAs(localTrack)) {
      result = result.copyWith(
        track: incomingTrack.copyWith(position: localTrack.position),
      );
    }

    // Cover art resolved for a track that is still playing should survive an
    // update that carries only the URI, or the art flickers on every push.
    final resolvedArt = localTrack?.albumArtBytes;
    final carried = result.track;
    if (resolvedArt != null &&
        carried != null &&
        carried.albumArtBytes == null &&
        carried.albumArtUri == localTrack?.albumArtUri) {
      result = result.copyWith(
        track: carried.copyWith(albumArtBytes: resolvedArt),
      );
    }

    // Same for the looked-up cover URL, keyed on the track rather than on the
    // image reference — dropping it would send the sticker back to its
    // placeholder on the next push and re-issue the lookup on the one after.
    final resolvedArtUrl = localTrack?.albumArtUrl;
    final carriedTrack = result.track;
    if (resolvedArtUrl != null &&
        carriedTrack != null &&
        carriedTrack.albumArtUrl == null &&
        carriedTrack.uri != null &&
        carriedTrack.uri == localTrack?.uri) {
      result = result.copyWith(
        track: carriedTrack.copyWith(albumArtUrl: resolvedArtUrl),
      );
    }

    final holdVolume = _holdVolumeUntil;
    if (holdVolume != null &&
        now.isBefore(holdVolume) &&
        local.volumePercent != null) {
      result = result.copyWith(volumePercent: local.volumePercent);
    }

    return result;
  }

  // --- Starting playback ---

  /// Starts a playlist, album or artist by Spotify URI.
  ///
  /// This is the path that makes the app a music player rather than a remote:
  /// on App Remote it wakes the Spotify app and hands it [contextUri]; on the
  /// Web API it finds a live device, moves the session there, and starts the
  /// context. Reports what to fix when neither can be done.
  Future<void> playContext(String contextUri) async {
    if (contextUri.isEmpty) return;
    state = state.copyWith(isLoading: true, clearMessage: true);

    try {
      switch (state.transport) {
        case MusicPlaybackTransport.appRemote:
          await _appRemote.play(contextUri);
        case MusicPlaybackTransport.webApi:
          await _startOverWebApi(contextUri);
        case MusicPlaybackTransport.none:
          // The bridge may have come back since the screen opened — one retry
          // is cheaper than telling the user to reconnect by hand.
          await _appRemote.ensureConnected();
          if (!mounted) return;
          _listenToAppRemote();
          state = state.copyWith(transport: MusicPlaybackTransport.appRemote);
          await _appRemote.play(contextUri);
      }
      if (!mounted) return;
      state = state.copyWith(isLoading: false, clearMessage: true);
      // App Remote pushes the new track on its own; the Web API does not.
      if (state.transport == MusicPlaybackTransport.webApi) await refresh();
    } on SpotifyRemoteException catch (e) {
      if (mounted) state = state.copyWith(isLoading: false, message: e.message);
    } on SpotifyPlaybackUnavailable catch (e) {
      if (mounted) state = state.copyWith(isLoading: false, message: e.message);
    } on SpotifyApiException catch (e) {
      if (mounted) state = state.copyWith(isLoading: false, message: e.message);
    }
  }

  /// Web API playback needs somewhere to play. Picks the active device, or
  /// the first usable one, and moves the session to it first.
  Future<void> _startOverWebApi(String contextUri) async {
    final devices = await _spotify.fetchDevices();
    final playable = devices.where((d) => d.isPlayable).toList(growable: false);
    if (playable.isEmpty) {
      throw const SpotifyPlaybackUnavailable(
        'No Spotify device is available. Open the Spotify app on this phone '
        'or another device, then try again.',
      );
    }

    final target = playable.firstWhere(
      (d) => d.isActive,
      orElse: () => playable.first,
    );
    if (!target.isActive) {
      await _spotify.transferPlayback(target.id, andPlay: false);
    }
    await _spotify.playContext(contextUri, deviceId: target.id);
  }

  // --- Transport ---

  Future<void> togglePlayPause() async {
    final snapshot = state.snapshot;
    if (snapshot == null) return;

    final wantsPlay = !snapshot.isPlaying;
    state = state.copyWith(
      snapshot: snapshot.copyWith(isPlaying: wantsPlay),
      clearMessage: true,
    );

    await _command(
      () async {
        if (state.transport == MusicPlaybackTransport.appRemote) {
          return wantsPlay ? _appRemote.resume() : _appRemote.pause();
        }
        return wantsPlay ? _spotify.play() : _spotify.pause();
      },
      onFailure: () => snapshot,
    );
  }

  Future<void> next() => _skip(forward: true);

  Future<void> previous() => _skip(forward: false);

  Future<void> _skip({required bool forward}) async {
    final snapshot = state.snapshot;
    if (snapshot == null) return;

    // Skipping changes the track, so there is nothing sensible to guess at —
    // clear the position and let the follow-up update fill in the new track.
    // Any pending seek hold is void for the same reason.
    _holdPositionUntil = null;
    final track = snapshot.track;
    if (track != null) {
      state = state.copyWith(
        snapshot: snapshot.copyWith(
          track: track.copyWith(position: Duration.zero),
        ),
        clearMessage: true,
      );
    }

    await _command(
      () {
        if (state.transport == MusicPlaybackTransport.appRemote) {
          return forward ? _appRemote.skipNext() : _appRemote.skipPrevious();
        }
        return forward ? _spotify.nextTrack() : _spotify.previousTrack();
      },
      onFailure: () => snapshot,
    );
    if (mounted) await refresh();
  }

  Future<void> toggleShuffle() async {
    final snapshot = state.snapshot;
    if (snapshot == null) return;

    final wanted = !snapshot.shuffleEnabled;
    state = state.copyWith(
      snapshot: snapshot.copyWith(shuffleEnabled: wanted),
      clearMessage: true,
    );

    await _command(
      () => state.transport == MusicPlaybackTransport.appRemote
          ? _appRemote.setShuffle(wanted)
          : _spotify.setShuffle(wanted),
      onFailure: () => snapshot,
    );
  }

  Future<void> cycleRepeat() async {
    final snapshot = state.snapshot;
    if (snapshot == null) return;

    final wanted = snapshot.repeatMode.next;
    state = state.copyWith(
      snapshot: snapshot.copyWith(repeatMode: wanted),
      clearMessage: true,
    );

    await _command(
      () => state.transport == MusicPlaybackTransport.appRemote
          ? _appRemote.setRepeat(wanted)
          : _spotify.setRepeat(wanted),
      onFailure: () => snapshot,
    );
  }

  /// Jumps to [position] in the current track.
  Future<void> seek(Duration position) async {
    final snapshot = state.snapshot;
    final track = snapshot?.track;
    if (snapshot == null || track == null) return;

    final target = position < Duration.zero
        ? Duration.zero
        : (position > track.duration ? track.duration : position);

    state = state.copyWith(
      snapshot: snapshot.copyWith(track: track.copyWith(position: target)),
      clearMessage: true,
    );
    _holdPositionUntil = DateTime.now().add(_holdAfterCommand);

    await _command(
      () => state.transport == MusicPlaybackTransport.appRemote
          ? _appRemote.seek(target)
          : _spotify.seek(target),
      onFailure: () {
        _holdPositionUntil = null;
        return snapshot;
      },
    );
  }

  /// Sets output volume on the active device, 0-100.
  ///
  /// Web API only: App Remote has no volume channel, because on the phone
  /// itself that is the hardware media stream's job.
  Future<void> setVolume(int percent) async {
    final snapshot = state.snapshot;
    if (snapshot == null || !snapshot.canSetVolume) return;

    final target = percent.clamp(0, 100);
    state = state.copyWith(
      snapshot: snapshot.copyWith(volumePercent: target),
      clearMessage: true,
    );
    _holdVolumeUntil = DateTime.now().add(_holdAfterCommand);

    await _command(
      () => _spotify.setVolume(target),
      onFailure: () {
        _holdVolumeUntil = null;
        return snapshot;
      },
    );
  }

  /// Runs a transport command, rolling the optimistic update back if the
  /// service rejects it.
  Future<void> _command(
    Future<void> Function() action, {
    required MusicPlayerSnapshot Function() onFailure,
  }) async {
    try {
      await action();
    } on SpotifyRemoteException catch (e) {
      if (mounted) {
        state = state.copyWith(snapshot: onFailure(), message: e.message);
      }
    } on SpotifyPlaybackUnavailable catch (e) {
      if (mounted) {
        state = state.copyWith(snapshot: onFailure(), message: e.message);
      }
    } on SpotifyApiException catch (e) {
      if (mounted) {
        state = state.copyWith(snapshot: onFailure(), message: e.message);
      }
    }
  }
}

/// Auto-disposed so the ticker stops the moment the player leaves the tree.
/// The App Remote bridge itself is root-scoped and survives, so music keeps
/// playing when the user navigates away.
final musicPlayerControllerProvider = StateNotifierProvider.autoDispose<
    MusicPlayerController, MusicPlayerState>((ref) {
  return MusicPlayerController(
    spotify: ref.watch(spotifyApiServiceProvider),
    appRemote: ref.watch(spotifyAppRemoteServiceProvider),
    connections: ref.watch(musicConnectionsProvider),
  );
});
