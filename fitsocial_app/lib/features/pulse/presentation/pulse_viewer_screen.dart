import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/avatar.dart';
import '../application/pulse_providers.dart';
import '../domain/pulse_models.dart';
import 'pulse_text.dart';
import 'pulse_viewers_sheet.dart';

/// Full-screen Pulse playback.
///
/// Follows the interaction model people already know from Instagram Stories:
/// stills hold for five seconds and video runs its own length, a tap on the
/// right advances and the left goes back, holding pauses, a downward swipe
/// dismisses, and swiping sideways turns to the next person on a cube.
class PulseViewerScreen extends ConsumerStatefulWidget {
  const PulseViewerScreen({required this.initialAuthorId, super.key});

  final String initialAuthorId;

  @override
  ConsumerState<PulseViewerScreen> createState() => _PulseViewerScreenState();
}

class _PulseViewerScreenState extends ConsumerState<PulseViewerScreen>
    with SingleTickerProviderStateMixin {
  late final PageController _pageController;
  late final AnimationController _frameProgress;

  /// The tray as it stood when the viewer opened.
  ///
  /// Deliberately a snapshot, not a live watch: marking Pulses seen re-ranks
  /// the tray, and re-ranking mid-playback would reshuffle the pages under the
  /// viewer's thumb.
  List<PulseTrayEntry> _entries = const [];

  int _entryIndex = 0;
  int _segmentIndex = 0;
  VideoPlayerController? _videoController;
  bool _paused = false;
  bool _advancing = false;
  bool _closing = false;

  /// Bumped on every segment change so a slow load that resolves after the
  /// user has already moved on gets discarded instead of applied.
  int _token = 0;

  @override
  void initState() {
    super.initState();

    final entries = ref.read(pulseTrayProvider).valueOrNull ?? const [];
    final index =
        entries.indexWhere((entry) => entry.authorId == widget.initialAuthorId);

    _entries = entries;
    _entryIndex = index < 0 ? 0 : index;
    _pageController = PageController(initialPage: _entryIndex);
    _frameProgress = AnimationController(
      vsync: this,
      duration: PulseTiming.frameDuration,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) _advance();
      });

    if (index < 0) {
      // The ring expired or was deleted between the tap and this frame.
      WidgetsBinding.instance.addPostFrameCallback((_) => _close());
      return;
    }

    // Instagram picks up where you left off rather than replaying from the
    // top, which is what firstUnseenIndex encodes.
    _segmentIndex = entries[_entryIndex].firstUnseenIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) => _startSegment());
  }

  @override
  void dispose() {
    _frameProgress.dispose();
    _videoController?.removeListener(_onVideoTick);
    _videoController?.dispose();
    _pageController.dispose();
    super.dispose();
  }

  PulseTrayEntry? get _currentEntry =>
      _entryIndex >= 0 && _entryIndex < _entries.length
          ? _entries[_entryIndex]
          : null;

  PulseSegment? get _currentSegment {
    final entry = _currentEntry;
    if (entry == null) return null;
    if (_segmentIndex < 0 || _segmentIndex >= entry.segments.length) return null;
    return entry.segments[_segmentIndex];
  }

  Future<void> _disposeVideo() async {
    final controller = _videoController;
    if (controller == null) return;
    _videoController = null;
    controller.removeListener(_onVideoTick);
    await controller.dispose();
  }

  Future<void> _startSegment() async {
    final token = ++_token;
    _advancing = false;
    _frameProgress.stop();
    _frameProgress.value = 0;
    await _disposeVideo();

    final segment = _currentSegment;
    if (segment == null || !mounted || token != _token) return;

    // Fire-and-forget: neither the view count nor the seen cursor is worth
    // stalling playback for, and a failure on either is invisible to the user.
    final actions = ref.read(pulseActionsProvider);
    unawaited(actions.recordView(segment.id).catchError((_) {}));
    unawaited(actions.markSeen(segment).catchError((_) {}));

    if (segment.type == PulseMediaType.video && segment.hasMedia) {
      await _startVideo(segment, token);
      return;
    }

    if (segment.type == PulseMediaType.photo && segment.hasMedia) {
      // Hold the timer until the photo is actually decoded, so a slow
      // connection doesn't spend the five seconds showing a blank frame.
      try {
        await precacheImage(NetworkImage(segment.mediaUrl!), context)
            .timeout(const Duration(seconds: 8));
      } catch (_) {
        // Show whatever the image widget can manage and move on.
      }
      if (!mounted || token != _token) return;
    }

    setState(() {});
    if (!_paused) _frameProgress.forward(from: 0);
    _precacheNext();
  }

  Future<void> _startVideo(PulseSegment segment, int token) async {
    final controller =
        VideoPlayerController.networkUrl(Uri.parse(segment.mediaUrl!));
    try {
      await controller.initialize();
    } catch (_) {
      await controller.dispose();
      if (mounted && token == _token) _advance();
      return;
    }

    if (!mounted || token != _token) {
      await controller.dispose();
      return;
    }

    controller.addListener(_onVideoTick);
    if (!_paused) await controller.play();
    setState(() => _videoController = controller);
    _precacheNext();
  }

  /// Warms the next segment's photo while this one plays, so advancing lands
  /// on an image that is already decoded.
  void _precacheNext() {
    final entry = _currentEntry;
    if (entry == null) return;
    if (_segmentIndex + 1 >= entry.segments.length) return;

    final next = entry.segments[_segmentIndex + 1];
    if (next.type != PulseMediaType.photo || !next.hasMedia) return;
    precacheImage(NetworkImage(next.mediaUrl!), context).catchError((_) {});
  }

  void _onVideoTick() {
    if (_advancing) return;
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) return;

    final duration = controller.value.duration;
    if (duration <= Duration.zero) return;
    if (controller.value.position >= duration) _advance();
  }

  void _advance() {
    if (_advancing || _closing) return;
    final entry = _currentEntry;
    if (entry == null) return;

    _advancing = true;
    if (_segmentIndex + 1 < entry.segments.length) {
      setState(() => _segmentIndex++);
      _startSegment();
    } else {
      _goToEntry(_entryIndex + 1);
    }
  }

  void _back() {
    if (_closing) return;
    if (_segmentIndex > 0) {
      _advancing = true;
      setState(() => _segmentIndex--);
      _startSegment();
      return;
    }
    _goToEntry(_entryIndex - 1);
  }

  void _goToEntry(int index) {
    if (index >= _entries.length) {
      _close();
      return;
    }
    if (index < 0) {
      // Already at the very first Pulse — replay it rather than dead-ending.
      _startSegment();
      return;
    }
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeInOut,
    );
  }

  void _onPageChanged(int index) {
    if (index < 0 || index >= _entries.length) return;
    setState(() {
      _entryIndex = index;
      _segmentIndex = _entries[index].firstUnseenIndex;
      _paused = false;
    });
    _startSegment();
  }

  void _setPaused(bool paused) {
    if (_paused == paused) return;
    setState(() => _paused = paused);

    final controller = _videoController;
    if (paused) {
      _frameProgress.stop();
      controller?.pause();
      return;
    }
    if (controller != null) {
      controller.play();
    } else {
      _frameProgress.forward();
    }
  }

  void _close() {
    if (_closing) return;
    _closing = true;
    if (mounted && context.canPop()) context.pop();
  }

  void _handleTap(TapUpDetails details, BoxConstraints constraints) {
    // Instagram's split: a narrow strip on the left goes back, the rest
    // advances, because forward is by far the more common intent.
    if (details.localPosition.dx < constraints.maxWidth * 0.32) {
      _back();
    } else {
      _advance();
    }
  }

  Future<void> _confirmDelete(PulseSegment segment) async {
    _setPaused(true);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.palette.surface,
        title: const Text('Delete this Pulse?'),
        content: const Text(
          "It will disappear for everyone straight away. This can't be undone.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Delete',
              style: TextStyle(color: context.palette.danger),
            ),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (confirmed != true) {
      _setPaused(false);
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(pulseActionsProvider).delete(segment.id);
      messenger.showSnackBar(const SnackBar(content: Text('Pulse deleted.')));
      // The snapshot this screen plays from still holds the deleted segment,
      // so leave rather than show something that no longer exists.
      _close();
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
      _setPaused(false);
    }
  }

  void _openViewers(PulseSegment segment) {
    _setPaused(true);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PulseViewersSheet(pulseId: segment.id),
    ).whenComplete(() {
      if (mounted) _setPaused(false);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_entries.isEmpty) {
      return const Scaffold(
        backgroundColor: AppColors.mediaBackdrop,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.orangeBright),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.mediaBackdrop,
      body: LayoutBuilder(
        builder: (context, constraints) {
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) => _handleTap(details, constraints),
            onLongPressStart: (_) => _setPaused(true),
            onLongPressEnd: (_) => _setPaused(false),
            onLongPressCancel: () => _setPaused(false),
            onVerticalDragEnd: (details) {
              if ((details.primaryVelocity ?? 0) > 220) _close();
            },
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: _onPageChanged,
              itemCount: _entries.length,
              itemBuilder: (context, index) {
                return _CubePage(
                  controller: _pageController,
                  index: index,
                  fallbackPage: _entryIndex,
                  child: _buildEntry(index),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildEntry(int index) {
    final entry = _entries[index];
    final isActive = index == _entryIndex;
    // Off-screen pages show their first frame with no player attached; they
    // are only visible for the length of a swipe.
    final segmentIndex = isActive ? _segmentIndex : entry.firstUnseenIndex;
    final segment = entry.segments[
        segmentIndex.clamp(0, entry.segments.length - 1)];

    return Stack(
      fit: StackFit.expand,
      children: [
        _PulseFrame(
          segment: segment,
          videoController: isActive ? _videoController : null,
        ),
        // Scrim: white type has to stay readable over whatever photo lands
        // underneath it.
        const _TopScrim(),
        AnimatedOpacity(
          opacity: _paused && isActive ? 0 : 1,
          duration: const Duration(milliseconds: 180),
          child: _buildChrome(entry, segment, isActive, segmentIndex),
        ),
      ],
    );
  }

  Widget _buildChrome(
    PulseTrayEntry entry,
    PulseSegment segment,
    bool isActive,
    int segmentIndex,
  ) {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.sm,
            ),
            child: _buildProgressBars(entry, isActive, segmentIndex),
          ),
          _PulseHeader(
            entry: entry,
            segment: segment,
            onClose: _close,
            onDelete: entry.isOwn ? () => _confirmDelete(segment) : null,
          ),
          const Spacer(),
          if (segment.type != PulseMediaType.text &&
              segment.text.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: PulseCaption(text: segment.text),
            ),
          if (entry.isOwn) ...[
            const SizedBox(height: AppSpacing.md),
            _ViewCountButton(
              count: segment.viewCount,
              onPressed: () => _openViewers(segment),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }

  Widget _buildProgressBars(
    PulseTrayEntry entry,
    bool isActive,
    int segmentIndex,
  ) {
    if (!isActive) {
      return _ProgressBars(
        count: entry.segments.length,
        activeIndex: segmentIndex,
        progress: 0,
      );
    }

    final controller = _videoController;
    if (controller != null) {
      // Video drives its own bar from real playback position, so buffering
      // shows as a stalled bar instead of one that runs ahead of the picture.
      return ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: controller,
        builder: (context, value, _) {
          final total = value.duration.inMilliseconds;
          final progress = total <= 0
              ? 0.0
              : (value.position.inMilliseconds / total).clamp(0.0, 1.0);
          return _ProgressBars(
            count: entry.segments.length,
            activeIndex: segmentIndex,
            progress: progress,
          );
        },
      );
    }

    return AnimatedBuilder(
      animation: _frameProgress,
      builder: (context, _) => _ProgressBars(
        count: entry.segments.length,
        activeIndex: segmentIndex,
        progress: _frameProgress.value,
      ),
    );
  }
}

/// Wraps a page in the rotating-cube transition Instagram uses between
/// authors, so moving from one person to the next reads as a turn rather than
/// a slide.
class _CubePage extends StatelessWidget {
  const _CubePage({
    required this.controller,
    required this.index,
    required this.fallbackPage,
    required this.child,
  });

  final PageController controller;
  final int index;

  /// Used before the controller has been laid out, when `page` is unreadable.
  final int fallbackPage;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final page = controller.hasClients &&
                controller.position.haveDimensions
            ? (controller.page ?? fallbackPage.toDouble())
            : fallbackPage.toDouble();
        final delta = (index - page).clamp(-1.0, 1.0);

        final transform = Matrix4.identity()
          // Perspective — without it the rotation flattens into a squash.
          ..setEntry(3, 2, 0.0015)
          ..rotateY(-delta * math.pi / 2);

        return Transform(
          // Each face hinges on the edge it shares with the page in view.
          alignment:
              delta <= 0 ? Alignment.centerRight : Alignment.centerLeft,
          transform: transform,
          child: Stack(
            fit: StackFit.expand,
            children: [
              child,
              // The turning face falls into shadow, which is what sells the
              // shape as solid.
              IgnorePointer(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: delta.abs() * 0.6),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// One Pulse, rendered full-bleed.
class _PulseFrame extends StatelessWidget {
  const _PulseFrame({required this.segment, this.videoController});

  final PulseSegment segment;
  final VideoPlayerController? videoController;

  @override
  Widget build(BuildContext context) {
    switch (segment.type) {
      case PulseMediaType.text:
        return DecoratedBox(
          decoration: BoxDecoration(gradient: segment.gradient.linear),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Center(
              child: Text(
                segment.text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.onMedia,
                  fontSize: pulseTextSize(segment.text),
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
            ),
          ),
        );

      case PulseMediaType.photo:
        return ColoredBox(
          color: AppColors.mediaBackdrop,
          child: segment.hasMedia
              ? Image.network(
                  segment.mediaUrl!,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  errorBuilder: (_, __, ___) =>
                      const _FrameMessage(label: 'This photo is unavailable.'),
                  loadingBuilder: (_, child, progress) =>
                      progress == null ? child : const _FrameSpinner(),
                )
              : const _FrameMessage(label: 'This Pulse is unavailable.'),
        );

      case PulseMediaType.video:
        final controller = videoController;
        if (controller == null || !controller.value.isInitialized) {
          return const ColoredBox(
            color: AppColors.mediaBackdrop,
            child: _FrameSpinner(),
          );
        }
        return ColoredBox(
          color: AppColors.mediaBackdrop,
          child: FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: controller.value.size.width,
              height: controller.value.size.height,
              child: VideoPlayer(controller),
            ),
          ),
        );
    }
  }
}

class _TopScrim extends StatelessWidget {
  const _TopScrim();

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x99000000), Color(0x00000000)],
            stops: [0, 0.28],
          ),
        ),
      ),
    );
  }
}

