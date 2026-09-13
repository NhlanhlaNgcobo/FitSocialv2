import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../domain/pulse_text_style.dart';
import 'pulse_text.dart';

/// Writing on a Pulse, the way a story composer does it.
///
/// Two states, and this file holds both. While editing, [PulseTextEditor]
/// takes the screen: the words sit in the middle over a dimmed canvas with
/// the keyboard up, the faces run along the top, the colours along the bottom,
/// and a slider on the left sets the size. Once done, [PulseTextSticker] is
/// the same words set down on the canvas, where a finger can drag, pinch and
/// turn them, and a tap opens the editor again.
///
/// Neither owns the text or its style. The composer does, because the same
/// values go on to the rasteriser and the draft.
class PulseTextEditor extends StatefulWidget {
  const PulseTextEditor({
    required this.controller,
    required this.style,
    required this.onStyleChanged,
    required this.onDone,
    required this.keyboardInset,
    this.hintText = 'Say something',
    super.key,
  });

  final TextEditingController controller;
  final PulseTextStyle style;
  final ValueChanged<PulseTextStyle> onStyleChanged;
  final VoidCallback onDone;

  /// How much of the bottom of the screen the keyboard is covering. The
  /// composer does not resize for the keyboard, so this is how the controls
  /// know to stay above it.
  final double keyboardInset;

  final String hintText;

  /// The longest message a Pulse carries.
  static const int maxLength = 280;

  @override
  State<PulseTextEditor> createState() => _PulseTextEditorState();
}

class _PulseTextEditorState extends State<PulseTextEditor> {
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // Opening the editor is the whole of asking to type — the keyboard comes
    // up with it. Requested after the first frame so the field exists to take
    // focus.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _update(PulseTextStyle Function(PulseTextStyle) change) {
    widget.onStyleChanged(change(widget.style));
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    // Live: the words re-flow into each face and colour as they are picked,
    // and the size steps down as the message runs long, exactly as the
    // finished card will.
    final text = widget.controller.text;
    final resolved = style.resolve(pulseTextSize(text));
    final fontSize = resolved.fontSize!;
    final plate = style.plate;
    final platePadding =
        plate == null ? EdgeInsets.zero : pulsePlatePadding(fontSize);

    // The field is made exactly as wide as its longest line, so a plate hugs
    // the words rather than spanning the screen — see pulseTextContentWidth.
    // Plus a quarter of an em: the editable keeps a caret's margin back from
    // its edge and rounds what is left, so a field cut to the exact width
    // wraps its own widest line. A quarter em covers that and is still too
    // narrow for a space and one more letter, so nothing new fits on a line.
    final maxWidth = pulseTextMaxWidth(MediaQuery.sizeOf(context).width);
    final fieldWidth = pulseTextContentWidth(
          text: text.isEmpty ? widget.hintText : text,
          style: resolved,
          textAlign: style.alignment.textAlign,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxWidth: maxWidth - platePadding.horizontal,
        ) +
        fontSize * 0.25;

    Widget field = TextField(
      controller: widget.controller,
      focusNode: _focus,
      onChanged: (_) => setState(() {}),
      maxLines: null,
      maxLength: PulseTextEditor.maxLength,
      textAlign: style.alignment.textAlign,
      textCapitalization: TextCapitalization.sentences,
      cursorColor: style.foreground,
      style: resolved,
      decoration: barePulseInput(
        hintText: widget.hintText,
        hintStyle: resolved.copyWith(
          color: style.foreground.withValues(alpha: 0.5),
          shadows: const [],
        ),
      ),
    );

    // Always the same wrappers, plate or no plate. Adding a DecoratedBox only
    // when there is one changes the shape of the tree around the field, which
    // recreates the editable inside it — and that drops the keyboard mid-
    // sentence every time the plate button is pressed. A transparent plate
    // costs nothing and keeps the field where it was.
    field = DecoratedBox(
      decoration: BoxDecoration(
        color: plate ?? const Color(0x00000000),
        borderRadius: BorderRadius.circular(pulsePlateRadius(fontSize)),
      ),
      child: Padding(
        padding: platePadding,
        child: SizedBox(width: fieldWidth, child: field),
      ),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        // The canvas steps back while the words are being written, so the
        // type is read against something calm rather than the photo it will
        // eventually sit on.
        GestureDetector(
          onTap: widget.onDone,
          behavior: HitTestBehavior.opaque,
          child: const ColoredBox(color: Color(0x73000000)),
        ),
        Column(
          children: [
            SafeArea(
              bottom: false,
              child: _EditorTopBar(
                style: style,
                onAlignment: () =>
                    _update((s) => s.copyWith(alignment: s.alignment.next)),
                onBackdrop: () =>
                    _update((s) => s.copyWith(backdrop: s.backdrop.next)),
                onDone: widget.onDone,
              ),
            ),
            Expanded(
              // The slider floats over the left edge rather than taking a
              // column of its own: the words get the same width here as the
              // sticker gets on the canvas, so they wrap the same way in both
              // and Done never re-flows them.
              child: Stack(
                children: [
                  Center(
                    child: SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: maxWidth),
                        child: field,
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _SizeSlider(
                      value: style.scale,
                      onChanged: (scale) =>
                          _update((s) => s.copyWith(scale: scale)),
                    ),
                  ),
                ],
              ),
            ),
            _FontRow(
              selected: style.font,
              onSelected: (font) => _update((s) => s.copyWith(font: font)),
            ),
            const SizedBox(height: AppSpacing.sm),
            _ColorRow(
              selected: style.color,
              onSelected: (color) => _update((s) => s.copyWith(color: color)),
            ),
            SizedBox(
              height: widget.keyboardInset > 0
                  ? widget.keyboardInset + AppSpacing.sm
                  : MediaQuery.paddingOf(context).bottom + AppSpacing.md,
            ),
          ],
        ),
      ],
    );
  }
}

