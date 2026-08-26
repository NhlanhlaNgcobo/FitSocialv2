import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Whether the app is between screens — and so whether every pane of glass
/// should hold still.
///
/// ## Why glass and page transitions cannot both have their way
///
/// A [BackdropFilter] filters what has *already been painted into the layer it
/// sits in*. A screen change fades, and a fade is an `Opacity`, which paints
/// its subtree into a fresh, empty offscreen buffer. A pane of liquid glass
/// inside that buffer has no backdrop at all: the lens bends nothing, the frost
/// blurs nothing, and every glass surface on the arriving screen renders as a
/// hole for the length of the transition — then snaps into being glass on the
/// single frame the fade completes and the buffer goes away.
///
/// That snap is the glitch. The cost is the other half of it: mid-transition
/// two whole screens' worth of backdrop filters are live on the same frame,
/// each one a full-surface read the compositor cannot batch, on top of whatever
/// the transition itself is doing.
///
/// So the transitions declare their motion here and [LiquidGlass] answers by
/// dropping its filter for the duration, painting the same material statically:
/// the same tint, the same sheen, the same rim — everything except the one part
/// that reads the screen behind it. Nothing is lost that can be seen at speed.
///
/// ## Where the filter comes back
///
/// Both transitions finish fading *before* they finish moving, and call [end]
/// at the moment their screen becomes fully opaque rather than at the moment it
/// stops. The filter therefore returns while the screen is still travelling the
/// last of its distance, so the hand-off lands under motion instead of on a
/// still frame, which is the only place it could be noticed.
class GlassMotion {
  GlassMotion._();

  /// False while any transition is in flight. Glass surfaces listen directly
  /// rather than reading an inherited widget: a screen change would otherwise
  /// rebuild every page in the shell twice, at exactly the moment there is no
  /// frame budget for it.
  static final ValueNotifier<bool> settled = ValueNotifier<bool>(true);

  /// How many transitions are running. A push landing on a shell whose branch
  /// is still cross-fading is ordinary, and the lens must stay off until the
  /// last of them is done.
  static int _depth = 0;

  static bool _pending = false;

  /// Declares that a screen change has started. Every [begin] must be paired
  /// with an [end], including from `dispose` — a route torn down mid-flight
  /// would otherwise leave the whole app frozen.
  static void begin() {
    _depth++;
    _sync();
  }

  static void end() {
    if (_depth == 0) return;
    _depth--;
    _sync();
  }

  static void _sync() {
    final value = _depth == 0;
    if (settled.value == value) return;

    // A branch change arrives through `didUpdateWidget`, which runs inside the
    // build phase. Notifying now would mark glass surfaces outside the subtree
    // currently building — the bottom nav, most of all — and that is a
    // setState-during-build. One frame late is invisible: at the start of a
    // transition the arriving screen is still fully transparent, and at the end
    // the lens is a frame later coming back.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_pending) return;
      _pending = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _pending = false;
        // Re-read rather than replaying the captured value: several
        // transitions may have started and finished inside the one frame.
        final settledNow = _depth == 0;
        if (settled.value != settledNow) settled.value = settledNow;
      });
      return;
    }

    settled.value = value;
  }

  @visibleForTesting
  static void resetForTest() {
    _depth = 0;
    _pending = false;
    settled.value = true;
  }
}
