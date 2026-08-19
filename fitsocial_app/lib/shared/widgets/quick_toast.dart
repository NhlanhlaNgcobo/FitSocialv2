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
/// The default time on screen is short on purpose: this is an acknowledgement
/// of something the user just did, not a notification they need to read. The
/// two cases that *are* read — a failure, and a toast carrying an [actionLabel]
/// the user has to reach for — get longer on their own, so no call site has to
/// remember to ask.
///
/// [actionLabel] and [onAction] add one inline button ("Undo"). Without them
/// the pill ignores pointers entirely, so it can never swallow a tap meant for
/// the screen underneath.
void showQuickToast(
  BuildContext context,
  String message, {
  IconData icon = Icons.check_rounded,
  ToastTone tone = ToastTone.neutral,
  Duration? visibleFor,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  showQuickToastOn(
    overlay,
    message,
    icon: icon,
    tone: tone,
    visibleFor: visibleFor,
    actionLabel: actionLabel,
    onAction: onAction,
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
  Duration? visibleFor,
  String? actionLabel,
  VoidCallback? onAction,
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
      visibleFor: visibleFor ?? _defaultDuration(tone, actionLabel != null),
      actionLabel: actionLabel,
      onAction: onAction,
      onFinished: () => handle.remove(),
      register: (dismiss) => handle.dismiss = dismiss,
    ),
  );

  handle = _ToastHandle(entry);
  _currentToast = handle;
  overlay.insert(entry);
}

/// How long a toast stays up when the caller does not say.
///
/// An acknowledgement is gone before it is in the way. A failure has to be
/// read, and anything with a button has to be reachable — those two hold.
Duration _defaultDuration(ToastTone tone, bool hasAction) {
  if (hasAction) return const Duration(milliseconds: 3600);
  if (tone == ToastTone.danger) return const Duration(milliseconds: 2600);
  return const Duration(milliseconds: 1150);
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
    required this.actionLabel,
    required this.onAction,
    required this.onFinished,
    required this.register,
  });

  final String message;
  final IconData icon;
  final ToastTone tone;
  final Duration visibleFor;
  final String? actionLabel;
  final VoidCallback? onAction;
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
        // A plain acknowledgement must never eat a tap aimed at the screen
        // behind it; one carrying a button obviously has to take them.
        ignoring: widget.actionLabel == null,
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
                padding: EdgeInsets.fromLTRB(
                  12,
                  10,
                  widget.actionLabel == null ? 18 : 10,
                  10,
                ),
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
                    if (widget.actionLabel case final label?) ...[
                      const SizedBox(width: 12),
                      // Taking the action retires the toast with it: leaving an
                      // "Undo" on screen that has already been used invites a
                      // second tap that would do nothing.
                      _ToastAction(
                        label: label,
                        onPressed: () {
                          widget.onAction?.call();
                          _leave();
                        },
                      ),
                    ],
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

/// The one button a toast is allowed: an inline word, in the brand orange, big
/// enough to hit without turning the pill into a bar.
class _ToastAction extends StatelessWidget {
  const _ToastAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    // Its own Material, inside the pill rather than the one wrapping it: ink
    // paints on the nearest Material *under* that material's children, so a
    // splash from the outer one would land behind the pill's own background.
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            label.toUpperCase(),
            style: TextStyle(
              color: palette.brandText,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
        ),
      ),
    );
  }
}
