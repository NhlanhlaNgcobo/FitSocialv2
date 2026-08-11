import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../application/pulse_providers.dart';
import '../data/pulse_media_picker.dart';
import '../domain/pulse_models.dart';
import 'pulse_text.dart';

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
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _captionController = TextEditingController();
  final FocusNode _textFocus = FocusNode();
  final FocusNode _captionFocus = FocusNode();

  // A Pulse is a camera format first and a writing format second, so the
  // composer opens on the lens: photo mode, with the camera already coming up.
  PulseMediaType _mode = PulseMediaType.photo;
  String _gradientKey = PulseGradient.ember.key;
  String? _mediaPath;
  Duration? _videoDuration;
  double? _videoAspectRatio;
  VideoPlayerController? _videoController;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // After the first frame, so the capture screen is already painted behind
    // the camera and is what the user lands on if they back out of it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _pickPhoto(ImageSource.camera);
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _captionController.dispose();
    _textFocus.dispose();
    _captionFocus.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  PulseGradient get _gradient => PulseGradient.fromKey(_gradientKey);

  bool get _hasMedia => (_mediaPath ?? '').isNotEmpty;

  bool get _canShare {
    if (_busy) return false;
    if (_mode == PulseMediaType.text) {
      return _textController.text.trim().isNotEmpty;
    }
    return _hasMedia;
  }

  void _switchMode(PulseMediaType mode) {
    if (mode == _mode) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _mode = mode;
      // Media belongs to the mode that picked it — a photo must not linger
      // behind the video tab, where Share would upload it as an .mp4.
      _clearMedia();
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
      path = await PulseMediaPicker.pickPhoto(
        context: context,
        source: source,
      );
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
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);

    final draft = PulseDraft(
      type: _mode,
      localFilePath: _mediaPath,
      text: _mode == PulseMediaType.text
          ? _textController.text
          : _captionController.text,
      gradientKey: _gradientKey,
      videoDuration: _videoDuration,
      aspectRatio: _mode == PulseMediaType.video
          ? _videoAspectRatio
          : PulseMediaPicker.aspectRatio,
    );

    try {
      await ref.read(pulseActionsProvider).publish(draft);
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Pulse is live for 24 hours.')),
      );
      context.pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showMessage(error.toString());
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final isTyping = keyboardInset > 0;

    return Scaffold(
      backgroundColor: AppColors.mediaBackdrop,
      // The keyboard overlays the canvas instead of resizing the screen. With
      // resize on, every control has to be re-fitted into the shrinking space
      // and the layout collapses — the canvas is repositioned by hand below.
      resizeToAvoidBottomInset: false,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildCanvas(keyboardInset),
          const _ControlScrim(),
          SafeArea(
            bottom: false,
            child: Align(
              alignment: Alignment.topCenter,
              child: _buildTopBar(isTyping),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            // Controls ride the top of the keyboard rather than hiding behind
            // it, so the palette stays reachable mid-sentence.
            bottom: keyboardInset,
            child: SafeArea(
              top: false,
              bottom: !isTyping,
              child: _buildControls(isTyping),
            ),
          ),
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
    );
  }

  Widget _buildTopBar(bool isTyping) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Row(
        children: [
          IconButton(
            onPressed: () => context.pop(),
            icon: const Icon(Icons.close_rounded),
            color: AppColors.onMedia,
            tooltip: 'Close',
          ),
          const Spacer(),
          if (isTyping)
            TextButton(
              onPressed: () => FocusScope.of(context).unfocus(),
              style: TextButton.styleFrom(foregroundColor: AppColors.onMedia),
              child: const Text(
                'Done',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
            )
          else if (_hasMedia)
            IconButton(
              onPressed: () => setState(_clearMedia),
              icon: const Icon(Icons.refresh_rounded),
              color: AppColors.onMedia,
              tooltip: 'Choose something else',
            ),
        ],
      ),
    );
  }

  Widget _buildCanvas(double keyboardInset) {
    switch (_mode) {
      // Not reachable from here: sharing a post to Pulse starts from the post,
      // not from this composer, and lands on SharePostToPulseScreen. Listed so
      // adding a Pulse kind can't silently fall through this switch.
      case PulseMediaType.post:
        return const SizedBox.shrink();

      case PulseMediaType.text:
        return GestureDetector(
          // The whole canvas is the way in, not just the line of hint text —
          // the field itself is only as tall as what has been typed so far.
          onTap: _textFocus.requestFocus,
          behavior: HitTestBehavior.opaque,
          child: DecoratedBox(
            decoration: BoxDecoration(gradient: _gradient.linear),
            child: SafeArea(
              child: Padding(
                // Centres the message in what is still visible above the
                // keyboard, the way Instagram keeps the caret in view.
                padding: EdgeInsets.only(
                  left: AppSpacing.lg,
                  right: AppSpacing.lg,
                  top: 72,
                  bottom: keyboardInset > 0 ? 72 : 160,
                ),
                child: Center(
                  child: SingleChildScrollView(
                    child: TextField(
                      controller: _textController,
                      focusNode: _textFocus,
                      onChanged: (_) => setState(() {}),
                      // Deliberately not autofocused: the background is picked
                      // before the writing starts, and a keyboard on open would
                      // bury the palette behind it.
                      maxLines: null,
                      maxLength: 280,
                      textAlign: TextAlign.center,
                      textCapitalization: TextCapitalization.sentences,
                      cursorColor: AppColors.onMedia,
                      style: TextStyle(
                        color: AppColors.onMedia,
                        fontSize: pulseTextSize(_textController.text),
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                      ),
                      decoration: barePulseInput(
                        hintText: 'Say something',
                        hintStyle: const TextStyle(
                          color: Color(0x8AFFFFFF),
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

      case PulseMediaType.photo:
        final path = _mediaPath;
        if (path == null) {
          return _CaptureCanvas(
            icon: Icons.photo_camera_rounded,
            title: 'Capture a Pulse',
            subtitle: 'Tap the shutter to shoot.\nIt disappears after 24 hours.',
            captureLabel: 'Take a photo',
            onCamera: () => _pickPhoto(ImageSource.camera),
            onGallery: () => _pickPhoto(ImageSource.gallery),
          );
        }
        return _MediaCanvas(
          child: kIsWeb
              ? Image.network(path, fit: BoxFit.cover)
              : Image.file(File(path), fit: BoxFit.cover),
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
        return _MediaCanvas(
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

  Widget _buildControls(bool isTyping) {
    // Writing a text Pulse clears the deck entirely: the message *is* the
    // canvas, so leaving the palette floating over the keyboard just crowds
    // it. Colour is a decision made before the first tap, and the Done button
    // in the top bar is the way back out to it.
    if (_mode == PulseMediaType.text && isTyping) {
      return const SizedBox.shrink();
    }

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
          if (_mode == PulseMediaType.text)
            _GradientPicker(
              selectedKey: _gradientKey,
              onSelected: (key) => setState(() => _gradientKey = key),
            )
          else if (_hasMedia)
            _CaptionField(
              controller: _captionController,
              focusNode: _captionFocus,
              onChanged: () => setState(() {}),
            ),
          // While the keyboard is up, the mode switch and Share step out of
          // the way — reaching them means finishing the sentence first.
          if (!isTyping) ...[
            const SizedBox(height: AppSpacing.md),
            _ModeSelector(mode: _mode, onSelected: _switchMode),
            // Nothing to share yet on an empty camera screen, and a dead grey
            // button under the shutter is just noise. It arrives with the shot.
            if (_mode == PulseMediaType.text || _hasMedia) ...[
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _canShare ? _share : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.orangeBright,
                    disabledBackgroundColor: const Color(0x66111111),
                    foregroundColor: AppColors.onMedia,
                    disabledForegroundColor: AppColors.onMediaMuted,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: const Icon(Icons.bolt_rounded),
                  label: const Text(
                    'Share Pulse',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ],
        ],
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

/// What sits behind the camera when it opens, and what the user lands on if
/// they back out of it: a shutter, and the gallery as the way round it.
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

/// Caption input for a photo or clip.
///
/// Sits on a translucent pill rather than a form field — it is part of the
/// picture, not part of a settings screen.
class _CaptionField extends StatelessWidget {
  const _CaptionField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: const Color(0x99000000),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.text_fields_rounded,
              color: Color(0xCCFFFFFF), size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              onChanged: (_) => onChanged(),
              maxLength: 140,
              textCapitalization: TextCapitalization.sentences,
              cursorColor: AppColors.onMedia,
              style: const TextStyle(
                color: AppColors.onMedia,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              decoration: barePulseInput(
                hintText: 'Add a caption',
                hintStyle: const TextStyle(
                  color: Color(0x8AFFFFFF),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GradientPicker extends StatelessWidget {
  const _GradientPicker({required this.selectedKey, required this.onSelected});

  final String selectedKey;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: PulseGradient.all.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, index) {
          final gradient = PulseGradient.all[index];
          final selected = gradient.key == selectedKey;
          return GestureDetector(
            onTap: () => onSelected(gradient.key),
            child: Container(
              width: 36,
              height: 36,
              margin: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: gradient.linear,
                border: Border.all(
                  color: selected ? AppColors.onMedia : const Color(0x66FFFFFF),
                  width: selected ? 3 : 1,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ModeSelector extends StatelessWidget {
  const _ModeSelector({required this.mode, required this.onSelected});

  final PulseMediaType mode;
  final ValueChanged<PulseMediaType> onSelected;

  // Photo leads: it is where the composer opens, and the selected tab reads
  // wrong sitting in the middle of the row on arrival.
  static const _labels = {
    PulseMediaType.photo: 'Photo',
    PulseMediaType.video: 'Video',
    PulseMediaType.text: 'Text',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0x99000000),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x33FFFFFF)),
      ),
      child: Row(
        children: [
          for (final entry in _labels.entries)
            Expanded(
              child: GestureDetector(
                onTap: () => onSelected(entry.key),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: entry.key == mode
                        ? AppColors.orangeBright
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    entry.value,
                    style: TextStyle(
                      color: entry.key == mode
                          ? AppColors.onMedia
                          : const Color(0xCCFFFFFF),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
