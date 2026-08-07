import 'dart:async';

import 'package:flutter/services.dart';
import 'package:spotify_sdk/models/image_uri.dart';
import 'package:spotify_sdk/models/player_state.dart' as remote;
import 'package:spotify_sdk/models/track.dart' as remote;
// The SDK ships two unrelated enums both called RepeatMode: this one, carried
// *inside* PlayerState, and the one `setRepeatMode` accepts (exported from
// spotify_sdk.dart and used unprefixed below). Reading and writing repeat go
// through different types, so both have to be in scope.
import 'package:spotify_sdk/models/player_options.dart' as options;
import 'package:spotify_sdk/spotify_sdk.dart';

import '../../main/domain/app_models.dart';
import '../domain/music_playback.dart';
import 'spotify_config.dart';

/// Why App Remote could not be used, in terms the UI can put in front of a
/// user. Each of these is fixable by the user; none of them is a bug.
enum SpotifyRemoteBlock {
  /// The Spotify app is not installed on this device. App Remote is a bridge
  /// to that app — without it there is nothing to bridge to.
  notInstalled,

  /// Spotify is installed but refused the connection. In practice this is a
  /// free account (App Remote is Premium-only) or an account that is not on
  /// the dashboard's allowlist while the app is in development mode.
  notAuthorized,

  /// Connected once and then dropped — usually the user force-quit Spotify.
  disconnected,

  /// Anything else, kept verbatim so a real failure is not disguised.
  unknown,
}

extension SpotifyRemoteBlockMessage on SpotifyRemoteBlock {
  String get message {
    switch (this) {
      case SpotifyRemoteBlock.notInstalled:
        return 'Install the Spotify app to play music here. FitSocial drives '
            'playback through it.';
      case SpotifyRemoteBlock.notAuthorized:
        return 'Spotify would not authorise playback. In-app playback needs a '
            'Premium account.';
      case SpotifyRemoteBlock.disconnected:
        return 'Lost the connection to Spotify. Tap play to reconnect.';
      case SpotifyRemoteBlock.unknown:
        return 'Could not reach the Spotify app.';
    }
  }
}

/// Thrown when an App Remote call cannot be served. Carries a [block] so the
/// player can decide between showing a hint and falling back to the Web API.
class SpotifyRemoteException implements Exception {
  const SpotifyRemoteException(this.block, [this.detail]);

  final SpotifyRemoteBlock block;

  /// The platform's own words, when it gave any. Appended to the friendly
  /// message rather than replacing it, so nothing gets swallowed.
  final String? detail;

  String get message {
    final extra = detail;
    if (extra == null || extra.isEmpty) return block.message;
    return '${block.message} ($extra)';
  }

  @override
  String toString() => message;
}

/// Playback through the Spotify app itself, via Spotify's App Remote SDK.
///
/// This is what makes music actually come *out of the phone* while the user is
/// in FitSocial. The Web API can only steer a session that some other device
/// has already started; App Remote wakes the installed Spotify app, hands it a
/// URI, and keeps a live player-state subscription open. Audio is owned by the
/// Spotify process throughout — Android gives no app the right to decode
/// someone else's licensed catalogue in-process.
///
/// Requires the Spotify app installed and a Premium account. Callers must treat
/// [SpotifyRemoteException] as an expected outcome, not an error path.
class SpotifyAppRemoteService {
  SpotifyAppRemoteService();

  /// Guards against two taps racing into two parallel connect handshakes,
  /// which the native SDK answers by tearing the first one down.
  Future<bool>? _pendingConnect;

  bool _connected = false;
  bool get isConnected => _connected;

  /// Connects if not already connected. Safe to call before every command.
  ///
  /// Returns true once the bridge is live. Throws [SpotifyRemoteException]
  /// when it cannot be, so the caller can fall back or explain.
  Future<bool> ensureConnected() {
    if (_connected) return Future.value(true);
    return _pendingConnect ??= _connect().whenComplete(() {
      _pendingConnect = null;
    });
  }

  Future<bool> _connect() async {
    try {
      _connected = await SpotifySdk.connectToSpotifyRemote(
        clientId: SpotifyConfig.clientId,
        redirectUrl: SpotifyConfig.appRemoteRedirectUri,
        playerName: 'FitSocial',
      );
      if (!_connected) {
        throw const SpotifyRemoteException(SpotifyRemoteBlock.unknown);
      }
      return true;
    } on PlatformException catch (e) {
      _connected = false;
      throw SpotifyRemoteException(_classify(e), e.message);
    } on MissingPluginException {
      _connected = false;
      throw const SpotifyRemoteException(
        SpotifyRemoteBlock.unknown,
        'the Spotify SDK is not available in this build',
      );
    }
  }

  Future<void> disconnect() async {
    if (!_connected) return;
    _connected = false;
    try {
      await SpotifySdk.disconnect();
    } on PlatformException {
      // Already gone. Nothing to release.
    }
  }

  /// Live player state, mapped into the app's own model.
  ///
  /// Push-based: Spotify emits on every play/pause/skip/seek, so there is no
  /// polling and no API quota to burn. Errors on the stream are surfaced as
  /// [SpotifyRemoteException] rather than raw platform exceptions.
  Stream<MusicPlayerSnapshot> playerStates() {
    return SpotifySdk.subscribePlayerState()
        .map(_toSnapshot)
        .handleError((Object error) {
      _connected = false;
      if (error is PlatformException) {
        throw SpotifyRemoteException(_classify(error), error.message);
      }
      throw SpotifyRemoteException(
        SpotifyRemoteBlock.disconnected,
        error.toString(),
      );
    });
  }