/// Alignment and plate on the left, Done on the right.
class _EditorTopBar extends StatelessWidget {
  const _EditorTopBar({
    required this.style,
    required this.onAlignment,
    required this.onBackdrop,
    required this.onDone,
  });

  final PulseTextStyle style;
  final VoidCallback onAlignment;
  final VoidCallback onBackdrop;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Row(
        children: [
          _ToolButton(
            label: 'Align',
            onTap: onAlignment,
            child: Icon(style.alignment.icon, color: AppColors.onMedia),
          ),
          _BackdropToggle(backdrop: style.backdrop, onTap: onBackdrop),
          const Spacer(),
          _ToolButton(
            label: 'Done',
            onTap: onDone,
            child: const Text(
              'Done',
              style: TextStyle(
                color: AppColors.onMedia,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Instagram's "A" button: the letter drawn the way the plate setting will
/// draw the text, so the button shows what the next tap does.
class _BackdropToggle extends StatelessWidget {
  const _BackdropToggle({required this.backdrop, required this.onTap});

  final PulseTextBackdrop backdrop;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color fill;
    final Color letter;
    switch (backdrop) {
      case PulseTextBackdrop.none:
        fill = const Color(0x00000000);
        letter = AppColors.onMedia;
      case PulseTextBackdrop.solid:
        fill = AppColors.onMedia;
        letter = PulseTextColors.black;
      case PulseTextBackdrop.translucent:
        fill = const Color(0x66FFFFFF);
        letter = AppColors.onMedia;
    }
    return _ToolButton(
      label: 'Text background',
      onTap: onTap,
      child: Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: AppColors.onMedia, width: 1.6),
        ),
        child: Text(
          'A',
          style: TextStyle(
            color: letter,
            fontSize: 15,
            fontWeight: FontWeight.w800,
            height: 1,
          ),
        ),
      ),
    );
  }
}

/// A control in the editor's top bar.
///
/// Not a Material button on purpose: those take focus when pressed, and focus
/// leaving the field drops the keyboard — so every tap on Align or the plate
/// would end the sentence being typed. This is a tap target and nothing else;
/// the field keeps the keyboard throughout.
class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.label,
    required this.onTap,
    required this.child,
  });

  final String label;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            alignment: Alignment.center,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// The size control down the left edge, as a story composer has it.
