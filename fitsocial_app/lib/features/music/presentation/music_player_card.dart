import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../main/domain/app_models.dart';
import '../../pulse/domain/pulse_music.dart';
import '../application/music_player_controller.dart';
import '../application/music_providers.dart';
import '../domain/music_brand.dart';
import '../domain/music_playback.dart';
import 'music_library_sheet.dart';
import 'widgets/album_art_glass.dart';
import 'widgets/music_album_art.dart';
import 'widgets/music_brand_logos.dart';
import '../../../shared/widgets/liquid_glass.dart';

/// The transport controls for the connected service.
///
/// Renders nothing at all until a service is connected — there is no point
/// showing a play button with nothing behind it.
class MusicPlayerCard extends ConsumerWidget {
  const MusicPlayerCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    // A linked account *or* notification access to the phone's own session.
    // The second needs no sign-in, and gating on connections alone hid the
    // whole player from everyone who took it.
    if (!ref.watch(hasMusicSourceProvider)) return const SizedBox.shrink();

    final player = ref.watch(musicPlayerControllerProvider);
    // Whatever is playing names itself; a linked account stands in until the
    // first snapshot lands, and `device` stands in for that, because the
    // media-session path has no account to name.
    final connected = ref.watch(musicConnectionsProvider).connectedServices;
    final service = player.service ??
        (connected.isEmpty ? MusicProviderService.device : connected.first);
    final brand = MusicBrand.of(service);
    final controller = ref.read(musicPlayerControllerProvider.notifier);
    final track = player.snapshot?.track;

    // Live once a transport is up — App Remote on this phone, or the Web API
    // driving a Connect device elsewhere.
    final canControl = player.canControl;

