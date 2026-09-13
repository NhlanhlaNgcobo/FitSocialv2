import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/quick_toast.dart';
import '../application/pulse_providers.dart';
import '../data/pulse_frame_renderer.dart';
import '../data/pulse_media_picker.dart';
import '../domain/pulse_models.dart';
import '../domain/pulse_text_style.dart';
import 'pulse_photo_editor.dart';
import 'pulse_photo_frame.dart';
import 'pulse_share_controls.dart';
import 'pulse_text_tool.dart';

/// Where a Pulse gets made: a written card, a photo, or a clip.
///
/// Built the way Instagram builds its story composer — the canvas is the
/// screen, edge to edge, and every control floats on top of it. Nothing is
/// laid out *around* the canvas, which is what keeps the keyboard from
/// squeezing the whole screen when someone starts typing.
class PulseComposerScreen extends ConsumerStatefulWidget {
  const PulseComposerScreen({super.key});

  @override
  ConsumerState<PulseComposerScreen> createState() =>
      _PulseComposerScreenState();
}

class _PulseComposerScreenState extends ConsumerState<PulseComposerScreen> {
  /// The words on the Pulse — the whole message on a text card, or the text
  /// laid over a photo or clip. One controller for both: whichever kind is
  /// being made, there is only ever one piece of writing on it.
  final TextEditingController _textController = TextEditingController();

  /// How and where those words are drawn. Owned here rather than by the text
  /// tool because the same value goes on to the rasteriser and the draft.
  PulseTextStyle _textStyle = PulseTextStyle.defaults;

  /// Whether the text tool has the screen. While it does, the words are being
  /// typed in the middle over a dimmed canvas; otherwise they sit on the
  /// canvas as a sticker.
  bool _editingText = false;

  // A Pulse is a camera format first and a writing format second, so the
  // composer opens on photo mode — but on the capture screen, with the shutter
  // waiting, not in the camera itself. Throwing the OS camera up on arrival
  // takes the screen over before anyone has said they want a photo, and
  // dismissing it reads as leaving the composer rather than landing in it.
  PulseMediaType _mode = PulseMediaType.photo;
  String _gradientKey = PulseGradient.ember.key;
  String? _mediaPath;
  Duration? _videoDuration;
  double? _videoAspectRatio;

  /// Wraps the canvas so the framing someone pinched into place can be
  /// rasterised exactly as they left it.
  final GlobalKey _canvasKey = GlobalKey();
  VideoPlayerController? _videoController;
  bool _busy = false;