class _SizeSlider extends StatelessWidget {
  const _SizeSlider({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      child: Center(
        child: SizedBox(
          height: 220,
          child: RotatedBox(
            quarterTurns: -1,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                activeTrackColor: AppColors.onMedia,
                inactiveTrackColor: const Color(0x66FFFFFF),
                thumbColor: AppColors.onMedia,
                overlayColor: const Color(0x33FFFFFF),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
              ),
              child: Slider(
                value: value.clamp(
                  PulseTextStyle.minScale,
                  PulseTextStyle.maxScale,
                ),
                min: PulseTextStyle.minScale,
                max: PulseTextStyle.maxScale,
                onChanged: onChanged,
                semanticFormatterCallback: (v) =>
                    'Text size ${v.toStringAsFixed(1)}',
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The faces, each chip set in the face it names.
class _FontRow extends StatelessWidget {
  const _FontRow({required this.selected, required this.onSelected});

  final PulseFont selected;
  final ValueChanged<PulseFont> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        itemCount: PulseFont.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, index) {
          final font = PulseFont.values[index];
          final isSelected = font == selected;
          return Semantics(
            button: true,
            selected: isSelected,
            label: font.label,
            child: GestureDetector(
              onTap: () => onSelected(font),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color:
                      isSelected ? AppColors.onMedia : const Color(0x33000000),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected
                        ? AppColors.onMedia
                        : const Color(0x66FFFFFF),
                  ),
                ),
                child: Text(
                  font.label,
                  style: font.baseStyle.copyWith(
                    color:
                        isSelected ? PulseTextColors.black : AppColors.onMedia,
                    fontSize: 14 * font.sizeFactor,
                    height: 1,
                    letterSpacing: 0,
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

/// The swatches under the words. The chosen one wears a ring with a gap
/// inside it — the same treatment the gradient picker gives its swatches.
class _ColorRow extends StatelessWidget {
  const _ColorRow({required this.selected, required this.onSelected});

  final Color selected;
  final ValueChanged<Color> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        itemCount: PulseTextColors.all.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final color = PulseTextColors.all[index];
          final isSelected = color == selected;
          return Semantics(
            button: true,
            selected: isSelected,
            label: 'Text colour',
            child: GestureDetector(
              onTap: () => onSelected(color),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                width: 32,
                height: 32,
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: EdgeInsets.all(isSelected ? 3 : 0),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected
                        ? AppColors.onMedia
                        : const Color(0x00FFFFFF),
                    width: 2,
                  ),
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                    border: Border.all(color: const Color(0x8AFFFFFF)),
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

/// The written words, set down on the canvas.
///
/// Press and hold to pick up and move, or just drag; pinch to size, twist to
/// turn, tap to edit. The gesture is taken on the block itself rather than the
/// whole canvas, so on a photo the picture under it still pinches on its own.
class PulseTextSticker extends StatefulWidget {
  const PulseTextSticker({
    required this.text,
    required this.style,
    required this.onStyleChanged,
    required this.onTap,
    super.key,
  });

  final String text;
  final PulseTextStyle style;
  final ValueChanged<PulseTextStyle> onStyleChanged;
  final VoidCallback onTap;

  /// How close to an edge the centre of the text may be dragged. Enough that
  /// a block can hang off the side, not so much that it can be lost.
  static const double edge = 0.06;

  @override
  State<PulseTextSticker> createState() => _PulseTextStickerState();
}

class _PulseTextStickerState extends State<PulseTextSticker> {
  // Scale and rotation are reported relative to the start of the gesture, so
  // they are applied to what the style was when it began. Movement is taken
  // from the focal point in *global* space, step by step: the block is the
  // thing moving under the fingers, so anything measured in its own
  // coordinates — `focalPointDelta` included — shrinks by however far it
  // just moved, and the drag falls behind the finger.
  double _startScale = 1;
  double _startRotation = 0;
  Offset _lastFocal = Offset.zero;

  /// The style as this gesture has left it so far.
  ///
  /// Built on from update to update rather than from `widget.style`: pointer
  /// events arrive several times per frame, and the widget is only rebuilt
  /// once a frame, so reading the widget's copy each time would apply only
  /// the last delta of every frame and lose the rest — the block would trail
  /// the finger at a fraction of its speed.
  PulseTextStyle _live = PulseTextStyle.defaults;

  void _onStart(ScaleStartDetails details) {
    _live = widget.style;
    _startScale = _live.scale;
    _startRotation = _live.rotation;
    _lastFocal = details.focalPoint;
  }

  void _onUpdate(ScaleUpdateDetails details, Size frame) {
    _moveTo(details.focalPoint, frame);
    _live = _live.copyWith(
      scale: (_startScale * details.scale).clamp(
        PulseTextStyle.minScale,
        PulseTextStyle.maxScale,
      ),
      rotation: _startRotation + details.rotation,
    );
    widget.onStyleChanged(_live);
  }

  /// Press and hold picks the block up — a tick under the finger says so —
  /// and from there it goes wherever the finger goes.
  void _onHold(LongPressStartDetails details) {
    HapticFeedback.mediumImpact();
    _live = widget.style;
    _lastFocal = details.globalPosition;
  }

  void _onHoldMove(LongPressMoveUpdateDetails details, Size frame) {
    _moveTo(details.globalPosition, frame);
    widget.onStyleChanged(_live);
  }

  /// Carries the block along with a finger now at [focal], in global space.
  void _moveTo(Offset focal, Size frame) {
    const edge = PulseTextSticker.edge;
    final moved = focal - _lastFocal;
    _lastFocal = focal;
    _live = _live.copyWith(
      x: (_live.x + moved.dx / frame.width).clamp(edge, 1 - edge),
      y: (_live.y + moved.dy / frame.height).clamp(edge, 1 - edge),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PulseTextLayer(
      text: widget.text,
      style: widget.style,
      child: (block, frame) => GestureDetector(
        onTap: widget.onTap,
        onLongPressStart: _onHold,
        onLongPressMoveUpdate: (details) => _onHoldMove(details, frame),
        onScaleStart: _onStart,
        onScaleUpdate: (details) => _onUpdate(details, frame),
        // Opaque, so a drag that starts on the plate's padding or between two
        // letters still takes hold of the block.
        behavior: HitTestBehavior.opaque,
        child: block,
      ),
    );
  }
}
