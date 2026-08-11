import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_colors.dart';
import '../reactions/fit_reaction.dart';

/// Wraps any widget in the reaction gesture, and opens the tray above it.
///
/// This is Facebook's interaction, not a menu:
///   * a tap gives [FitReaction.defaultReaction], because that is what people
///     mean nine times out of ten and making them choose would slow it down;
///   * a tap while already holding a reaction takes it back;
///   * a press-and-hold opens the tray of seven reactions, and the *same*
///     gesture continues — slide along the row to aim, lift to pick. Never two
///     gestures, which is what makes the whole thing take under a second.
///
/// Lifting away from the row picks nothing, so opening the tray by accident
/// costs a release and no reaction.
///
/// Separate from what it wraps because the two places this is used look
/// nothing alike: a Pulse wants a labelled pill over its photo, a post wants
/// an icon and a count in a row of them. The gesture, the tray, its geometry
/// and its arithmetic are the same in both, and only exist once.
class ReactionTrigger extends StatefulWidget {
  const ReactionTrigger({
    required this.selected,
    required this.onChanged,
    required this.child,
    this.onTrayVisibilityChanged,
    super.key,
  });

  /// The reaction this viewer is currently holding, null when they have none.
  final FitReaction? selected;

  /// Fires with the newly chosen reaction, or null when the reaction is taken
  /// back. Never fires with the reaction already held.
  final ValueChanged<FitReaction?> onChanged;

  /// What the gesture sits on, and what the tray springs from.
  final Widget child;

  /// Raised while the tray is open, so the host can hold playback: a Pulse
  /// that advances out from under the tray takes the reaction with it.
  final ValueChanged<bool>? onTrayVisibilityChanged;

  @override
  State<ReactionTrigger> createState() => _ReactionTriggerState();
}

