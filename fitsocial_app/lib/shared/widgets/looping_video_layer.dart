import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../app/theme/app_motion.dart';

/// A card's video loop, playing silently over its own first frame.
///
/// Laid over the still rather than instead of it: the still is already on
/// screen, so a slow connection or a clip that will not open costs the motion
/// and nothing else, and the swap from still to video has no flash in it.
///
/// Muted, and mixed with other audio, so a card scrolling past never pauses
/// the music someone is running to. With reduce motion on it never starts at
/// all — the still is the card.
class LoopingVideoLayer extends StatefulWidget {
  const LoopingVideoLayer({required this.source, super.key});

  /// An https URL, or a local file path for a loop not yet uploaded.
  final String source;

  @override
  State<LoopingVideoLayer> createState() => _LoopingVideoLayerState();
}

class _LoopingVideoLayerState extends State<LoopingVideoLayer> {
  VideoPlayerController? _controller;
  bool _ready = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller == null && !context.reduceMotion) _start();
  }

  @override
  void didUpdateWidget(LoopingVideoLayer old) {
    super.didUpdateWidget(old);
    if (old.source != widget.source) {
      _stop();
      if (!context.reduceMotion) _start();
    }
  }

  Future<void> _start() async {
    final source = widget.source;
    final options = VideoPlayerOptions(mixWithOthers: true);
    final controller = source.startsWith('http')
        ? VideoPlayerController.networkUrl(
            Uri.parse(source),
            videoPlayerOptions: options,
          )
        : kIsWeb
            ? null
            : VideoPlayerController.file(
                File(source),
                videoPlayerOptions: options,
              );
    if (controller == null) return;
    _controller = controller;
    try {
      await controller.initialize();
      await controller.setVolume(0);
      await controller.setLooping(true);
      // Gone while it was opening: the card scrolled away, or the source
      // changed under it.
      if (!mounted || _controller != controller) return;
      await controller.play();
      setState(() => _ready = true);
    } catch (error) {
      // The still underneath is the fallback; nothing to show the viewer.
      debugPrint('Card loop failed to play: $error');
    }
  }

  void _stop() {
    _controller?.dispose();
    _controller = null;
    _ready = false;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final size = controller?.value.size;
    if (!_ready || controller == null || size == null || size.isEmpty) {
      return const SizedBox.shrink();
    }
    // Cover, the way the still is drawn, so the two line up exactly and the
    // card keeps the shape its photo gave it.
    return IgnorePointer(
      child: ClipRect(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: VideoPlayer(controller),
          ),
        ),
      ),
    );
  }
}
