import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/app_photo.dart';
import '../../../shared/widgets/liquid_glass.dart';
import '../../../shared/widgets/quick_toast.dart';
import '../../main/domain/app_models.dart';
import '../../music/application/music_player_controller.dart';
import '../../music/application/music_providers.dart';
import '../../music/presentation/connect_music_sheet.dart';
import '../../music/presentation/widgets/music_brand_logos.dart';
import '../domain/pulse_models.dart';
import '../domain/pulse_music.dart';
import 'pulse_photo_frame.dart';

/// A music Pulse, filling the frame.
///
/// The cover art is the background — blurred and dimmed, the way Instagram
/// builds a music story — with a sharp copy of the same art held whole in the
/// middle, the track under it, and one way to hear it. The art itself is never
/// cropped: it is square and the frame is 9:16, so only the backdrop is cut.
///
/// Deliberately fixed light-on-dark rather than palette-driven. It sits over
/// album art or a Pulse gradient, neither of which changes with the theme.
class PulseMusicFrame extends ConsumerWidget {
  const PulseMusicFrame({
    required this.music,
    required this.gradient,
    this.contentPadding = viewerPadding,
    super.key,
  });

  final PulseMusic music;

  /// Painted when the track has no cover art to fill the frame with — an older
  /// Pulse, or a service whose artwork this app cannot reach.
  final PulseGradient gradient;

  /// Keeps the sticker clear of whatever chrome floats over the frame.
  final EdgeInsets contentPadding;

  /// Clears the viewer's header and its reaction bar.
  static const EdgeInsets viewerPadding =
      EdgeInsets.fromLTRB(AppSpacing.lg, 96, AppSpacing.lg, 168);

  /// Clears the share screen's top bar and its control stack.
  static const EdgeInsets sharePadding =
      EdgeInsets.fromLTRB(AppSpacing.lg, 64, AppSpacing.lg, 210);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final art = music.albumArtUrl;
    final hasArt = art != null && art.isNotEmpty;

    return ColoredBox(
      color: AppColors.mediaBackdrop,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasArt)
            PulseBlurredBackdrop(image: appPhoto(art))
          else
            DecoratedBox(decoration: BoxDecoration(gradient: gradient.linear)),
          Padding(
            padding: contentPadding,
            child: LayoutBuilder(
              builder: (context, constraints) {
                // The art leads, but never at the cost of the track beneath it
                // — on a short frame the square gives way before the title
                // does.
                final cover = math.min(
                  constraints.maxWidth * 0.72,
                  constraints.maxHeight * 0.46,
                );
                return Center(
                  child: SingleChildScrollView(
                    child: _Details(
                      music: music,
                      coverSize: math.max(cover, 96),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.music, required this.coverSize});

  final PulseMusic music;
  final double coverSize;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            MusicServiceLogo(service: music.provider, size: 15),
            const SizedBox(width: 7),
            Text(
              'LISTENING TO',
              style: TextStyle(
                color: AppColors.onMedia.withValues(alpha: 0.72),
                fontSize: 11,
                letterSpacing: 1.6,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        SizedBox(height: coverSize * 0.12),
        _Cover(imageUrl: music.albumArtUrl, size: coverSize),
        SizedBox(height: coverSize * 0.13),
        Text(
          music.title,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.onMedia,
            fontSize: 26,
            height: 1.15,
            letterSpacing: -0.4,
            fontWeight: FontWeight.w800,
          ),
        ),
        // The service is already named in the eyebrow above, so this line is
        // the artist alone rather than `music.subtitle` — and it steps out
        // entirely for a track that arrived without one.
        if (music.artist.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            music.artist,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppColors.onMedia.withValues(alpha: 0.72),
              fontSize: 15,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        _ListenAction(music: music),
      ],
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
      return _GlassButton(
        icon: Icons.link_rounded,
        label: 'Connect ${music.provider.label}',
        onPressed: () => showConnectMusicSheet(context),
      );
    }

    return _GlassButton(
      icon: _isStarting ? null : Icons.play_arrow_rounded,
      label: _isStarting ? 'Starting…' : 'Play',
      busy: _isStarting,
      onPressed: _isStarting ? null : _play,
    );
  }
}

/// The pill under the track: the app's glass, not a slab of brand orange.
class _GlassButton extends StatelessWidget {
  const _GlassButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;

  static const double _height = 46;
  static const BorderRadius _radius =
      BorderRadius.all(Radius.circular(_height / 2));

  @override
  Widget build(BuildContext context) {
    return LiquidGlass(
      borderRadius: _radius,
      // No lens. Behind this pill is the blurred backdrop or a Pulse gradient
      // — both already smooth, and bending a smooth thing hands back the same
      // smooth thing. The pane paints its own material instead, which costs no
      // second render pass on a frame that is also playing a Pulse.
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: _radius,
          border: Border.all(color: AppColors.onMedia.withValues(alpha: 0.28)),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onPressed,
            borderRadius: _radius,
            child: Container(
              height: _height,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (busy)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.onMedia,
                      ),
                    )
                  else if (icon != null)
                    Icon(icon, size: 20, color: AppColors.onMedia),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    label,
                    style: const TextStyle(
                      color: AppColors.onMedia,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The sharp cover, held whole in the middle of the frame.
class _Cover extends StatelessWidget {
  const _Cover({required this.imageUrl, required this.size});

  final String? imageUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.06);

    Widget placeholder() => DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.onMedia.withValues(alpha: 0.12),
            borderRadius: radius,
          ),
          child: Center(
            child: Icon(
              Icons.music_note_rounded,
              color: AppColors.onMedia.withValues(alpha: 0.7),
              size: size * 0.34,
            ),
          ),
        );

    final url = imageUrl;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: radius,
        // Lifts the art off its own blurred copy, which is otherwise the same
        // colours at the same brightness and reads as a smudge.
        boxShadow: const [
          BoxShadow(
            color: Color(0x8C000000),
            blurRadius: 30,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: url == null || url.isEmpty
            ? placeholder()
            : Image(
                image: appPhotoSized(context, url, size),
                width: size,
                height: size,
                fit: BoxFit.cover,
                // The art fades in over the placeholder rather than replacing
                // it in one frame, so a cover arriving a beat late doesn't read
                // as a glitch. Already-cached frames pass straight through.
                frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                  if (wasSynchronouslyLoaded) return child;
                  return Stack(
                    fit: StackFit.expand,
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
                // Cover art that will not load must not cost the sticker its
                // track.
                errorBuilder: (context, error, stackTrace) => placeholder(),
              ),
      ),
    );
  }
}