  @override
  void dispose() {
    _textController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  PulseGradient get _gradient => PulseGradient.fromKey(_gradientKey);

  bool get _hasMedia => (_mediaPath ?? '').isNotEmpty;

  bool get _hasText => _textController.text.trim().isNotEmpty;

  bool get _canShare {
    if (_busy || _editingText) return false;
    if (_mode == PulseMediaType.text) return _hasText;
    return _hasMedia;
  }

  void _switchMode(PulseMediaType mode) {
    if (mode == _mode) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _mode = mode;
      // Media belongs to the mode that picked it — a photo must not linger
      // behind the video tab, where Share would upload it as an .mp4. The
      // writing goes with it: words placed over a photo were placed for that
      // photo, and would land somewhere meaningless on a blank card.
      _clearMedia();
      _clearText();
    });
  }

  void _clearText() {
    _textController.clear();
    _textStyle = PulseTextStyle.defaults;
    _editingText = false;
  }

  void _openTextTool() {
    if (_editingText) return;
    setState(() => _editingText = true);
  }

  void _closeTextTool() {
    FocusScope.of(context).unfocus();
    setState(() {
      _editingText = false;
      // Whitespace is not a message. Cleared rather than kept, so a stray
      // space does not leave an invisible sticker that still counts as text.
      if (!_hasText) _textController.clear();
    });
  }

  void _clearMedia() {
    _videoController?.dispose();
    _videoController = null;
    _mediaPath = null;
    _videoDuration = null;
    _videoAspectRatio = null;
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final String? path;
    try {
      path = await PulseMediaPicker.pickPhoto(source: source);
    } catch (_) {
      // A denied permission or a device with no camera lands here. The capture
      // screen is already behind this, so falling back to it is enough.
      if (!mounted) return;
      _showMessage(
        source == ImageSource.camera
            ? "The camera isn't available. Try uploading from your gallery."
            : "That gallery couldn't be opened.",
      );
      return;
    }
    if (path == null || !mounted) return;
    setState(() {
      _clearMedia();
      _mode = PulseMediaType.photo;
      _mediaPath = path;
    });
  }

  Future<void> _pickVideo(ImageSource source) async {
    final String? path;
    try {
      path = await PulseMediaPicker.pickVideo(source: source);
    } catch (_) {
      if (!mounted) return;
      _showMessage(
        source == ImageSource.camera
            ? "The camera isn't available. Try uploading from your gallery."
            : "That gallery couldn't be opened.",
      );
      return;
    }
    if (path == null || !mounted) return;

    setState(() => _busy = true);
    final controller = kIsWeb
        ? VideoPlayerController.networkUrl(Uri.parse(path))
        : VideoPlayerController.file(File(path));

    try {
      await controller.initialize();
    } catch (_) {
      await controller.dispose();
      if (!mounted) return;
      setState(() => _busy = false);
      _showMessage("That video couldn't be opened. Try another clip.");
      return;
    }

    final duration = controller.value.duration;
    // The picker's maxDuration only caps recording; a clip chosen from the
    // gallery arrives at whatever length it already was, so the limit has to
    // be enforced here too.
    if (duration > PulseTiming.maxVideoDuration) {
      await controller.dispose();
      if (!mounted) return;
      setState(() => _busy = false);
      _showMessage(
        'Pulse clips max out at '
        '${PulseTiming.maxVideoDuration.inSeconds} seconds.',
      );
      return;
    }

    await controller.setLooping(true);
    await controller.setVolume(1);
    await controller.play();
    if (!mounted) {
      await controller.dispose();
      return;
    }

    setState(() {
      _clearMedia();
      _mediaPath = path;
      _videoController = controller;
      _videoDuration = duration;
      _videoAspectRatio = controller.value.aspectRatio;
      _busy = false;
    });
  }

  Future<void> _share() async {
    if (!_canShare) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);

    var mediaPath = _mediaPath;
    var aspectRatio = _videoAspectRatio;

    if (_mode == PulseMediaType.photo) {
      // What leaves the phone is the canvas, not the file that was picked:
      // the pinch, the drag and the blurred backdrop are all in these pixels,
      // so every viewer sees the frame that was composed here.
      final PulseFrameFile framed;
      try {
        framed = await renderPulseFrame(_canvasKey);
      } on PulseFrameRenderException catch (error) {
        if (!mounted) return;
        setState(() => _busy = false);
        _showMessage(error.message);
        return;
      }
      if (!mounted) return;
      mediaPath = framed.path;
      aspectRatio = framed.aspectRatio;
    }

    // On a photo the words are already in the pixels — the canvas above was
    // rasterised with the sticker on it — so the document carries none, or
    // the viewer would draw them twice. A clip cannot be baked, so its words
    // travel with their style and the viewer lays them over the video.
    final bakedIntoPhoto = _mode == PulseMediaType.photo;
    final draft = PulseDraft(
      type: _mode,
      localFilePath: mediaPath,
      text: bakedIntoPhoto ? '' : _textController.text,
      textStyle: bakedIntoPhoto ? null : _textStyle,
      gradientKey: _gradientKey,
      videoDuration: _videoDuration,
      aspectRatio: aspectRatio,
    );

    try {
      await ref.read(pulseActionsProvider).publish(draft);
      if (!mounted) return;
      // The same acknowledgement a deleted post gets: a floating pill on the
      // root overlay rather than a snackbar. This route is about to pop, so the
      // overlay is grabbed first — it outlives the screen that triggered it,
      // and a snackbar anchored to this Scaffold would leave with it.
      final overlay = Overlay.maybeOf(context, rootOverlay: true);
      if (overlay != null) {
        showQuickToastOn(
          overlay,
          'Pulse is live for 24 hours',
          icon: Icons.bolt_rounded,
          tone: ToastTone.success,
        );
      }
      context.pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showMessage(error.toString());
    }
  }

  void _showMessage(String message) {
    showQuickToast(
      context,
      message,
      icon: Icons.error_outline_rounded,
      tone: ToastTone.danger,
    );
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    return PopScope(
      // Back while the text tool is open closes the tool, not the composer:
      // the words are kept, and the card is where they were being put.
      canPop: !_editingText,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closeTextTool();
      },
      child: Scaffold(
        backgroundColor: AppColors.mediaBackdrop,
        // The keyboard overlays the canvas instead of resizing the screen. With
        // resize on, every control has to be re-fitted into the shrinking space
        // and the layout collapses — the text tool positions itself above the
        // keyboard by hand instead.
        resizeToAvoidBottomInset: false,
        body: Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(key: _canvasKey, child: _buildCanvas()),
            const _ControlScrim(),
            // The text tool brings its own chrome and takes the whole screen
            // while it is open: the words are the only thing being worked on,
            // and the palette, Share and the mode switch would only crowd them.
            if (_editingText)
              PulseTextEditor(
                controller: _textController,
                style: _textStyle,
                onStyleChanged: (style) => setState(() => _textStyle = style),
                onDone: _closeTextTool,
                keyboardInset: keyboardInset,
              )
            else ...[
              SafeArea(
                bottom: false,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: _buildTopBar(),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(top: false, child: _buildControls()),
              ),
            ],
            if (_busy)
              const ColoredBox(
                color: Color(0xAA050505),
                child: Center(
                  child: CircularProgressIndicator(
                    color: AppColors.orangeBright,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    // Text is offered wherever there is something to write on: a blank card,
    // or a photo or clip already chosen. Not on the capture screen — there is
    // nothing there yet to put words over.
    final canWrite = _mode == PulseMediaType.text || _hasMedia;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            onPressed: () => context.pop(),
            icon: const Icon(Icons.close_rounded),
            color: AppColors.onMedia,
            tooltip: 'Close',
          ),
          const Spacer(),
          // The tools stack down the right edge, the way a story composer
          // keeps its rail: text first, then whatever applies to the canvas
          // underneath it.
          Column(
            children: [
              if (canWrite) PulseTextToolButton(onTap: _openTextTool),
              if (_mode == PulseMediaType.text)
                PulseBackgroundButton(onTap: _cycleGradient),
              if (_hasMedia)
                IconButton(
                  onPressed: () => setState(_clearMedia),
                  icon: const Icon(Icons.refresh_rounded),
                  color: AppColors.onMedia,
                  tooltip: 'Choose something else',
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Steps the text card on to the next backdrop, wrapping round at the end.
  /// One tap per colour rather than a palette to pick from: the set is small
  /// enough to walk through, and a tap is faster than a scroll and a choice.
  void _cycleGradient() {
    const all = PulseGradient.all;
    final index = all.indexWhere((gradient) => gradient.key == _gradientKey);
    setState(() => _gradientKey = all[(index + 1) % all.length].key);
  }

  /// The words, set down where their style says, over whatever [background]
  /// is. Nothing while the text tool is open — the tool is showing them in
  /// the middle of the screen, and a second copy on the canvas would sit
  /// behind the dimmer as a ghost.
  Widget _withText(Widget background) {
    if (_editingText || !_hasText) return background;
    return Stack(
      fit: StackFit.expand,
      children: [
        background,
        PulseTextSticker(
          text: _textController.text,
          style: _textStyle,
          onStyleChanged: (style) => setState(() => _textStyle = style),
          onTap: _openTextTool,
        ),
      ],
    );
  }

  Widget _buildCanvas() {
    switch (_mode) {
      // Neither is reachable from here: sharing a post starts from the post
      // and sharing a track starts from the player, and both land on their own
      // screen. Listed so adding a Pulse kind can't silently fall through this
      // switch.
      case PulseMediaType.post:
      case PulseMediaType.music:
        return const SizedBox.shrink();

      case PulseMediaType.text:
        return GestureDetector(
          // The whole canvas is the way in, not just the line of hint text.
          // Deliberately not opened on arrival: the background is picked
          // before the writing starts, and a keyboard on open would bury the
          // palette behind it.
          onTap: _openTextTool,
          behavior: HitTestBehavior.opaque,
          child: _withText(
            DecoratedBox(
              decoration: BoxDecoration(gradient: _gradient.linear),
              child: _hasText || _editingText
                  ? const SizedBox.expand()
                  : const _WritingPrompt(),
            ),
          ),
        );

      case PulseMediaType.photo:
        final path = _mediaPath;
        if (path == null) {
          return _CaptureCanvas(
            icon: Icons.photo_camera_rounded,
            title: 'Capture a Pulse',
            subtitle:
                'Tap the shutter to shoot.\nIt disappears after 24 hours.',
            captureLabel: 'Take a photo',
            onCamera: () => _pickPhoto(ImageSource.camera),
            onGallery: () => _pickPhoto(ImageSource.gallery),
          );
        }
        // The sticker rides inside the same boundary as the photo, which is
        // what bakes it into the frame on Share.
        return _withText(
          _MediaCanvas(
            child: PulsePhotoEditor(image: pulseLocalPhoto(path)),
          ),
        );

      case PulseMediaType.video:
        final controller = _videoController;
        if (controller == null) {
          return _CaptureCanvas(
            icon: Icons.videocam_rounded,
            title: 'Record a Pulse',
            subtitle: 'Clips run up to '
                '${PulseTiming.maxVideoDuration.inSeconds} seconds.',
            captureLabel: 'Record a clip',
            onCamera: () => _pickVideo(ImageSource.camera),
            onGallery: () => _pickVideo(ImageSource.gallery),
          );
        }
        return _withText(
          _MediaCanvas(
            child: FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: controller.value.size.width,
                height: controller.value.size.height,
                child: VideoPlayer(controller),
              ),
            ),
          ),
        );
    }
  }

  Widget _buildControls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Share sits above the mode switch, which holds the bottom edge
          // where a tab bar belongs: the kind of Pulse is picked once on the
          // way in, but Share is read on the way out.
          //
          // Nothing to share yet on an empty camera screen, and a dead grey
          // button under the shutter is just noise. It arrives with the shot.
          if (_mode == PulseMediaType.text || _hasMedia) ...[
            PulseShareButton(onPressed: _canShare ? _share : null),
            const SizedBox(height: AppSpacing.md),
          ],
          _ModeSelector(mode: _mode, onSelected: _switchMode),
        ],
      ),
    );
  }
}