class _ReactionTriggerState extends State<ReactionTrigger>
    with SingleTickerProviderStateMixin {
  /// Widest a single reaction's slot gets. Below this the row is squeezed to fit
  /// rather than overflowing — seven reactions have to land on a narrow phone.
  static const double _maxItemExtent = 46;
  static const double _trayPadding = 8;

  /// Gap between the tray and the button it springs from.
  static const double _trayLift = 14;

  /// How far past the row a finger may stray before the pick is abandoned.
  /// Asymmetric on purpose: sliding *down* is how people back out, so that
  /// side is tighter than the one they overshoot into while aiming.
  static const double _cancelBelow = 64;
  static const double _cancelAbove = 110;

  final _buttonKey = GlobalKey();

  late final AnimationController _reveal;

  OverlayEntry? _tray;

  /// The tray that is playing its closing animation. Held separately from
  /// [_tray] so a dispose landing mid-close still has something to remove.
  OverlayEntry? _closing;

  /// Global rect of the open tray, fixed at the moment it opens. Held rather
  /// than measured per move so aiming is answered by arithmetic instead of a
  /// hit test on every frame of the drag.
  Rect _trayRect = Rect.zero;
  double _itemExtent = _maxItemExtent;

  FitReaction? _hovered;

  @override
  void initState() {
    super.initState();
    _reveal = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      reverseDuration: const Duration(milliseconds: 140),
    );
  }

  @override
  void dispose() {
    // Removed directly rather than through _closeTray: that one animates and
    // notifies the host, and neither is safe from dispose.
    for (final entry in [_tray, _closing]) {
      if (entry != null && entry.mounted) entry.remove();
    }
    _tray = null;
    _closing = null;
    _reveal.dispose();
    super.dispose();
  }

  /// A bare tap: give a Like, or take back whatever is held.
  void _handleTap() {
    HapticFeedback.selectionClick();
    widget.onChanged(
      widget.selected == null ? FitReaction.defaultReaction : null,
    );
  }

  void _openTray() {
    if (_tray != null) return;

    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    final box = _buttonKey.currentContext?.findRenderObject();
    if (overlay == null || box is! RenderBox || !box.hasSize) return;

    final overlayBox = overlay.context.findRenderObject();
    if (overlayBox is! RenderBox) return;

    final anchor = box.localToGlobal(Offset.zero, ancestor: overlayBox);
    final screen = overlayBox.size;

    // Seven slots, shrunk to fit rather than clipped, with a margin at each
    // edge so the row never runs into the side of the screen.
    const margin = 12.0;
    final available = screen.width - (margin * 2) - (_trayPadding * 2);
    _itemExtent =
        math.min(_maxItemExtent, available / FitReaction.all.length);

    final trayWidth =
        (_itemExtent * FitReaction.all.length) + (_trayPadding * 2);
    final trayHeight = _itemExtent + (_trayPadding * 2);

    // Centred on the button, then pushed back inside the screen — a bar near
    // the edge would otherwise hang the row half off it.
    final left = (anchor.dx + (box.size.width / 2) - (trayWidth / 2))
        .clamp(margin, math.max(margin, screen.width - trayWidth - margin))
        .toDouble();

    _trayRect = Rect.fromLTWH(
      left,
      anchor.dy - trayHeight - _trayLift,
      trayWidth,
      trayHeight,
    );
    _hovered = null;

    _tray = OverlayEntry(builder: (context) => _buildTray());
    overlay.insert(_tray!);
    _reveal.forward(from: 0);
    HapticFeedback.mediumImpact();
    widget.onTrayVisibilityChanged?.call(true);
  }

  /// Closes the tray and reports [picked] if the finger came up on a reaction.
  Future<void> _closeTray({FitReaction? picked}) async {
    final tray = _tray;
    if (tray == null) return;
    _tray = null;
    _closing = tray;

    widget.onTrayVisibilityChanged?.call(false);
    if (picked != null && picked != widget.selected) {
      HapticFeedback.mediumImpact();
      widget.onChanged(picked);
    }

    if (mounted) await _reveal.reverse();
    _closing = null;
    // The widget may have gone away during the animation, in which case
    // dispose has already taken the entry down.
    if (tray.mounted) tray.remove();
  }

  /// Which reaction the finger is over, null when it has strayed off the row.
  FitReaction? _faceAt(Offset global) {
    if (global.dy > _trayRect.bottom + _cancelBelow) return null;
    if (global.dy < _trayRect.top - _cancelAbove) return null;

    final x = global.dx - _trayRect.left - _trayPadding;
    // Half a slot of slack at each end, so aiming at the first or last reaction
    // doesn't demand more precision than the ones in the middle.
    if (x < -_itemExtent / 2) return null;
    if (x > (_itemExtent * FitReaction.all.length) + (_itemExtent / 2)) {
      return null;
    }

    final index = (x ~/ _itemExtent).clamp(0, FitReaction.all.length - 1);
    return FitReaction.all[index];
  }

  void _updateHover(Offset global) {
    final reaction = _faceAt(global);
    if (reaction == _hovered) return;
    _hovered = reaction;
    if (reaction != null) HapticFeedback.selectionClick();
    // The tray lives in the overlay, so it is not rebuilt by this widget's
    // setState — it has to be told directly.
    _tray?.markNeedsBuild();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: _buttonKey,
      behavior: HitTestBehavior.opaque,
      onTap: _handleTap,
      onLongPressStart: (_) => _openTray(),
      onLongPressMoveUpdate: (details) => _updateHover(details.globalPosition),
      onLongPressEnd: (_) => _closeTray(picked: _hovered),
      onLongPressCancel: () => _closeTray(),
      child: widget.child,
    );
  }

  Widget _buildTray() {
    return Positioned.fromRect(
      rect: _trayRect,
      // The row must not swallow the long-press that opened it — the gesture
      // is still live on the button underneath, and it is the one steering.
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _reveal,
          builder: (context, _) => _ReactionTray(
            reveal: _reveal.value,
            hovered: _hovered,
            selected: widget.selected,
            itemExtent: _itemExtent,
            padding: _trayPadding,
          ),
        ),
      ),
    );
  }
}

