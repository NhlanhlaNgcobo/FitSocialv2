import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_palette.dart';
import '../../../shared/widgets/dark_card.dart';
import '../application/music_player_controller.dart';
import '../application/music_providers.dart';
import '../domain/music_brand.dart';
import 'music_library_sheet.dart';
import 'widgets/music_album_art.dart';

/// A one-line player for screens where music is not the point.
///
/// Built for the Live Run screen: mid-run the only control that matters is
/// skipping a track you don't want, so this carries previous / play-pause /
/// next and nothing else. Shuffle, repeat, seek and volume are deliberately
/// left to the full [MusicPlayerCard] — they are not decisions anyone makes
/// while running, and every extra control is another thing to hit by mistake
/// with sweaty hands.
///
/// Shares the same controller as the full player, so whatever is playing and
/// whatever the runner does here stays in step with the Music tab.
class MusicMiniPlayer extends ConsumerWidget {
  const MusicMiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final connections = ref.watch(musicConnectionsProvider);
    if (!connections.hasAnyConnection) return const SizedBox.shrink();

    final player = ref.watch(musicPlayerControllerProvider);
    final service = player.service ?? connections.connectedServices.first;
    final brand = MusicBrand.of(service);
    final controller = ref.read(musicPlayerControllerProvider.notifier);
    final track = player.snapshot?.track;

    final canControl = player.canControl;

    return DarkCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          // Art and title open the library. Mid-run the user has one hand and
          // no patience for a menu, so the biggest thing on the card is the
          // way to change what is playing.
          Expanded(
            child: InkWell(
              onTap: player.canStartPlayback
                  ? () => showMusicLibrarySheet(context)
                  : null,
              borderRadius: BorderRadius.circular(12),
              child: Row(
                children: [
                  MusicAlbumArt(
                    imageUrl: track?.albumArtUrl,
                    imageBytes: track?.albumArtBytes,
                    accent: brand.accent,
                    size: 46,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track?.title ?? 'Tap to pick a playlist',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.text,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          // With no track loaded the reason why is more useful
                          // than a blank line — but it has to stay on one line.
                          track?.artist ?? player.message ?? brand.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          _MiniButton(
            icon: Icons.skip_previous_rounded,
            tooltip: 'Previous track',
            enabled: canControl,
            onPressed: controller.previous,
          ),
          _MiniPlayPause(
            isPlaying: player.isPlaying,
            accent: brand.accent,
            enabled: canControl,
            onPressed: controller.togglePlayPause,
          ),
          _MiniButton(
            icon: Icons.skip_next_rounded,
            tooltip: 'Next track',
            enabled: canControl,
            onPressed: controller.next,
          ),
        ],
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color =
        enabled ? palette.text : palette.muted.withValues(alpha: 0.4);

    return IconButton(
      tooltip: tooltip,
      onPressed: enabled ? onPressed : null,
      icon: Icon(icon, size: 28),
      color: color,
      disabledColor: color,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
    );
  }
}

class _MiniPlayPause extends StatelessWidget {
  const _MiniPlayPause({
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
            width: 42,
            height: 42,
            child: Icon(
              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: 24,
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
