import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/quick_toast.dart';
import '../application/pulse_providers.dart';
import '../domain/pulse_models.dart';
import '../domain/pulse_text_style.dart';
import 'pulse_share_controls.dart';
import 'pulse_text_tool.dart';

/// The shared canvas behind every "add this to your Pulse" screen.
///
/// Sharing a post and sharing a track are the same screen with a different
/// thing mounted on it: a card on a gradient you pick, words you may or may
/// not write over it with the same text tool the composer has, and one
/// button. Only [canvas] and [buildDraft] differ, so they are the only two
/// things a caller supplies.
///
/// Nothing here uploads. Both kinds publish from a snapshot written onto the
/// Pulse document, which is what lets a single write finish the job.
class PulseShareScaffold extends ConsumerStatefulWidget {
  const PulseShareScaffold({
    required this.canvas,
    required this.buildDraft,
    this.beforeShare,
    this.captionHint = 'Say something about this',
    this.canvasFillsFrame = false,
    this.showGradientPicker = true,
    super.key,
  });

  /// What sits in the middle of the frame — or, with [canvasFillsFrame], what
  /// *is* the frame.
  ///
  /// Built from the gradient currently picked, so a canvas that paints its own
  /// background stays in step with the palette below it.
  final Widget Function(PulseGradient gradient) canvas;

  /// Whether [canvas] paints its own background edge to edge.
  ///
  /// A shared post is a card centred on a gradient. A shared track is the
  /// album art itself, filling the screen, and centring that inside padding
  /// would frame the frame.
  final bool canvasFillsFrame;

  /// Whether the gradient palette is offered.
  ///
  /// Off for a canvas that covers the gradient completely: a colour nobody
  /// will ever see is a control that does nothing.
  final bool showGradientPicker;

  /// The draft to publish, given whatever the user wrote and picked.
  ///
  /// [text] is empty and [textStyle] the defaults when nothing was written;
  /// otherwise the style says how and where the words sit on the frame.
  final PulseDraft Function(
    String text,
    PulseTextStyle textStyle,
    String gradientKey,
  ) buildDraft;

  /// Awaited, under the busy state, before [buildDraft] is read.
  ///
  /// For anything the screen is still fetching that belongs on the Pulse —
  /// a cover that is being looked up, say. A Pulse is a snapshot: whatever
  /// has not landed by the time the draft is built is missing for 24 hours,
  /// and a Share pressed a beat after arriving must not lose it. Errors are
  /// the caller's to swallow; a hook that throws fails the share.
  final Future<void> Function()? beforeShare;

  /// What the empty text tool says.
  final String captionHint;

  @override
  ConsumerState<PulseShareScaffold> createState() => _PulseShareScaffoldState();
}

class _PulseShareScaffoldState extends ConsumerState<PulseShareScaffold> {
  /// The words over the canvas, and how they are drawn — the same tool, the
  /// same state, as the composer keeps for a text card.
  final TextEditingController _textController = TextEditingController();
  PulseTextStyle _textStyle = PulseTextStyle.defaults;
  bool _editingText = false;

  String _gradientKey = PulseGradient.ember.key;
  bool _busy = false;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  PulseGradient get _gradient => PulseGradient.fromKey(_gradientKey);

  bool get _hasText => _textController.text.trim().isNotEmpty;

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

  /// Steps the mount on to the next backdrop, wrapping round at the end —
  /// the composer's one-tap wheel, not a palette.
  void _cycleGradient() {
    const all = PulseGradient.all;
    final index = all.indexWhere((gradient) => gradient.key == _gradientKey);
    setState(() => _gradientKey = all[(index + 1) % all.length].key);
  }

  Future<void> _share() async {
    if (_busy || _editingText) return;
    FocusScope.of(context).unfocus();
    // Read off the root overlay before anything awaits: this route pops on
    // success, and a message anchored to its Scaffold would go with it.
    final overlay = Overlay.of(context, rootOverlay: true);
    setState(() => _busy = true);

    try {
      await widget.beforeShare?.call();
      if (!mounted) return;
      await ref.read(pulseActionsProvider).publish(
            widget.buildDraft(
              _hasText ? _textController.text : '',
              _textStyle,
              _gradientKey,
            ),
          );
      if (!mounted) return;
      showQuickToastOn(
        overlay,
        'Pulse is live for 24 hours',
        icon: Icons.bolt_rounded,
        tone: ToastTone.success,
      );
      context.pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      debugPrint('Publishing a Pulse failed: $error');
      showQuickToastOn(
        overlay,
        "Couldn't share that. Try again.",
        icon: Icons.error_outline_rounded,
        tone: ToastTone.danger,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    return PopScope(
      // Back while the text tool is open closes the tool, not the screen.
      canPop: !_editingText,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closeTextTool();
      },
      child: Scaffold(
        backgroundColor: AppColors.mediaBackdrop,
        // Same rule as the Pulse composer: the keyboard overlays the canvas
        // rather than resizing it; the text tool lifts itself above it.
        resizeToAvoidBottomInset: false,
        body: Stack(
          fit: StackFit.expand,
          children: [
            _withText(_buildCanvas()),
            // The text tool brings its own chrome and takes the whole screen
            // while it is open, exactly as it does in the composer.
            if (_editingText)
              PulseTextEditor(
                controller: _textController,
                style: _textStyle,
                onStyleChanged: (style) => setState(() => _textStyle = style),
                onDone: _closeTextTool,
                keyboardInset: keyboardInset,
                hintText: widget.captionHint,
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

  /// The words, set down where their style says, over the canvas. Nothing
  /// while the text tool is open — it is showing them itself.
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
    final canvas = widget.canvas(_gradient);
    if (widget.canvasFillsFrame) return canvas;

    return DecoratedBox(
      decoration: BoxDecoration(gradient: _gradient.linear),
      child: SafeArea(
        child: Padding(
          // Clears the top bar and the Share pill, so the card centres in the
          // space that is actually free rather than under the chrome.
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            64,
            AppSpacing.lg,
            120,
          ),
          child: Center(
            child: SingleChildScrollView(child: canvas),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
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
          // The composer's rail: text first, then the backdrop wheel for a
          // canvas that still shows its gradient.
          Column(
            children: [
              PulseTextToolButton(onTap: _openTextTool),
              if (widget.showGradientPicker)
                PulseBackgroundButton(onTap: _cycleGradient),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.md,
      ),
      // Centred, not stretched: it is a pill over the canvas, as in the
      // composer, not a footer across it.
      child: Center(child: PulseShareButton(onPressed: _busy ? null : _share)),
    );
  }
}
