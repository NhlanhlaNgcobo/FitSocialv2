import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_palette.dart';
import '../../app/theme/app_spacing.dart';
import 'avatar.dart';
import 'glass_well.dart';

/// The row a comment is typed in: the writer's avatar, the glass pill, and
/// the send disc.
///
/// The look only. Two composers share it — the post one, which threads
/// replies and bumps feed counters, and the Pulse one, which does neither —
/// and the box has to be the same box on both, so the material lives here and
/// the writes stay with their callers.
///
/// ## Why the pill is a [GlassWell] and not a bare field in glass
///
/// The theme draws every field as an [OutlineInputBorder] at
/// [AppRadius.field], orange when focused. `border: InputBorder.none` on the
/// field does not switch that off: `enabledBorder` and `focusedBorder` resolve
/// from the theme on their own, so a focused comment box went on drawing an
/// 18px orange outline inside a 24px pill and the clip sliced it into orange
/// fringes along the edges. The well overrides every border slot from closer
/// in than the theme, which is the only place that override sticks.
///
/// ## What lights up, and when
///
/// The pill takes a brand rim and a faint glow while it has focus; the disc
/// takes the brand fill and the nav's glow only once there is something to
/// send. Before that it is a quiet grey coin — a lit orange button beside an
/// empty box is asking to be tapped for nothing.
class CommentWell extends StatefulWidget {
  const CommentWell({
    required this.controller,
    required this.focusNode,
    required this.onSubmit,
    required this.isSending,
    required this.hintText,
    this.avatarInitials = '',
    this.avatarUrl,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode focusNode;

  /// Asked to send. Only fired while the box has text and nothing is in
  /// flight; the caller trims and validates its own copy regardless.
  final VoidCallback onSubmit;

  /// Holds the disc lit and swaps the arrow for a spinner.
  final bool isSending;

  final String hintText;

  /// The writer, so the box reads as *theirs*. Empty initials and no URL fall
  /// back to the neutral glyph, the same as everywhere else an avatar stands.
  final String avatarInitials;
  final String? avatarUrl;

  /// One notch under the card radius: a pill this height at 24 reads as a
  /// capsule with no straight edge left, and the text sits oddly in it.
  static const double _radius = 22;
  static const double _avatarSize = 32;
  static const double _discSize = 40;

  static const Duration _fade = Duration(milliseconds: 200);

  @override
  State<CommentWell> createState() => _CommentWellState();
}

class _CommentWellState extends State<CommentWell> {
  bool _focused = false;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _focused = widget.focusNode.hasFocus;
    _hasText = widget.controller.text.trim().isNotEmpty;
    widget.focusNode.addListener(_focusChanged);
    widget.controller.addListener(_textChanged);
  }

  @override
  void didUpdateWidget(CommentWell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_focusChanged);
      widget.focusNode.addListener(_focusChanged);
      _focused = widget.focusNode.hasFocus;
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_textChanged);
      widget.controller.addListener(_textChanged);
      _hasText = widget.controller.text.trim().isNotEmpty;
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_focusChanged);
    widget.controller.removeListener(_textChanged);
    super.dispose();
  }

  void _focusChanged() {
    final focused = widget.focusNode.hasFocus;
    if (focused != _focused) setState(() => _focused = focused);
  }

  /// Rebuilds only when the answer changes — every keystroke would otherwise
  /// repaint the disc and the glow for nothing.
  void _textChanged() {
    final hasText = widget.controller.text.trim().isNotEmpty;
    if (hasText != _hasText) setState(() => _hasText = hasText);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final canSend = _hasText && !widget.isSending;

    return Row(
      // Pinned to the bottom edge, so the avatar and the disc hold their place
      // beside the first line while the box grows upward for a longer comment.
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Padding(
          // Lines the disc's centre up with the pill's single-line centre.
          padding: const EdgeInsets.only(
            bottom: (_pillMinHeight - CommentWell._avatarSize) / 2,
          ),
          child: Avatar(
            initials: widget.avatarInitials,
            imageUrl: widget.avatarUrl,
            size: CommentWell._avatarSize,
          ),
        ),
        const SizedBox(width: AppSpacing.sm + 2),
        Expanded(child: _pill(palette)),
        const SizedBox(width: AppSpacing.sm),
        Padding(
          padding: const EdgeInsets.only(
            bottom: (_pillMinHeight - CommentWell._discSize) / 2,
          ),
          child: _SendDisc(
            lit: _hasText || widget.isSending,
            sending: widget.isSending,
            onTap: canSend ? widget.onSubmit : null,
          ),
        ),
      ],
    );
  }

  /// One line of 15px text plus the field's vertical padding and the well's
  /// hairline — what the pill measures with nothing typed yet.
  static const double _pillMinHeight = 44;

  Widget _pill(AppPalette palette) {
    final brand = palette.brand;
    final shape = BorderRadius.circular(CommentWell._radius);

    return AnimatedContainer(
      duration: CommentWell._fade,
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        borderRadius: shape,
        // A glow rather than a thicker ring: the well's hairline already turns
        // brand on focus, and a 2px ring on a pane of glass reads as a sticker.
        boxShadow: [
          BoxShadow(
            color: brand.withValues(alpha: _focused ? 0.18 : 0),
            blurRadius: 18,
            spreadRadius: -2,
          ),
        ],
      ),
      child: GlassWell(
        radius: CommentWell._radius,
        borderColor: _focused ? brand.withValues(alpha: 0.55) : null,
        child: TextField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          style: TextStyle(
            color: palette.text,
            fontSize: 15,
            height: 1.35,
          ),
          cursorColor: brand,
          decoration: InputDecoration(
            hintText: widget.hintText,
            hintStyle: TextStyle(color: palette.muted, fontSize: 15),
            isDense: true,
            // The well owns the surface; this only has to say where the text
            // sits. Set on the decoration rather than the theme so it beats
            // the well's own, which is sized for a taller form field.
            contentPadding: const EdgeInsets.fromLTRB(16, 11, 14, 11),
          ),
          maxLines: 4,
          minLines: 1,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.send,
          onSubmitted: (_) {
            if (_hasText && !widget.isSending) widget.onSubmit();
          },
        ),
      ),
    );
  }
}

