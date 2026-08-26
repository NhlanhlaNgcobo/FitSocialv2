import 'package:flutter/material.dart';

import '../widgets/glass_motion.dart';

/// Moves between the shell's five branches when a nav destination is tapped.
///
/// The default `StatefulShellRoute.indexedStack` cuts straight from one branch
/// to the next on the same frame, which is the one place in the app a screen
/// change happens with no motion at all.
///
/// ## Why a fade-through and not a cross-fade
///
/// The destinations are siblings, not a hierarchy — Profile is not "inside"
/// Home — so nothing should look like it slid in from a direction. The Material
/// fade-through pattern is built for exactly that: the outgoing branch is
/// fully gone by the time the incoming one starts to appear, so the two never
/// overlap into a doubled, half-legible image. The incoming branch also scales
/// up from slightly small, which gives the change a direction in depth without
/// implying one on screen.
///
/// ## State
///
/// Every branch stays in the tree for its whole life — scroll positions, form
/// text and in-flight requests survive a tab switch, exactly as they did under
/// the IndexedStack. Branches that are neither arriving nor leaving are held
/// [Offstage], so they cost nothing to paint and their tickers are stopped.
///
/// ## What it costs to fade a screen full of glass
///
/// A fade is an opacity layer, and a pane of liquid glass inside one has no
/// backdrop left to bend — see [GlassMotion]. So the fade is declared there and
/// every glass surface in the app holds still until it is over, which is also
/// what keeps two branches' worth of backdrop filters off the same frame.
///
/// The arriving branch is opaque before it has finished scaling, so the lens
/// comes back while the branch is still moving rather than on a still frame.
/// The [RepaintBoundary] around each branch is the other half of that bargain:
/// it lets the opacity and the scale composite a raster the branch already has
/// instead of repainting a whole screen on every frame of the change.
class BranchTransition extends StatefulWidget {
  const BranchTransition({
    required this.currentIndex,
    required this.children,
    super.key,
  });

  final int currentIndex;

  /// One navigator per branch, in branch order.
  final List<Widget> children;

  @override
  State<BranchTransition> createState() => _BranchTransitionState();
}

class _BranchTransitionState extends State<BranchTransition>
    with SingleTickerProviderStateMixin {
  static const Duration _duration = Duration(milliseconds: 300);

  /// The outgoing third and the incoming two thirds do not overlap — that gap
  /// is what separates a fade-through from a muddy dissolve.
  static const Interval _outInterval = Interval(0, 0.3, curve: Curves.easeOut);
  static const Interval _inInterval = Interval(0.3, 0.8, curve: Curves.easeOut);

  /// The scale outlasts the fade. The branch is fully legible for the last
  /// fifth of the change and only still settling, which is where the glass gets
  /// its filter back unnoticed.
  static const Interval _scaleInterval =
      Interval(0.3, 1, curve: Curves.easeOut);

  /// How small the arriving branch starts. Barely perceptible on its own; what
  /// registers is that the screen resolves into place rather than blinking on.
  static const double _arrivalScale = 0.94;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _duration,
    // Settled on the starting branch — nothing to animate until a tap.
    value: 1,
  );

  /// The branch being left behind, painted only while the transition runs.
  late int _outgoing = widget.currentIndex;

  /// Whether this transition is currently counted against [GlassMotion].
  bool _holding = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_syncMotion);
  }

  @override
  void didUpdateWidget(BranchTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentIndex == oldWidget.currentIndex) return;

    // From zero rather than resuming: a tap during a transition should play the
    // arrival of the branch just asked for, not finish the previous one.
    _outgoing = oldWidget.currentIndex;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.removeListener(_syncMotion);
    _controller.dispose();
    // Torn down mid-change, this still owes its [GlassMotion.begin].
    if (_holding) {
      _holding = false;
      GlassMotion.end();
    }
    super.dispose();
  }

  /// Whether an opacity of [value] costs an offscreen buffer.
  ///
  /// Flutter paints straight through at both ends — a fully opaque branch needs
  /// no layer, and a fully transparent one is never painted — so only the span
  /// strictly between them is a fade the glass has to sit out.
  static bool _buffered(double value) => value > 0 && value < 1;

  void _syncMotion() {
    final t = _controller.value;
    final holding = _buffered(_inInterval.transform(t)) ||
        _buffered(1 - _outInterval.transform(t));
    if (holding == _holding) return;
    _holding = holding;
    holding ? GlassMotion.begin() : GlassMotion.end();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final settled = !_controller.isAnimating;

        return Stack(
          fit: StackFit.expand,
          children: [
            for (var i = 0; i < widget.children.length; i++)
              _branch(i, settled: settled),
          ],
        );
      },
    );
  }

  /// One branch, in whichever of the three states it is currently in.
  ///
  /// Every branch is wrapped in the *same* chain of widgets in every state,
  /// only their parameters differ. That is not stylistic: changing the shape of
  /// the tree above a branch — dropping the wrappers once the transition ends,
  /// say — gives its element a different slot, and Flutter answers that by
  /// discarding the subtree and building a fresh one. The branch would come
  /// back scrolled to the top with its forms blank on every single tab switch.
  Widget _branch(int index, {required bool settled}) {
    final isCurrent = index == widget.currentIndex;
    final isLeaving = index == _outgoing && !settled;

    // Neither arriving nor leaving: alive, but off the paint and layout path.
    final parked = !isCurrent && !isLeaving;

    final t = _controller.value;
    final double opacity;
    var scale = 1.0;

    if (isCurrent) {
      opacity = settled ? 1.0 : _inInterval.transform(t);
      final arrival = settled ? 1.0 : _scaleInterval.transform(t);
      scale = _arrivalScale + (1 - _arrivalScale) * arrival;
    } else if (isLeaving) {
      opacity = 1 - _outInterval.transform(t);
    } else {
      opacity = 0;
    }

    return Offstage(
      offstage: parked,
      child: TickerMode(
        enabled: !parked,
        // Not interactive until it has arrived, so a stray tap mid-transition
        // cannot land on a control that is still moving.
        child: IgnorePointer(
          ignoring: !isCurrent || !settled,
          // Both are no-ops at rest — Opacity at 1 and an identity transform
          // paint their child directly without allocating a layer — so the
          // settled branch pays nothing for being wrapped.
          child: Opacity(
            opacity: opacity,
            child: Transform.scale(
              scale: scale,
              // The branch keeps its own raster, so the fade and the scale
              // above composite a picture that already exists rather than
              // dragging a whole screen through a repaint every frame.
              child: RepaintBoundary(child: widget.children[index]),
            ),
          ),
        ),
      ),
    );
  }
}