/// What a blank text card says before anything is written on it.
///
/// Plain [Text] rather than a field's hint: the field lives in the text tool
/// now, and a tap anywhere on the card opens it.
class _WritingPrompt extends StatelessWidget {
  const _WritingPrompt();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'Say something',
        style: TextStyle(
          color: Color(0x8AFFFFFF),
          fontSize: 34,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// Darkens the top and bottom edges so white controls stay legible over a
/// bright photo without putting a panel behind them.
class _ControlScrim extends StatelessWidget {
  const _ControlScrim();

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0x73000000),
              Color(0x00000000),
              Color(0x00000000),
              Color(0xA6000000),
            ],
            stops: [0, 0.18, 0.55, 1],
          ),
        ),
      ),
    );
  }
}

/// Where the composer opens, and what the user comes back to after cancelling
/// a shot: a shutter, and the gallery as the way round it.
///
/// Dark rather than gradient-filled on purpose — this is the lens, not a
/// canvas, and a lit orange backdrop would swallow the orange shutter.
class _CaptureCanvas extends StatelessWidget {
  const _CaptureCanvas({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.captureLabel,
    required this.onCamera,
    required this.onGallery,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String captureLabel;
  final VoidCallback onCamera;
  final VoidCallback onGallery;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.mediaBackdrop,
        gradient: RadialGradient(
          center: Alignment(0, -0.2),
          radius: 0.95,
          colors: [Color(0x2EFF6B1A), Color(0x00050505)],
        ),
      ),
      child: SafeArea(
        child: Padding(
          // The bottom inset keeps this block clear of the mode selector
          // floating over it, so the shutter centres in the space that is
          // actually free rather than under the controls.
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            116,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ShutterButton(icon: icon, onTap: onCamera),
              const SizedBox(height: AppSpacing.lg),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.onMedia,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.onMediaMuted,
                  fontSize: 13.5,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                captureLabel.toUpperCase(),
                style: const TextStyle(
                  color: AppColors.onMediaMuted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              _GlassButton(
                icon: Icons.photo_library_rounded,
                label: 'Upload from gallery',
                onTap: onGallery,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The shutter: an orange disc breathing inside two slow rings — the same
/// pulse the tray's live ring carries, at the size of a thumb.
class _ShutterButton extends StatefulWidget {
  const _ShutterButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_ShutterButton> createState() => _ShutterButtonState();
}

class _ShutterButtonState extends State<_ShutterButton>
    with SingleTickerProviderStateMixin {
  static const double _discSize = 92;
  static const double _haloSize = 168;

  late final AnimationController _controller;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      child: SizedBox(
        width: _haloSize,
        height: _haloSize,
        child: Stack(
          alignment: Alignment.center,
          children: [
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    // Two rings, half a cycle apart, so one is always leaving
                    // as the other starts.
                    for (final offset in const [0.0, 0.5])
                      _halo((_controller.value + offset) % 1),
                  ],
                );
              },
            ),
            AnimatedScale(
              scale: _pressed ? 0.92 : 1,
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              child: Container(
                width: _discSize,
                height: _discSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.orangeBright, AppColors.orange],
                  ),
                  border: Border.all(
                    color: AppColors.onMedia.withValues(alpha: 0.9),
                    width: 3,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.orangeBright.withValues(alpha: 0.45),
                      blurRadius: 28,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Icon(
                  widget.icon,
                  color: AppColors.onMedia,
                  size: 34,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _halo(double t) {
    final size = _discSize + (_haloSize - _discSize) * t;
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: AppColors.orangeBright.withValues(alpha: 0.5 * (1 - t)),
            width: 1.5,
          ),
        ),
      ),
    );
  }
}

/// A translucent pill for the secondary way in. Sits on the media backdrop, so
/// its white is fixed in both themes.
class _GlassButton extends StatelessWidget {
  const _GlassButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.onMedia.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.onMedia.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: AppColors.onMedia),
              const SizedBox(width: 10),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.onMedia,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A chosen photo or clip, filling the frame.
class _MediaCanvas extends StatelessWidget {
  const _MediaCanvas({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.mediaBackdrop,
      child: SizedBox.expand(child: child),
    );
  }
}

/// The mode switch, cut like the app's tab bar: a floating capsule of icons
/// with a lifted pane tracking the selected one.
///
/// Sized to its three icons rather than stretched across the screen — three
/// glyphs in a full-width bar float apart from each other and stop reading
/// as one control. Smoked glass rather than [LiquidGlass]: that pane takes
/// its tint from the theme, and this screen is a dark media surface whatever
/// the theme says, so the chrome here is drawn in the composer's own black.
class _ModeSelector extends StatelessWidget {
  const _ModeSelector({required this.mode, required this.onSelected});

  final PulseMediaType mode;
  final ValueChanged<PulseMediaType> onSelected;

  // Photo leads: it is where the composer opens, and the selected tab reads
  // wrong sitting in the middle of the row on arrival.
  static const _options = <(PulseMediaType, IconData, String)>[
    (PulseMediaType.photo, Icons.photo_camera_rounded, 'Photo'),
    (PulseMediaType.video, Icons.videocam_rounded, 'Video'),
    (PulseMediaType.text, Icons.format_quote_rounded, 'Text'),
  ];

  static const _duration = Duration(milliseconds: 220);

  static const double _height = 52;
  static const double _tabWidth = 56;
  static const double _inset = 4;
  static const double _edge = 1;
  static const _radius = BorderRadius.all(Radius.circular(_height / 2));

  @override
  Widget build(BuildContext context) {
    final selectedIndex = _options.indexWhere((option) => option.$1 == mode);

    return DecoratedBox(
      // Outside the clip on purpose: a shadow drawn inside ClipRRect would be
      // clipped away by the very shape casting it.
      decoration: const BoxDecoration(
        borderRadius: _radius,
        boxShadow: [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: _radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            height: _height,
            // The border is drawn inside the box, so it is counted in.
            width: _tabWidth * _options.length + (_inset + _edge) * 2,
            padding: const EdgeInsets.all(_inset),
            decoration: BoxDecoration(
              borderRadius: _radius,
              color: const Color(0x8C000000),
              border: Border.all(
                color: const Color(0x33FFFFFF),
                width: _edge,
              ),
            ),
            child: Stack(
              children: [
                // One pane that slides between the tabs rather than three
                // that blink on and off: the travel is what says these are
                // three positions of one control, not three separate buttons.
                AnimatedPositioned(
                  duration: _duration,
                  curve: Curves.easeOutCubic,
                  left: _tabWidth * selectedIndex,
                  width: _tabWidth,
                  top: 0,
                  bottom: 0,
                  child: const DecoratedBox(
                    // A white lift, as the app's bar does it, rather than an
                    // orange slab: the one lit orange thing down here should
                    // be Share.
                    decoration: BoxDecoration(
                      color: Color(0x24FFFFFF),
                      borderRadius: BorderRadius.all(Radius.circular(22)),
                      border: Border.fromBorderSide(
                        BorderSide(color: Color(0x26FFFFFF)),
                      ),
                    ),
                  ),
                ),
                // Stretched across the cross axis, so each tab's tap target
                // is the whole height of the bar.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (type, icon, label) in _options)
                      SizedBox(
                        width: _tabWidth,
                        child: _ModeTab(
                          icon: icon,
                          label: label,
                          selected: type == mode,
                          onTap: () => onSelected(type),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeTab extends StatelessWidget {
  const _ModeTab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;

  /// Read out, and shown on a long press, but never drawn: the icons carry
  /// the bar on their own, as the app's do.
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Tooltip(
        message: label,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          // The icon brightens on the same curve the pane travels on, so it
          // is lit by the time the pane arrives under it.
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: selected ? 1 : 0),
            duration: _ModeSelector._duration,
            curve: Curves.easeOutCubic,
            builder: (context, t, _) {
              return Center(
                child: Icon(
                  icon,
                  size: 22,
                  color: Color.lerp(
                    const Color(0x9EFFFFFF),
                    AppColors.onMedia,
                    t,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
