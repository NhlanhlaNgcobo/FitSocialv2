import 'dart:io';

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
  // composer opens on photo mode — but on the capture screen, with the shutter
  // waiting, not in the camera itself. Throwing the OS camera up on arrival
  // takes the screen over before anyone has said they want a photo, and
  // dismissing it reads as leaving the composer rather than landing in it.
  PulseMediaType _mode = PulseMediaType.photo;
  String _gradientKey = PulseGradient.ember.key;
  String? _mediaPath;
  Duration? _videoDuration;
  double? _videoAspectRatio;
  VideoPlayerController? _videoController;
  bool _busy = false;

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
      // Neither is reachable from here: sharing a post starts from the post
      // and sharing a track starts from the player, and both land on their own
      // screen. Listed so adding a Pulse kind can't silently fall through this
      // switch.
      case PulseMediaType.post:
      case PulseMediaType.music:
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
                  // Clears the whole control stack — palette, Share, mode
                  // switch — so the last line typed is never behind a button.
                  bottom: keyboardInset > 0 ? 72 : 184,
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
            subtitle:
                'Tap the shutter to shoot.\nIt disappears after 24 hours.',
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
            // Share sits with the writing it belongs to, and the mode switch
            // holds the bottom edge where a tab bar belongs: the kind of Pulse
            // is picked once on the way in, but Share is read on the way out.
            //
            // Nothing to share yet on an empty camera screen, and a dead grey
            // button under the shutter is just noise. It arrives with the shot.
            if (_mode == PulseMediaType.text || _hasMedia) ...[
              const SizedBox(height: AppSpacing.md),
              _ShareButton(onPressed: _canShare ? _share : null),
            ],
            const SizedBox(height: AppSpacing.md),
            _ModeSelector(mode: _mode, onSelected: _switchMode),
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

/// The backdrop a written Pulse gets set on.
///
/// The chosen swatch wears a ring with a gap inside it rather than a thicker
/// border — a heavier edge on a small circle eats the colour it is meant to be
/// showing off.
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
            child: Semantics(
              button: true,
              selected: selected,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                width: 40,
                height: 40,
                margin: const EdgeInsets.symmetric(vertical: 2),
                padding: EdgeInsets.all(selected ? 3 : 0),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color:
                        selected ? AppColors.onMedia : const Color(0x00FFFFFF),
                    width: 2,
                  ),
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: gradient.linear,
                    border: Border.all(
                      color: const Color(0x59FFFFFF),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The one thing this screen exists to do.
///
/// Lit orange with a glow under it while it is live, and smoked glass while
/// there is nothing to send — the difference has to be readable at a glance
/// over any photo, which a greyed-out fill alone is not.
class _ShareButton extends StatefulWidget {
  const _ShareButton({required this.onPressed});

  /// Null while the Pulse is not ready to go out.
  final VoidCallback? onPressed;

  @override
  State<_ShareButton> createState() => _ShareButtonState();
}

class _ShareButtonState extends State<_ShareButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final foreground = enabled ? AppColors.onMedia : AppColors.onMediaMuted;

    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Share Pulse',
      child: GestureDetector(
        onTap: widget.onPressed,
        onTapDown: enabled ? (_) => _setPressed(true) : null,
        onTapCancel: () => _setPressed(false),
        onTapUp: (_) => _setPressed(false),
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            height: 54,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: enabled
                  ? const LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [AppColors.orangeBright, AppColors.orange],
                    )
                  : null,
              color: enabled ? null : const Color(0x8A000000),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color:
                    enabled ? const Color(0x3DFFFFFF) : const Color(0x1FFFFFFF),
              ),
              boxShadow: enabled
                  ? [
                      // Cast in the deep orange rather than the lit one, and
                      // kept tight. A wide halo in the bright tone reads as a
                      // second light source over a coloured canvas and washes
                      // the bottom of the screen out; this just lifts the
                      // button off whatever is behind it.
                      BoxShadow(
                        color: AppColors.orange.withValues(alpha: 0.28),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.bolt_rounded, size: 20, color: foreground),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'Share Pulse',
                  style: TextStyle(
                    color: foreground,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
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

  @override
  Widget build(BuildContext context) {
    final selectedIndex = _options.indexWhere((option) => option.$1 == mode);

    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: const Color(0x99000000),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x2EFFFFFF)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tabWidth = constraints.maxWidth / _options.length;
          return SizedBox(
            height: 44,
            child: Stack(
              children: [
                // One pill that slides between the tabs rather than three that
                // blink on and off: the travel is what says these are three
                // positions of one control, not three separate buttons.
                AnimatedPositioned(
                  duration: _duration,
                  curve: Curves.easeOutCubic,
                  left: tabWidth * selectedIndex,
                  width: tabWidth,
                  top: 0,
                  bottom: 0,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      // Flat deep orange, no lit gradient and no coloured
                      // glow. This pill sits directly under the Share button:
                      // two lit orange slabs stacked over a coloured canvas
                      // read as one bright blob, and the place switch ends up
                      // shouting as loudly as the thing it is switching to.
                      // Deep and unlit, it stays legible and lets Share lead.
                      color: AppColors.orange,
                      borderRadius: BorderRadius.all(Radius.circular(14)),
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x45000000),
                          blurRadius: 10,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                  ),
                ),
                // Expanded, and stretched across the cross axis, so each tab's
                // tap target is the whole height of the bar. Left to size
                // itself, the row collapses to the height of the label inside
                // it and everything below the text stops responding.
                SizedBox.expand(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (type, icon, label) in _options)
                        Expanded(
                          child: _ModeTab(
                            icon: icon,
                            label: label,
                            selected: type == mode,
                            onTap: () => onSelected(type),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
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
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        // Icon and label brighten on the same curve the pill travels on, so
        // the label is lit by the time the pill arrives under it.
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: selected ? 1 : 0),
          duration: _ModeSelector._duration,
          curve: Curves.easeOutCubic,
          builder: (context, t, _) {
            final color = Color.lerp(
              const Color(0xB3FFFFFF),
              AppColors.onMedia,
              t,
            )!;
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 17, color: color),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 13.5,
                    fontWeight:
                        FontWeight.lerp(FontWeight.w600, FontWeight.w800, t),
                    letterSpacing: 0.1,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
