import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/quick_toast.dart';
import '../../main/domain/app_models.dart';
import '../../music/application/music_player_controller.dart';
import '../../music/application/music_providers.dart';
import '../../music/presentation/connect_music_sheet.dart';
import '../../music/presentation/widgets/music_brand_logos.dart';
import '../domain/pulse_music.dart';

/// The now-playing sticker on a music Pulse.
///
/// Drawn on the frame the way Instagram draws a music sticker: cover art, the
/// track, who it is by, and a way to hear it. Deliberately fixed light-on-dark
/// rather than palette-driven — it sits over a Pulse gradient, which is the
/// same in both themes.
class PulseMusicCard extends ConsumerWidget {
  const PulseMusicCard({required this.music, super.key});

  final PulseMusic music;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: const Color(0xCC0B0B0B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.onMedia.withValues(alpha: 0.18)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              MusicServiceLogo(service: music.provider, size: 15),
              const SizedBox(width: 6),
              Text(
                'LISTENING TO',
                style: TextStyle(
                  color: AppColors.onMedia.withValues(alpha: 0.7),
                  fontSize: 10,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              _Cover(imageUrl: music.albumArtUrl),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      music.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.onMedia,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      music.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.onMedia.withValues(alpha: 0.72),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _ListenAction(music: music),
        ],
      ),
    );
  }
}

class _ListenAction extends ConsumerStatefulWidget {
  const _ListenAction({required this.music});

  final PulseMusic music;

  @override
  ConsumerState<_ListenAction> createState() => _ListenActionState();
}

class _ListenActionState extends ConsumerState<_ListenAction> {
  bool _isStarting = false;

  Future<void> _play() async {
    final uri = widget.music.trackUri;
    if (uri == null) return;

    setState(() => _isStarting = true);
    try {
      await ref.read(musicPlayerControllerProvider.notifier).playContext(uri);
    } catch (error) {
      if (!mounted) return;
      debugPrint('Starting a track failed: $error');
      showQuickToast(
        context,
        "Couldn't start that track.",
        icon: Icons.error_outline_rounded,
        tone: ToastTone.danger,
      );
    } finally {
      if (mounted) setState(() => _isStarting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final music = widget.music;

    // Nothing to start: an older Pulse saved before track URIs were captured,
    // or a service this app does not drive. The sticker still names the song.
    if (!music.isPlayable) return const SizedBox.shrink();

    // Starting a named track needs an account, and there are none on offer
    // right now — the phone's media session can steer what is playing but
    // cannot pick it. The sticker still names the song, which is the part that
    // travels between people anyway. See musicAccountsEnabledProvider.
    if (!ref.watch(musicAccountsEnabledProvider)) {
      return const SizedBox.shrink();
    }

    final isConnected =
        ref.watch(musicConnectionsProvider).isConnected(music.provider);

    if (!isConnected) {
      return _StickerButton(
        icon: Icons.link_rounded,
        label: 'Connect ${music.provider.label}',
        onPressed: () => showConnectMusicSheet(context),
      );
    }

    return _StickerButton(
      icon: _isStarting ? null : Icons.play_arrow_rounded,
      label: _isStarting ? 'Starting…' : 'Play',
      busy: _isStarting,
      onPressed: _isStarting ? null : _play,
    );
  }
}

class _StickerButton extends StatelessWidget {
  const _StickerButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 40,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.orangeBright,
          foregroundColor: AppColors.onBrand,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        onPressed: onPressed,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (busy)
              const SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.onBrand,
                ),
              )
            else if (icon != null)
              Icon(icon, size: 18),
            const SizedBox(width: AppSpacing.sm),
            Text(label),
          ],
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.imageUrl});

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    const size = 60.0;

    Widget placeholder() => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: AppColors.onMedia.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.music_note_rounded,
            color: AppColors.onMedia.withValues(alpha: 0.7),
            size: 26,
          ),
        );

    final url = imageUrl;
    if (url == null || url.isEmpty) return placeholder();

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        // The art fades in over the placeholder rather than replacing it in
        // one frame, so a cover arriving a beat late doesn't read as a glitch.
        // Already-cached frames are handed straight through.
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded) return child;
          return Stack(
            children: [
              placeholder(),
              AnimatedOpacity(
                opacity: frame == null ? 0 : 1,
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOut,
                child: child,
              ),
            ],
          );
        },
        // Cover art that will not load must not cost the sticker its track.
        errorBuilder: (context, error, stackTrace) => placeholder(),
      ),
    );
  }
}
