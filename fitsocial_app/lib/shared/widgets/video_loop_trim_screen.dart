import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../../app/theme/app_palette.dart';
import '../../app/theme/app_spacing.dart';
import '../services/video_loop_maker.dart';
import 'quick_toast.dart';

/// Picks a video and cuts it into a card loop. Returns the loop's first
/// frame — the path every background picker already knows how to treat as a
/// photo — or null when the user backed out anywhere along the way.
Future<String?> pickVideoLoop(
  BuildContext context, {
  required ImageSource source,
}) async {
  final picked = await ImagePicker().pickVideo(
    source: source,
    // Recording stops itself here; a gallery clip is checked on the trim
    // screen instead, since the picker does not cut those.
    maxDuration: VideoLoopMaker.maxSource,
  );
  if (picked == null || !context.mounted) return null;
  final loop = await Navigator.of(context).push<VideoLoop>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => VideoLoopTrimScreen(path: picked.path),
    ),
  );
  return loop?.posterPath;
}

/// Choose which few seconds of a clip loop behind the card.
///
/// The preview plays only the chosen window, round and round, so what is on
/// screen is exactly what the card will do. One slider for where it starts
/// and three lengths — a loop has no other decisions worth asking about.
class VideoLoopTrimScreen extends StatefulWidget {
  const VideoLoopTrimScreen({required this.path, super.key});

  final String path;

  @override
  State<VideoLoopTrimScreen> createState() => _VideoLoopTrimScreenState();
}

class _VideoLoopTrimScreenState extends State<VideoLoopTrimScreen> {
  late final VideoPlayerController _controller =
      VideoPlayerController.file(File(widget.path));

  Duration _start = Duration.zero;
  Duration _length = VideoLoopMaker.lengths.last;
  bool _ready = false;
  bool _working = false;
  String? _problem;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      await _controller.initialize();
      await _controller.setVolume(0);
      final duration = _controller.value.duration;
      if (duration > VideoLoopMaker.maxSource + const Duration(seconds: 1)) {
        setState(() => _problem = 'Pick a clip under two minutes long.');
        return;
      }
      _controller.addListener(_keepInWindow);
      await _controller.play();
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      if (mounted) setState(() => _problem = "That video couldn't be opened.");
    }
  }

  Duration get _duration => _controller.value.duration;

  /// The loop's length, never longer than the clip itself.
  Duration get _effectiveLength => _length > _duration ? _duration : _length;

  /// Holds the preview inside the chosen window.
  void _keepInWindow() {
    final position = _controller.value.position;
    final end = _start + _effectiveLength;
    if (position >= end || position < _start) {
      unawaited(_controller.seekTo(_start));
    }
  }

  Future<void> _use() async {
    setState(() => _working = true);
    try {
      final loop = await VideoLoopMaker.make(
        path: widget.path,
        start: _start,
        length: _effectiveLength,
      );
      if (!mounted) return;
      Navigator.of(context).pop(loop);
    } catch (_) {
      if (!mounted) return;
      setState(() => _working = false);
      showQuickToast(
        context,
        "Couldn't make a loop from that clip. Try another.",
        icon: Icons.error_outline_rounded,
        tone: ToastTone.danger,
      );
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_keepInWindow);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final problem = _problem;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Card loop'),
      ),
      body: problem != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Text(
                  problem,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
              ),
            )
          : !_ready
              ? const Center(child: CircularProgressIndicator())
              : SafeArea(
                  child: Column(
                    children: [
                      Expanded(
                        child: Center(
                          child: AspectRatio(
                            aspectRatio: _controller.value.aspectRatio,
                            child: VideoPlayer(_controller),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.md,
                          AppSpacing.md,
                          AppSpacing.md,
                          AppSpacing.md,
                        ),
                        child: _controls(palette),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _controls(AppPalette palette) {
    final room = _duration - _effectiveLength;
    final maxStart =
        room.inMilliseconds <= 0 ? 0.0 : room.inMilliseconds / 1000;
    const label = TextStyle(
      color: Colors.white70,
      fontSize: 12,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.1,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('LENGTH', style: label),
        const SizedBox(height: AppSpacing.sm),
        SegmentedButton<Duration>(
          segments: [
            for (final length in VideoLoopMaker.lengths)
              ButtonSegment(
                value: length,
                label: Text('${length.inSeconds} s'),
              ),
          ],
          selected: {_length},
          showSelectedIcon: false,
          onSelectionChanged: _working
              ? null
              : (picked) => setState(() {
                    _length = picked.first;
                    // Keep the window inside the clip.
                    final latest = _duration - _effectiveLength;
                    if (_start > latest) {
                      _start = latest.isNegative ? Duration.zero : latest;
                    }
                    unawaited(_controller.seekTo(_start));
                  }),
        ),
        if (maxStart > 0) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            'STARTS AT ${(_start.inMilliseconds / 1000).toStringAsFixed(1)} s',
            style: label,
          ),
          Slider(
            value: (_start.inMilliseconds / 1000).clamp(0, maxStart).toDouble(),
            max: maxStart,
            activeColor: palette.brand,
            onChanged: _working
                ? null
                : (seconds) => setState(
                      () => _start = Duration(
                        milliseconds: (seconds * 1000).round(),
                      ),
                    ),
            onChangeEnd: (_) => unawaited(_controller.seekTo(_start)),
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        FilledButton(
          onPressed: _working ? null : _use,
          style: FilledButton.styleFrom(
            backgroundColor: palette.brand,
            minimumSize: const Size.fromHeight(50),
          ),
          child: _working
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text(
                  'Use this loop',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
        ),
      ],
    );
  }
}
