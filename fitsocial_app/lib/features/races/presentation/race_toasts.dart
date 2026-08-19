import 'package:flutter/material.dart';

import '../../../shared/widgets/quick_toast.dart';

/// Confirms a save or an unsave.
///
/// One helper for all three places a race can be bookmarked — the calendar, the
/// detail screen and the saved list — so the wording and the glyph cannot drift
/// apart between them. It is a [showQuickToast] pill rather than a `SnackBar`
/// because the bar docks to the Scaffold and slides in behind the floating nav.
void showRaceSavedToast(BuildContext context, {required bool saved}) {
  showQuickToast(
    context,
    _savedMessage(saved),
    icon: _savedIcon(saved),
    tone: saved ? ToastTone.success : ToastTone.neutral,
  );
}

/// [showRaceSavedToast] for callers whose context may be gone by the time the
/// write returns — an unsaved row leaving the list, a popped detail screen.
void showRaceSavedToastOn(OverlayState overlay, {required bool saved}) {
  showQuickToastOn(
    overlay,
    _savedMessage(saved),
    icon: _savedIcon(saved),
    tone: saved ? ToastTone.success : ToastTone.neutral,
  );
}

void showRaceSaveFailedToast(BuildContext context) {
  showQuickToast(
    context,
    _failedMessage,
    icon: Icons.error_outline_rounded,
    tone: ToastTone.danger,
  );
}

void showRaceSaveFailedToastOn(OverlayState overlay) {
  showQuickToastOn(
    overlay,
    _failedMessage,
    icon: Icons.error_outline_rounded,
    tone: ToastTone.danger,
  );
}

String _savedMessage(bool saved) =>
    saved ? 'Saved to my races' : 'Removed from my races';

IconData _savedIcon(bool saved) =>
    saved ? Icons.bookmark_added_rounded : Icons.bookmark_remove_rounded;

// The raw exception used to be shown here. It told the user nothing they could
// act on, so the failure says what to do instead.
const _failedMessage = "Couldn't update your races. Try again.";