/// The row of seven reactions, and the name of whichever one is under the finger.
class _ReactionTray extends StatelessWidget {
  const _ReactionTray({
    required this.reveal,
    required this.hovered,
    required this.selected,
    required this.itemExtent,
    required this.padding,
  });

  /// 0 closed, 1 fully open. Drives the whole tray's rise and each reaction's
  /// staggered pop.
  final double reveal;

  final FitReaction? hovered;
  final FitReaction? selected;
  final double itemExtent;
  final double padding;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: reveal.clamp(0.0, 1.0),
      child: Transform.translate(
        // Rises out of the button rather than appearing in place.
        offset: Offset(0, (1 - reveal) * 18),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xF21C1C1E),
                borderRadius: BorderRadius.circular(itemExtent),
                border: Border.all(color: const Color(0x26FFFFFF)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x66000000),
                    blurRadius: 18,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Padding(
                padding: EdgeInsets.all(padding),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < FitReaction.all.length; i++)
                      _TrayReaction(
                        reaction: FitReaction.all[i],
                        extent: itemExtent,
                        // Each lands a beat after the one before it,
                        // which is what reads as the row unrolling.
                        entrance: _staggered(i),
                        isHovered: FitReaction.all[i] == hovered,
                        isSelected: FitReaction.all[i] == selected,
                      ),
                  ],
                ),
              ),
            ),
            if (hovered != null) _label(hovered!),
          ],
        ),
      ),
    );
  }

  /// One reaction's share of the reveal, offset so the row arrives in order.
  double _staggered(int index) {
    const step = 0.07;
    final start = index * step;
    final span = 1 - (step * (FitReaction.all.length - 1));
    final local = ((reveal - start) / span).clamp(0.0, 1.0);
    return Curves.easeOutBack.transform(local);
  }

  /// The name of the aimed-at reaction, in a bubble above the row — the only
  /// thing that tells "Respect" from "Champion" before committing to it.
  Widget _label(FitReaction reaction) {
    final index = FitReaction.all.indexOf(reaction);
    final centre = padding + (index * itemExtent) + (itemExtent / 2);

    return Positioned(
      top: -30,
      left: centre - 44,
      width: 88,
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xF2000000),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Text(
              reaction.label,
              style: const TextStyle(
                color: AppColors.onMedia,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TrayReaction extends StatelessWidget {
  const _TrayReaction({
    required this.reaction,
    required this.extent,
    required this.entrance,
    required this.isHovered,
    required this.isSelected,
  });

  final FitReaction reaction;
  final double extent;
  final double entrance;
  final bool isHovered;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: extent,
      height: extent,
      child: AnimatedScale(
        // The aimed-at reaction grows well past its neighbours: at a thumb's
        // distance the size difference is more readable than the label is.
        scale: isHovered ? 1.42 : 1,
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOut,
        child: AnimatedSlide(
          offset: isHovered ? const Offset(0, -0.22) : Offset.zero,
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOut,
          child: Transform.scale(
            scale: entrance,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                // A ring under the reaction you already hold, so the tray opens
                // showing where you stand.
                color: isSelected
                    ? reaction.accent.withValues(alpha: 0.28)
                    : Colors.transparent,
              ),
              child: Center(
                child: Text(
                  reaction.emoji,
                  style: TextStyle(fontSize: extent * 0.62),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The reaction control over a Pulse: a labelled pill, on the dark chrome.
///
/// A [ReactionTrigger] around a pill, and nothing more — the gesture lives in
/// the trigger so the post card can wear a different face on the same one.
class ReactionBar extends StatelessWidget {
  const ReactionBar({
    required this.selected,
    required this.onChanged,
    this.onTrayVisibilityChanged,
    super.key,
  });

  final FitReaction? selected;
  final ValueChanged<FitReaction?> onChanged;
  final ValueChanged<bool>? onTrayVisibilityChanged;

  @override
  Widget build(BuildContext context) {
    return ReactionTrigger(
      selected: selected,
      onChanged: onChanged,
      onTrayVisibilityChanged: onTrayVisibilityChanged,
      child: _ReactionPill(selected: selected),
    );
  }
}

/// The button itself: the reaction you gave and its name, or a dimmed
/// default when you haven't given one.
class _ReactionPill extends StatelessWidget {
  const _ReactionPill({required this.selected});

  final FitReaction? selected;

  @override
  Widget build(BuildContext context) {
    final reaction = selected;
    final accent = reaction?.accent;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: accent == null
            ? const Color(0x33FFFFFF)
            : accent.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: accent == null
              ? const Color(0x40FFFFFF)
              : accent.withValues(alpha: 0.9),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            (reaction ?? FitReaction.defaultReaction).emoji,
            style: TextStyle(
              fontSize: 17,
              // The unpicked default reads as dimmed rather than full colour,
              // so a bar nobody has touched can't be mistaken for one that
              // has been.
              color: reaction == null ? const Color(0x99FFFFFF) : null,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            (reaction ?? FitReaction.defaultReaction).label,
            style: TextStyle(
              color: reaction == null ? const Color(0xCCFFFFFF) : accent,
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// The reaction control on a post card: an emoji and a count, sized to sit in
/// a row of plain icons without shouting over them.
///
/// Wears the outline heart until you react, because a feed of posts nobody has
/// touched should read as quiet — a row of 🧡 at rest would look like everyone
/// had already joined in.
class PostReactionIcon extends StatelessWidget {
  const PostReactionIcon({
    required this.selected,
    required this.count,
    required this.onChanged,
    this.size = 22,
    this.restingColor,
    super.key,
  });

  final FitReaction? selected;
  final int count;
  final ValueChanged<FitReaction?> onChanged;
  final double size;

  /// Colour of the untouched heart and its count. Defaults to the muted tone
  /// the rest of the row uses.
  final Color? restingColor;

  @override
  Widget build(BuildContext context) {
    final reaction = selected;
    final resting = restingColor ?? const Color(0xFF8A8A8E);
    final tint = reaction?.accent ?? resting;

    return ReactionTrigger(
      selected: reaction,
      onChanged: onChanged,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: size,
              height: size,
              child: Center(
                child: reaction == null
                    ? Icon(
                        Icons.favorite_border_rounded,
                        size: size,
                        color: resting,
                      )
                    // Sized under the icon's own box: an emoji drawn at the
                    // icon's size sits taller than the glyph beside it and
                    // makes the row jump when somebody reacts.
                    : Text(
                        reaction.emoji,
                        style: TextStyle(fontSize: size * 0.82),
                      ),
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Text(
                '$count',
                style: TextStyle(
                  color: tint,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The stacked reactions and total under a Pulse — "😆❤️👍 24".
///
/// Facebook shows the three leading reactions and the count, which is enough
/// to tell you what the room felt without listing everybody. Tapping opens the
/// full breakdown.
class ReactionSummaryRow extends StatelessWidget {
  const ReactionSummaryRow({
    required this.summary,
    required this.onTap,
    super.key,
  });

  final FitReactionSummary summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (summary.isEmpty) return const SizedBox.shrink();

    final reactions = summary.topReactions;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Overlapped left to right, the leading reaction on top.
          SizedBox(
            width: 20.0 + ((reactions.length - 1) * 13),
            height: 22,
            child: Stack(
              children: [
                for (var i = reactions.length - 1; i >= 0; i--)
                  Positioned(
                    left: i * 13,
                    child: _StackedReaction(reaction: reactions[i]),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '${summary.total}',
            style: const TextStyle(
              color: AppColors.onMedia,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _StackedReaction extends StatelessWidget {
  const _StackedReaction({required this.reaction});

  final FitReaction reaction;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: reaction.accent.withValues(alpha: 0.9),
        // A rim against the photo behind it: without one the reactions smear into
        // each other and into whatever the Pulse is showing.
        border: Border.all(color: AppColors.mediaBackdrop, width: 1.5),
      ),
      child: Text(reaction.emoji, style: const TextStyle(fontSize: 11)),
    );
  }
}
