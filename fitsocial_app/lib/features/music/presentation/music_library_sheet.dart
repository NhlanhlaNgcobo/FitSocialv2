import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../application/music_player_controller.dart';
import '../application/music_providers.dart';
import '../data/spotify_api_service.dart';
import '../domain/music_brand.dart';
import '../../../shared/widgets/app_photo.dart';
import '../../../shared/widgets/liquid_glass.dart';

/// Pick something to play.
///
/// This is the half of the music feature that turns the player card from a
/// remote control into a way to start music: every row here starts playback
/// on the phone through the Spotify app.
Future<void> showMusicLibrarySheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _MusicLibrarySheet(),
  );
}

class _MusicLibrarySheet extends ConsumerStatefulWidget {
  const _MusicLibrarySheet();

  @override
  ConsumerState<_MusicLibrarySheet> createState() => _MusicLibrarySheetState();
}

class _MusicLibrarySheetState extends ConsumerState<_MusicLibrarySheet> {
  /// The playlist a tap is currently starting, so only that row spins.
  String? _startingId;

  Future<void> _play(SpotifyPlaylist playlist) async {
    setState(() => _startingId = playlist.id);
    await ref
        .read(musicPlayerControllerProvider.notifier)
        .playContext(playlist.uri);

    if (!mounted) return;
    setState(() => _startingId = null);

    // Close only when playback actually started. On failure the sheet stays
    // put so the reason is readable next to the row that produced it.
    final player = ref.read(musicPlayerControllerProvider);
    if (player.message == null) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final accent = MusicBrand.spotify.accent;
    final player = ref.watch(musicPlayerControllerProvider);

    // The user's own library, and only that. Mood searches used to sit above
    // this list, but every playlist worth starting mid-session is already in
    // the library — the search was a second way to reach a smaller set.
    final playlists = ref.watch(spotifyMyPlaylistsProvider);

    return SafeArea(
      top: false,
      child: LiquidGlass(
        // Over the screen it was opened from, so there is real content to bend.
        lens: true,
        // A sheet always has a page behind it, which makes it the
        // one surface guaranteed something worth bending.
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Container(
          // Tall enough to be worth scrolling, short enough that the player card
          // behind it stays visible.
          height: MediaQuery.of(context).size.height * 0.72,
          padding:
              const EdgeInsets.fromLTRB(AppSpacing.md, 12, AppSpacing.md, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: palette.stroke,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Put something on',
                style: TextStyle(
                  color: palette.text,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Plays through the Spotify app on this phone.',
                style: TextStyle(color: palette.muted, height: 1.45),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Your library',
                style: TextStyle(
                  color: palette.muted,
                  fontSize: 12,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (player.message != null) ...[
                const SizedBox(height: AppSpacing.sm),
                _Notice(message: player.message!),
              ],
              const SizedBox(height: AppSpacing.sm),
              Expanded(
                child: playlists.when(
                  loading: () => Center(
                    child: CircularProgressIndicator(color: accent),
                  ),
                  error: (error, _) => _Notice(
                    message: error is SpotifyApiException
                        ? error.message
                        : 'Could not load playlists: $error',
                  ),
                  data: (items) {
                    if (items.isEmpty) {
                      return const _Notice(
                        message: 'No playlists in your Spotify library yet. '
                            'Make one in Spotify and it will show up here.',
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (_, index) {
                        final playlist = items[index];
                        return _PlaylistRow(
                          playlist: playlist,
                          accent: accent,
                          isStarting: _startingId == playlist.id,
                          onTap: _startingId == null
                              ? () => _play(playlist)
                              : null,
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaylistRow extends StatelessWidget {
  const _PlaylistRow({
    required this.playlist,
    required this.accent,
    required this.isStarting,
    required this.onTap,
  });

  final SpotifyPlaylist playlist;
  final Color accent;
  final bool isStarting;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final cover = playlist.imageUrl;

    // Spotify does not always report a count on `/me/playlists` — editorial and
    // algorithmic playlists in particular come back with nothing there. "0
    // tracks" next to a playlist that plainly has some reads as a broken row
    // rather than a missing field, so with no count to show the owner carries
    // the line on its own.
    final count = playlist.trackCount;
    final subtitle = count > 0
        ? '$count ${count == 1 ? 'track' : 'tracks'} · ${playlist.owner}'
        : playlist.owner;

    return LiquidGlass(
      // Material stays for the ink splash and gives up its colour:
      // an opaque fill in there would sit between the glass and
      // everything it is meant to bend.
      borderRadius: BorderRadius.circular(16),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: cover == null
                        ? ColoredBox(
                            color: palette.surface,
                            child: Icon(
                              Icons.queue_music_rounded,
                              color: accent.withValues(alpha: 0.7),
                              size: 22,
                            ),
                          )
                        : Image(
                            image: appPhotoSized(context, cover, 48),
                            fit: BoxFit.cover,
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        playlist.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.text,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: palette.muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 28,
                  height: 28,
                  child: isStarting
                      ? CircularProgressIndicator(strokeWidth: 2, color: accent)
                      : Icon(Icons.play_circle_fill_rounded,
                          color: accent, size: 28),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// An explanation in the flow of the list, rather than a snackbar the sheet
/// would sit on top of.
class _Notice extends StatelessWidget {
  const _Notice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return LiquidGlass(
      // Painted by the lens rather than by a fill of its own: a pane
      // over the app backdrop, like every other card.
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: palette.stroke),
        ),
        child: Text(
          message,
          style: TextStyle(color: palette.muted, fontSize: 12.5, height: 1.45),
        ),
      ),
    );
  }
}
