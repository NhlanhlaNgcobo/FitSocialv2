import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main/domain/app_models.dart';
import '../../music/application/music_providers.dart';
import '../domain/pulse_models.dart';
import '../domain/pulse_music.dart';
import 'pulse_music_frame.dart';
import 'pulse_share_scaffold.dart';

/// "Share what you're listening to" — the Instagram and Spotify move, in
/// FitSocial's terms.
///
/// Reached from the player rather than from the Pulse composer, because the
/// thing being shared is whatever is playing right now: opening a composer
/// first and then asking which song would be asking a question the app can
/// already answer.
///
/// The track is snapshotted onto the Pulse, so skipping to the next song a
/// second later does not rewrite what was shared.
class ShareMusicToPulseScreen extends ConsumerStatefulWidget {
  const ShareMusicToPulseScreen({required this.music, super.key});

  final PulseMusic music;

  @override
  ConsumerState<ShareMusicToPulseScreen> createState() =>
      _ShareMusicToPulseScreenState();
}

class _ShareMusicToPulseScreenState
    extends ConsumerState<ShareMusicToPulseScreen> {
  late PulseMusic _music = widget.music;

  /// The cover lookup, while it is in flight. Share waits on this: a Pulse
  /// published a beat after arriving would otherwise go out bare and stay
  /// bare, since a Pulse is a snapshot.
  Future<void>? _coverLookup;

  @override
  void initState() {
    super.initState();
    if (_music.albumArtUrl == null) _coverLookup = _resolveCoverArt();
  }

  /// Holds Share until the cover has been found or given up on.
  ///
  /// Bounded: the lookup already times out per request, but a phone on a
  /// bad connection should not sit on a spinner for the sum of them. Past
  /// the bound the Pulse goes out with whatever it has, which is what it
  /// would have done anyway.
  Future<void> _awaitCover() async {
    final lookup = _coverLookup;
    if (lookup == null) return;
    try {
      await lookup.timeout(const Duration(seconds: 12));
    } catch (_) {
      // A slow or failed lookup is not a failed share.
    }
  }

  /// The last chance to find the cover before it is written onto a Pulse.
  ///
  /// A Pulse is a snapshot, so whatever is missing at publish time stays
  /// missing for the whole 24 hours, and a sticker that names a song over a
  /// grey square reads as broken. Two places to look, in order of how exact
  /// they are:
  ///
  ///  1. Spotify's own catalogue, by track id — but only a track that came in
  ///     through a linked account carries an id, and the Web API behind it
  ///     needs that account's token.
  ///  2. A public catalogue, by title and artist. This is the path every
  ///     user is actually on: the phone's media session reports the cover as
  ///     bytes that cannot leave this device, and nothing else to look it up
  ///     by. Without this step, every track shared from it arrived bare.
  Future<void> _resolveCoverArt() async {
    final url = await _lookupBySpotifyId() ?? await _lookupByName();
    if (!mounted) return;

    setState(() {
      _coverLookup = null;
      if (url != null) _music = _music.withAlbumArt(url);
    });
  }

  Future<String?> _lookupBySpotifyId() async {
    final uri = _music.trackUri;
    if (uri == null || _music.provider != MusicProviderService.spotify) {
      return null;
    }
    try {
      return await ref
          .read(spotifyApiServiceProvider)
          .fetchTrackArtworkUrl(uri);
    } catch (_) {
      // Not worth a message: the sticker still names the track, and telling
      // someone their cover art failed to load is noise they cannot act on.
      // The name lookup below still gets its turn.
      return null;
    }
  }

  Future<String?> _lookupByName() async {
    try {
      return await ref.read(coverArtLookupProvider).findArtworkUrl(
            title: _music.title,
            artist: _music.artist,
          );
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasArt = (_music.albumArtUrl ?? '').isNotEmpty;

    return PulseShareScaffold(
      canvas: (gradient) => PulseMusicFrame(
        music: _music,
        gradient: gradient,
        contentPadding: PulseMusicFrame.sharePadding,
        resolvingArt: _coverLookup != null,
      ),
      canvasFillsFrame: true,
      // Once the cover art is the background there is no gradient left to see,
      // so the palette only appears for a track that arrived without artwork.
      showGradientPicker: !hasArt,
      captionHint: 'Say something about this track',
      beforeShare: _awaitCover,
      // Reads _music rather than the widget's copy, so a cover that resolves
      // while the caption is being typed still makes it onto the Pulse.
      buildDraft: (text, textStyle, gradientKey) => PulseDraft(
        type: PulseMediaType.music,
        text: text,
        textStyle: textStyle,
        gradientKey: gradientKey,
        music: _music,
      ),
    );
  }
}