class _ProgressBars extends StatelessWidget {
  const _ProgressBars({
    required this.count,
    required this.activeIndex,
    required this.progress,
  });

  final int count;
  final int activeIndex;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < count; i++) ...[
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: i < activeIndex ? 1 : (i == activeIndex ? progress : 0),
                minHeight: 2.5,
                backgroundColor: const Color(0x4DFFFFFF),
                valueColor:
                    const AlwaysStoppedAnimation<Color>(AppColors.onMedia),
              ),
            ),
          ),
          if (i != count - 1) const SizedBox(width: 3),
        ],
      ],
    );
  }
}

class _PulseHeader extends StatelessWidget {
  const _PulseHeader({
    required this.entry,
    required this.segment,
    required this.onClose,
    this.onDelete,
  });

  final PulseTrayEntry entry;
  final PulseSegment segment;
  final VoidCallback onClose;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Row(
        children: [
          Avatar(
            initials: pulseInitials(entry.authorName),
            imageUrl: entry.authorAvatarUrl,
            size: 34,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              entry.isOwn ? 'Pulse' : entry.authorName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.onMedia,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            pulseAgeLabel(segment.createdAt, DateTime.now()),
            style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 12),
          ),
          if (onDelete != null)
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded),
              color: AppColors.onMedia,
              tooltip: 'Delete Pulse',
            ),
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded),
            color: AppColors.onMedia,
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }
}

class _ViewCountButton extends StatelessWidget {
  const _ViewCountButton({required this.count, required this.onPressed});

  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      style: TextButton.styleFrom(foregroundColor: AppColors.onMedia),
      icon: const Icon(Icons.visibility_outlined, size: 18),
      label: Text(
        count == 1 ? '1 view' : '$count views',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _FrameSpinner extends StatelessWidget {
  const _FrameSpinner();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(color: AppColors.orangeBright),
    );
  }
}

class _FrameMessage extends StatelessWidget {
  const _FrameMessage({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.onMediaMuted),
        ),
      ),
    );
  }
}