  /// True while the bridge is up, as reported by Spotify rather than by our
  /// own bookkeeping.
  Stream<bool> connectionStates() {
    return SpotifySdk.subscribeConnectionStatus().map((status) {
      _connected = status.connected;
      return status.connected;
    });
  }

  // --- Transport ---

  /// Starts [spotifyUri] — a track, album, playlist or artist URI.
  ///
  /// This is the one thing the Web API could not do without an already-active
  /// device, and the reason App Remote is here.
  Future<void> play(String spotifyUri) =>
      _guard(() => SpotifySdk.play(spotifyUri: spotifyUri));

  Future<void> queue(String spotifyUri) =>
      _guard(() => SpotifySdk.queue(spotifyUri: spotifyUri));

  Future<void> resume() => _guard(SpotifySdk.resume);

  Future<void> pause() => _guard(SpotifySdk.pause);

  Future<void> skipNext() => _guard(SpotifySdk.skipNext);

  Future<void> skipPrevious() => _guard(SpotifySdk.skipPrevious);

  Future<void> seek(Duration position) => _guard(
        () => SpotifySdk.seekTo(
          positionedMilliseconds: position.inMilliseconds,
        ),
      );

  Future<void> setShuffle(bool enabled) =>
      _guard(() => SpotifySdk.setShuffle(shuffle: enabled));

  Future<void> setRepeat(MusicRepeatMode mode) => _guard(
        () => SpotifySdk.setRepeatMode(repeatMode: _toRemoteRepeat(mode)),
      );

  /// Cover art bytes for a track's [imageUriRaw] (`PlayerState.track.imageUri`).
  ///
  /// App Remote hands back a `spotify:image:…` URI that no HTTP client can
  /// resolve — the bytes have to be requested back through the SDK. Returns
  /// null rather than throwing: missing artwork must never break the player.
  Future<Uint8List?> albumArt(String imageUriRaw) async {
    if (imageUriRaw.isEmpty) return null;
    try {
      return await SpotifySdk.getImage(
        imageUri: ImageUri(imageUriRaw),
        dimension: ImageDimension.medium,
      );
    } catch (_) {
      return null;
    }
  }

  /// Runs a transport command, reconnecting once if the bridge has gone away.
  ///
  /// Spotify drops the connection whenever its app is killed or swapped out,
  /// which during a workout is routine rather than exceptional — so a dropped
  /// bridge should cost the user a reconnect, not a failed button press.
  Future<void> _guard(Future<void> Function() action) async {
    await ensureConnected();
    try {
      await action();
    } on PlatformException catch (e) {
      final block = _classify(e);
      if (block != SpotifyRemoteBlock.disconnected) {
        throw SpotifyRemoteException(block, e.message);
      }
      _connected = false;
      await ensureConnected();
      try {
        await action();
      } on PlatformException catch (retry) {
        throw SpotifyRemoteException(_classify(retry), retry.message);
      }
    }
  }

  // --- Mapping ---

  MusicPlayerSnapshot _toSnapshot(remote.PlayerState state) {
    final track = state.track;
    return MusicPlayerSnapshot(
      service: MusicProviderService.spotify,
      track: track == null
          ? null
          : NowPlayingTrack(
              title: track.name,
              artist: _artistsOf(track),
              duration: Duration(milliseconds: track.duration),
              position: Duration(milliseconds: state.playbackPosition),
              albumArtUri: track.imageUri.raw,
            ),
      isPlaying: !state.isPaused,
      shuffleEnabled: state.playbackOptions.isShuffling,
      repeatMode: _fromRemoteRepeat(state.playbackOptions.repeatMode),
      // App Remote always targets the phone Spotify is running on, and exposes
      // no volume control — that belongs to the device's media stream.
      deviceName: 'This phone',
      supportsVolume: false,
    );
  }

  String _artistsOf(remote.Track track) {
    final names = track.artists
        .map((a) => a.name)
        .whereType<String>()
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
    if (names.isNotEmpty) return names.join(', ');
    return track.artist.name ?? 'Unknown artist';
  }

  static RepeatMode _toRemoteRepeat(MusicRepeatMode mode) {
    switch (mode) {
      case MusicRepeatMode.off:
        return RepeatMode.off;
      case MusicRepeatMode.track:
        return RepeatMode.track;
      case MusicRepeatMode.context:
        return RepeatMode.context;
    }
  }

  static MusicRepeatMode _fromRemoteRepeat(options.RepeatMode mode) {
    switch (mode) {
      case options.RepeatMode.off:
        return MusicRepeatMode.off;
      case options.RepeatMode.track:
        return MusicRepeatMode.track;
      case options.RepeatMode.context:
        return MusicRepeatMode.context;
    }
  }

  /// Maps the native SDK's error text onto something actionable.
  ///
  /// The plugin reports every failure as a PlatformException whose code is one
  /// of a handful of strings; the distinguishing detail is in the message, so
  /// both are inspected.
  static SpotifyRemoteBlock _classify(PlatformException e) {
    final haystack = '${e.code} ${e.message ?? ''}'.toLowerCase();
    if (haystack.contains('couldnotfindspotifyapp') ||
        haystack.contains('notinstalled') ||
        haystack.contains('spotify app is not installed')) {
      return SpotifyRemoteBlock.notInstalled;
    }
    if (haystack.contains('notloggedin') ||
        haystack.contains('unauthorized') ||
        haystack.contains('unauthorised') ||
        haystack.contains('usernotauthorized') ||
        haystack.contains('authentication')) {
      return SpotifyRemoteBlock.notAuthorized;
    }
    if (haystack.contains('notconnected') ||
        haystack.contains('disconnect') ||
        haystack.contains('connectionterminated')) {
      return SpotifyRemoteBlock.disconnected;
    }
    return SpotifyRemoteBlock.unknown;
  }
}