    // The card wears the cover art: blurred to glass behind the controls, so
    // the player takes on the colour of whatever is playing instead of sitting
    // on the same grey slab all day.
    return AlbumArtGlass(
      imageUrl: track?.albumArtUrl,
      imageBytes: track?.albumArtBytes,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              MusicAlbumArt(
                imageUrl: track?.albumArtUrl,
                imageBytes: track?.albumArtBytes,
                accent: brand.accent,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        MusicServiceLogo(service: service, size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            player.snapshot?.deviceName ?? brand.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: brand.accent,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      track?.title ?? 'Nothing playing',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      track?.artist ?? 'Start a track to see it here',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.muted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              _PlayerMenu(
                brand: brand,
                onLogOut: () => ref
                    .read(musicConnectionsProvider.notifier)
                    .disconnect(service),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _SeekBar(
            track: track,
            accent: brand.accent,
            // A live stream publishes no seek action; the bar still draws so
            // the elapsed time is readable, it just does not take a drag.
            enabled: canControl && (player.snapshot?.canSeek ?? true),
            onSeek: controller.seek,
          ),
          const SizedBox(height: 6),
          _TransportRow(
            player: player,
            accent: brand.accent,
            enabled: canControl,
            onShuffle: controller.toggleShuffle,
            onPrevious: controller.previous,
            onPlayPause: controller.togglePlayPause,
            onNext: controller.next,
            onRepeat: controller.cycleRepeat,
          ),
          if (canControl && (player.snapshot?.canSetVolume ?? false))
            _VolumeRow(
              level: player.snapshot!.volumePercent!,
              accent: brand.accent,
              onChanged: controller.setVolume,
            ),
          if (player.canStartPlayback) ...[
            const SizedBox(height: AppSpacing.sm),
            _BrowseButton(
              accent: brand.accent,
              // The label carries the weight when there is nothing loaded —
              // that is the state where the user most needs to be told this
              // card can start music, not just steer it.
              label: player.hasTrack ? 'Change playlist' : 'Pick a playlist',
              onTap: () => showMusicLibrarySheet(context),
            ),
          ],
          // Only with something actually loaded: "share what you're listening
          // to" has nothing to say when nothing is playing.
          if (player.hasTrack) ...[
            const SizedBox(height: AppSpacing.sm),
            _ShareToPulseButton(
              accent: brand.accent,
              onTap: () => _shareTrackToPulse(context, player),
            ),
          ],
          if (player.message != null) ...[
            const SizedBox(height: 4),
            Text(
              player.message!,
              style: TextStyle(
                color: palette.muted,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Sends whatever is playing to the Pulse composer.
///
/// Snapshotted here rather than read again on the other screen: by the time
/// the composer builds, the track may have changed, and what the user pressed
/// the button on is what they meant to share.
void _shareTrackToPulse(BuildContext context, MusicPlayerState player) {
  final track = player.snapshot?.track;
  final service = player.service;
  if (track == null || service == null) return;

  context.push(
    '/share-music-to-pulse',
    extra: PulseMusic(
      provider: service,
      title: track.title,
      artist: track.artist,
      trackUri: track.uri,
      // Only the https form travels: the bytes both App Remote and the media
      // session hand back are local to this phone. The controller resolves
      // this URL from the track while it plays where it can, and the share
      // screen looks it up by id or by name if it is still missing here —
      // which on the media-session path it always is.
      albumArtUrl: track.albumArtUrl,
    ),
  );
}

/// Puts the current track on your Pulse.
///
/// Sits under the browse row and is styled to match it: this is a secondary
/// action on a card whose job is playback, not a call to action competing with
/// the transport above it.
class _ShareToPulseButton extends StatelessWidget {
  const _ShareToPulseButton({required this.accent, required this.onTap});

  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return LiquidGlass(
      // Material stays for the ink splash and gives up its colour:
      // an opaque fill in there would sit between the glass and
      // everything it is meant to bend.
      borderRadius: BorderRadius.circular(14),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: palette.stroke),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.bolt_rounded, size: 18, color: accent),
                const SizedBox(width: 8),
                Text(
                  'Share to Pulse',
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens the library sheet.
///
/// Styled as a quiet full-width row rather than a brand-coloured button: the
/// transport above it is the loud element, and two competing calls to action
/// inside one card read as clutter.
class _BrowseButton extends StatelessWidget {
  const _BrowseButton({
    required this.accent,
    required this.label,
    required this.onTap,
  });

  final Color accent;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return LiquidGlass(
      // Material stays for the ink splash and gives up its colour:
      // an opaque fill in there would sit between the glass and
      // everything it is meant to bend.
      borderRadius: BorderRadius.circular(14),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: palette.stroke),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.queue_music_rounded, size: 18, color: accent),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Signing out of the music account, from the card that account drives.
///
/// Deliberately understated: it lives behind an overflow menu rather than
/// sitting next to the transport, because logging out mid-workout by mistake
/// is worse than taking one extra tap to do it on purpose. Reconnecting is a
/// single tap, so it asks for no further confirmation.
enum _PlayerMenuAction { logOut }

class _PlayerMenu extends StatelessWidget {
  const _PlayerMenu({required this.brand, required this.onLogOut});

  final MusicBrand brand;
  final VoidCallback onLogOut;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return PopupMenuButton<_PlayerMenuAction>(
      tooltip: '${brand.name} account',
      icon: const Icon(Icons.more_horiz_rounded, size: 20),
      color: palette.surfaceHigh,
      iconColor: palette.muted,
      padding: EdgeInsets.zero,
      splashRadius: 20,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: palette.stroke),
      ),
      onSelected: (action) {
        switch (action) {
          case _PlayerMenuAction.logOut:
            onLogOut();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<_PlayerMenuAction>(
          value: _PlayerMenuAction.logOut,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.logout_rounded,
                size: 18,
                color: palette.muted,
              ),
              const SizedBox(width: 10),
              // The menu caps its own width, so the longest service name
              // ("Log out of YouTube Music") has to be allowed to shrink.
              Flexible(
                child: Text(
                  'Log out of ${brand.name}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

String _formatTime(Duration? value) {
  if (value == null) return '--:--';
  final minutes = value.inMinutes;
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

/// Slim theme shared by the seek and volume sliders: a hairline track with a
/// small thumb, so they read as part of the card rather than as form controls.
SliderThemeData _sliderTheme(
  Color accent, {
  required AppPalette palette,
  required bool enabled,
}) {
  return SliderThemeData(
    trackHeight: 4,
    activeTrackColor: enabled ? accent : palette.muted.withValues(alpha: 0.4),
    inactiveTrackColor: palette.surfaceHigh,
    thumbColor: enabled ? accent : palette.muted.withValues(alpha: 0.4),
    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
    overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
    overlayColor: accent.withValues(alpha: 0.16),
    trackShape: const RoundedRectSliderTrackShape(),
    // The player owns the tick labels; the default bubble would cover the art.
    showValueIndicator: ShowValueIndicator.never,
  );
}

/// The progress bar, draggable to scrub.
///
/// The thumb follows the finger locally and only commits on release: seeking
/// on every drag frame would fire a request per pixel and get the app rate
/// limited within a second.
class _SeekBar extends StatefulWidget {
  const _SeekBar({
    required this.track,
    required this.accent,
    required this.enabled,
    required this.onSeek,
  });

  final NowPlayingTrack? track;
  final Color accent;
  final bool enabled;
  final ValueChanged<Duration> onSeek;

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double? _dragMs;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final track = widget.track;
    final totalMs = track?.duration.inMilliseconds ?? 0;
    // A zero-length track would make Slider's min and max equal, which throws.
    final scrubbable = widget.enabled && track != null && totalMs > 0;

    final positionMs = _dragMs ??
        (track?.position.inMilliseconds ?? 0).clamp(0, totalMs).toDouble();

    return Column(
      children: [
        SliderTheme(
          data: _sliderTheme(widget.accent,
              palette: palette, enabled: scrubbable),
          child: Slider(
            value: scrubbable ? positionMs : 0,
            max: scrubbable ? totalMs.toDouble() : 1,
            onChanged:
                scrubbable ? (value) => setState(() => _dragMs = value) : null,
            onChangeEnd: scrubbable
                ? (value) {
                    widget.onSeek(Duration(milliseconds: value.round()));
                    setState(() => _dragMs = null);
                  }
                : null,
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              // While dragging, the left-hand time is where you would land.
              _formatTime(
                scrubbable
                    ? Duration(milliseconds: positionMs.round())
                    : track?.position,
              ),
              style: TextStyle(
                color: _dragMs == null ? palette.muted : widget.accent,
                fontSize: 11,
                fontWeight: _dragMs == null ? FontWeight.w400 : FontWeight.w700,
              ),
            ),
            Text(
              _formatTime(track?.duration),
              style: TextStyle(color: palette.muted, fontSize: 11),
            ),
          ],
        ),
      ],
    );
  }
}

/// Output volume for the active Spotify device.
class _VolumeRow extends StatefulWidget {
  const _VolumeRow({
    required this.level,
    required this.accent,
    required this.onChanged,
  });

  final int level;
  final Color accent;
  final ValueChanged<int> onChanged;

  @override
  State<_VolumeRow> createState() => _VolumeRowState();
}

class _VolumeRowState extends State<_VolumeRow> {
  double? _dragLevel;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final level = _dragLevel ?? widget.level.toDouble();

    return Row(
      children: [
        IconButton(
          tooltip: level == 0 ? 'Unmute' : 'Mute',
          // Mute remembers nothing: coming back from silence restores a usable
          // level rather than the volume the user had before.
          onPressed: () => widget.onChanged(level == 0 ? 40 : 0),
          icon: Icon(_iconFor(level), size: 20),
          color: palette.muted,
          visualDensity: VisualDensity.compact,
        ),
        Expanded(
          child: SliderTheme(
            data: _sliderTheme(widget.accent, palette: palette, enabled: true),
            child: Slider(
              value: level,
              max: 100,
              onChanged: (value) => setState(() => _dragLevel = value),
              onChangeEnd: (value) {
                widget.onChanged(value.round());
                setState(() => _dragLevel = null);
              },
            ),
          ),
        ),
        SizedBox(
          width: 34,
          child: Text(
            '${level.round()}',
            textAlign: TextAlign.end,
            style: TextStyle(color: palette.muted, fontSize: 11),
          ),
        ),
      ],
    );
  }

  IconData _iconFor(double level) {
    if (level == 0) return Icons.volume_off_rounded;
    if (level < 50) return Icons.volume_down_rounded;
    return Icons.volume_up_rounded;
  }
}

class _TransportRow extends StatelessWidget {
  const _TransportRow({
    required this.player,
    required this.accent,
    required this.enabled,
    required this.onShuffle,
    required this.onPrevious,
    required this.onPlayPause,
    required this.onNext,
    required this.onRepeat,
  });

  final MusicPlayerState player;
  final Color accent;
  final bool enabled;
  final VoidCallback onShuffle;
  final VoidCallback onPrevious;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onRepeat;

  @override
  Widget build(BuildContext context) {
    final repeat = player.repeatMode;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _TransportButton(
          icon: Icons.shuffle_rounded,
          tooltip: 'Shuffle',
          // Shuffle and repeat light up in the brand colour when engaged, the
          // same signal both Spotify and Apple Music use.
          active: player.shuffleEnabled,
          accent: accent,
          // Dimmed rather than absent on the media-session path: the control
          // exists in every other transport, and a button that vanishes
          // between sessions reads as a bug.
          enabled: enabled && player.canSetShuffleRepeat,
          onPressed: onShuffle,
        ),
        _TransportButton(
          icon: Icons.skip_previous_rounded,
          tooltip: 'Previous track',
          size: 32,
          accent: accent,
          enabled: enabled && (player.snapshot?.canSkipPrevious ?? true),
          onPressed: onPrevious,
        ),
        _PlayPauseButton(
          isPlaying: player.isPlaying,
          accent: accent,
          enabled: enabled,
          onPressed: onPlayPause,
        ),
        _TransportButton(
          icon: Icons.skip_next_rounded,
          tooltip: 'Next track',
          size: 32,
          accent: accent,
          enabled: enabled && (player.snapshot?.canSkipNext ?? true),
          onPressed: onNext,
        ),
        _TransportButton(
          icon: repeat == MusicRepeatMode.track
              ? Icons.repeat_one_rounded
              : Icons.repeat_rounded,
          tooltip: switch (repeat) {
            MusicRepeatMode.off => 'Repeat off',
            MusicRepeatMode.context => 'Repeat playlist',
            MusicRepeatMode.track => 'Repeat track',
          },
          active: repeat != MusicRepeatMode.off,
          accent: accent,
          enabled: enabled && player.canSetShuffleRepeat,
          onPressed: onRepeat,
        ),
      ],
    );
  }
}

class _TransportButton extends StatelessWidget {
  const _TransportButton({
    required this.icon,
    required this.tooltip,
    required this.accent,
    required this.enabled,
    required this.onPressed,
    this.active = false,
    this.size = 24,
  });

  final IconData icon;
  final String tooltip;
  final Color accent;
  final bool enabled;
  final VoidCallback onPressed;
  final bool active;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final Color color;
    if (!enabled) {
      color = palette.muted.withValues(alpha: 0.4);
    } else if (active) {
      color = accent;
    } else {
      color = palette.text;
    }

    return IconButton(
      tooltip: tooltip,
      onPressed: enabled ? onPressed : null,
      icon: Icon(icon, size: size),
      color: color,
      // Disabled IconButtons ignore `color`, so pin the same value there too.
      disabledColor: color,
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  const _PlayPauseButton({
    required this.isPlaying,
    required this.accent,
    required this.enabled,
    required this.onPressed,
  });

  final bool isPlaying;
  final Color accent;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      button: true,
      label: isPlaying ? 'Pause' : 'Play',
      child: Material(
        color: enabled ? accent : palette.surfaceHigh,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? onPressed : null,
          child: SizedBox(
            width: 54,
            height: 54,
            child: Icon(
              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: 30,
              color: enabled
                  ? palette.background
                  : palette.muted.withValues(alpha: 0.4),
            ),
          ),
        ),
      ),
    );
  }
}
