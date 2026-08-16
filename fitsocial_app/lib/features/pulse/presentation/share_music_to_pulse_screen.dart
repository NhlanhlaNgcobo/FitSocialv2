import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main/domain/app_models.dart';
import '../../music/application/music_providers.dart';
import '../domain/pulse_models.dart';
import '../domain/pulse_music.dart';
import 'pulse_music_card.dart';
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

  @override
  void initState() {
    super.initState();
    if (_music.albumArtUrl == null) unawaited(_resolveCoverArt());
  }

  /// The last chance to find the cover before it is written onto a Pulse.
  ///
  /// The player normally resolves this while the track is playing, but a song
  /// shared the instant it changes can arrive here before that lookup lands —
  /// and a Pulse is a snapshot, so whatever is missing at publish time stays
  /// missing for the whole 24 hours. A sticker that names a song and shows a
  /// grey square reads as broken, which is worth one more request to avoid.
  Future<void> _resolveCoverArt() async {
    final uri = _music.trackUri;
    // Spotify is the only service with a lookup wired up; the others snapshot
    // whatever artwork they came with.
    if (uri == null || _music.provider != MusicProviderService.spotify) return;

    final String? url;
    try {
      url = await ref.read(spotifyApiServiceProvider).fetchTrackArtworkUrl(uri);
    } catch (_) {
      // Not worth a message: the sticker still names the track, and telling
      // someone their cover art failed to load is noise they cannot act on.
      return;
    }
    if (!mounted || url == null) return;

    setState(() => _music = _music.withAlbumArt(url!));
  }

  @override
  Widget build(BuildContext context) {
    return PulseShareScaffold(
      canvas: PulseMusicCard(music: _music),
      captionHint: 'Say something about this track',
      // Reads _music rather than the widget's copy, so a cover that resolves
      // while the caption is being typed still makes it onto the Pulse.
      buildDraft: (caption, gradientKey) => PulseDraft(
        type: PulseMediaType.music,
        text: caption,
        gradientKey: gradientKey,
        music: _music,
      ),
    );
  }
}
