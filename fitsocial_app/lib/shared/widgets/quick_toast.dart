import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme/app_palette.dart';

/// How a toast is tinted. The tone only colours the glyph disc — the pill
/// itself stays on [AppPalette.surface] so a confirmation never reads as an
/// alert bar the way a full-bleed coloured `SnackBar` does.
enum ToastTone { neutral, success, danger }

/// A small floating confirmation pill: "Post deleted", "Copied", and friends.
///
/// Deliberately not a `SnackBar`. A snackbar is anchored to the nearest
/// `Scaffold`, so it slides in *behind* the floating nav, reflows the layout it
/// docks to, and — because the messenger queues — a second message waits out
/// the first one's full four seconds. This rides the root [Overlay] instead:
/// it floats over everything including open sheets, never touches layout, and
/// a new toast replaces the one on screen instead of queueing behind it.
///
/// The default [visibleFor] is short on purpose. This is an acknowledgement of
/// something the user just did, not a notification they need to read.
void showQuickToast(
  BuildContext context,
  String message, {
  IconData icon = Icons.check_rounded,
  ToastTone tone = ToastTone.neutral,
  Duration visibleFor = const Duration(milliseconds: 1150),
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  showQuickToastOn(
    overlay,
    message,
    icon: icon,
    tone: tone,
    visibleFor: visibleFor,
  );
}

/// [showQuickToast] for callers that no longer have a mounted context.
///
/// Exists for the flows that confirm an action *and* leave the screen — pop the
/// route, then toast. Grab the [OverlayState] before the pop and the message
/// still lands, because the root overlay outlives the route that triggered it.
void showQuickToastOn(
  OverlayState overlay,
  String message, {
  IconData icon = Icons.check_rounded,
  ToastTone tone = ToastTone.neutral,
  Duration visibleFor = const Duration(milliseconds: 1150),
}) {
  if (!overlay.mounted) return;

  // Only ever one toast on screen. Whatever is showing is now stale.
  _currentToast?.dismiss();

  late final _ToastHandle handle;
  final entry = OverlayEntry(
    builder: (_) => _QuickToast(
      message: message,
      icon: icon,
      tone: tone,
      visibleFor: visibleFor,
      onFinished: () => handle.remove(),
      register: (dismiss) => handle.dismiss = dismiss,
    ),
  );

  handle = _ToastHandle(entry);
  _currentToast = handle;
  overlay.insert(entry);
}

_ToastHandle? _currentToast;

/// Lets [showQuickToast] retire the toast that is already on screen without the
/// widget and the entry holding references to each other.
class _ToastHandle {
  _ToastHandle(this.entry);

  final OverlayEntry entry;

  /// Set by the toast once it is mounted: plays the exit animation, which then
  /// calls [remove].
  VoidCallback dismiss = () {};

  bool _removed = false;

  void remove() {
    if (_removed) return;
    _removed = true;
    entry.remove();
    if (identical(_currentToast?.entry, entry)) _currentToast = null;
  }
}

class _QuickToast extends StatefulWidget {
  const _QuickToast({
    required this.message,
    required this.icon,
    required this.tone,
    required this.visibleFor,
    required this.onFinished,
    required this.register,
  });

  final String message;
  final IconData icon;
  final ToastTone tone;
  final Duration visibleFor;
  final VoidCallback onFinished;
  final ValueChanged<VoidCallback> register;

  @override
  State<_QuickToast> createState() => _QuickToastState();
}

class _QuickToastState extends State<_QuickToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    reverseDuration: const Duration(milliseconds: 180),
  );

  Timer? _holdTimer;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    widget.register(_leave);
    _controller.forward();
    _holdTimer = Timer(widget.visibleFor + _controller.duration!, _leave);
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    _holdTimer?.cancel();
    await _controller.reverse();
    if (mounted) widget.onFinished();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final accent = switch (widget.tone) {
      ToastTone.neutral => palette.text,
      ToastTone.success => palette.success,
      ToastTone.danger => palette.danger,
    };

    final curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeIn,
    );

    return Positioned(
      // Clears the floating nav on the tabbed screens and still sits
      // comfortably above the home indicator on the ones without it.
      bottom: MediaQuery.viewPaddingOf(context).bottom + 96,
      left: 24,
      right: 24,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: curve,
          builder: (context, child) {
            // `easeOutBack` overshoots past 1, which is the little pop on the
            // way in — but opacity has to stay legal, hence the clamp.
            final t = curve.value;
            return Opacity(
              opacity: t.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, 18 * (1 - t)),
                child: Transform.scale(scale: 0.94 + 0.06 * t, child: child),
              ),
            );
          },
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 18, 10),
                decoration: BoxDecoration(
                  color: palette.surface,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: palette.stroke),
                  boxShadow: [
                    BoxShadow(
                      color: palette.navShadow,
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(widget.icon, size: 16, color: accent),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        widget.message,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