/// The send button: a grey coin until there is something to send, then the
/// brand disc the nav's Create button is cut from, glow included.
class _SendDisc extends StatelessWidget {
  const _SendDisc({
    required this.lit,
    required this.sending,
    required this.onTap,
  });

  final bool lit;
  final bool sending;

  /// Null while there is nothing to send; the disc still paints, it just
  /// doesn't answer.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final brand = palette.brand;

    return Semantics(
      button: true,
      enabled: onTap != null,
      label: 'Post comment',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.lightImpact();
                onTap!();
              },
        child: AnimatedContainer(
          duration: CommentWell._fade,
          curve: Curves.easeOutCubic,
          width: CommentWell._discSize,
          height: CommentWell._discSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            // The same lit corner as the nav disc, so the two orange buttons
            // on screen at once are visibly one material.
            gradient: lit
                ? LinearGradient(
                    colors: [
                      Color.lerp(brand, const Color(0xFFFFFFFF), 0.32)!,
                      brand,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: lit ? null : palette.surfaceHigh,
            border: lit ? null : Border.all(color: palette.stroke),
            boxShadow: [
              BoxShadow(
                color: brand.withValues(alpha: lit ? 0.45 : 0),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: sending
              ? const Padding(
                  padding: EdgeInsets.all(11),
                  child: CircularProgressIndicator(
                    color: AppColors.onBrand,
                    strokeWidth: 2,
                  ),
                )
              : AnimatedScale(
                  scale: lit ? 1 : 0.85,
                  duration: CommentWell._fade,
                  curve: Curves.easeOutBack,
                  child: Icon(
                    Icons.arrow_upward_rounded,
                    // The constant, not `palette.text`: on the light theme
                    // that is near-black, and a black arrow on orange is
                    // the one thing this disc must never be.
                    color: lit ? AppColors.onBrand : palette.muted,
                    size: 21,
                  ),
                ),
        ),
      ),
    );
  }
}
