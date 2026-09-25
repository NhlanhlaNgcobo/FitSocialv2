import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quick_actions/quick_actions.dart';

import '../../../app/router/app_router.dart';
import '../../auth/application/app_session.dart';
import '../domain/volume_pattern.dart';
import 'panic_controller.dart';
import 'safety_providers.dart';

/// The ways into a silent alert that are not a button on a screen: the app
/// icon's long-press menu, and the volume-button pattern.
///
/// Started once from the app root, and only for a build with Firebase — with
/// nobody to alert there is nothing for either to do.
class SafetyShortcuts {
  SafetyShortcuts(this._ref);

  static const String sendAlertType = 'send_alert';

  final Ref _ref;
  final QuickActions _quickActions = const QuickActions();
  final VolumePattern _volume = VolumePattern();
  bool _started = false;
  VoidCallback? _sessionListener;

  void start() {
    if (_started) return;
    _started = true;

    // The app icon's long-press menu. Works on Android and iPhone alike, and
    // shows nothing anywhere until somebody long-presses the icon.
    _quickActions.initialize((type) {
      if (type == sendAlertType) _sendFromShortcut();
    });
    _quickActions.setShortcutItems(const [
      ShortcutItem(type: sendAlertType, localizedTitle: 'Send alert'),
    ]);

    // Volume buttons: Flutter sees them on Android while the app is on screen,
    // and passes them on untouched so the volume still changes. iOS never
    // reports them, so there the handler simply never fires.
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _stopWaiting();
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final key = switch (event.logicalKey) {
      LogicalKeyboardKey.audioVolumeUp => VolumeKey.up,
      LogicalKeyboardKey.audioVolumeDown => VolumeKey.down,
      _ => null,
    };
    if (key == null) return false;
    final enabled = _ref
            .read(safetySettingsProvider)
            .valueOrNull
            ?.volumeShortcutEnabled ??
        false;
    if (enabled &&
        _ref.read(appSessionProvider).stage == AuthStage.authenticated &&
        _volume.press(key, DateTime.now())) {
      _sendSilently();
    }
    // Never consumed: the button still changes the volume, so nothing on
    // screen or in the hand gives the pattern away.
    return false;
  }

  /// From the volume buttons: no screen change at all. One firm vibration,
  /// felt by the person holding the phone and nobody else, says it went.
  void _sendSilently() {
    final state = _ref.read(panicControllerProvider);
    if (state.phase == PanicPhase.dispatching ||
        state.phase == PanicPhase.active) {
      return;
    }
    HapticFeedback.heavyImpact();
    _ref.read(panicControllerProvider.notifier).trigger();
  }

  /// From the app icon: the app is opening anyway, so it opens on the alert
  /// screen. On a cold start the session is still restoring; the alert waits
  /// for it rather than being dropped.
  void _sendFromShortcut() {
    if (_ref.read(appSessionProvider).stage == AuthStage.authenticated) {
      _sendAndShow(layHomeFirst: false);
      return;
    }
    if (_sessionListener != null) return;
    final session = _ref.read(appSessionProvider);
    void onChanged() {
      if (session.stage != AuthStage.authenticated) return;
      _stopWaiting();
      _sendAndShow(layHomeFirst: true);
    }

    _sessionListener = onChanged;
    session.addListener(onChanged);
  }

  void _stopWaiting() {
    final listener = _sessionListener;
    if (listener != null) {
      _ref.read(appSessionProvider).removeListener(listener);
    }
    _sessionListener = null;
  }

  void _sendAndShow({required bool layHomeFirst}) {
    _ref.read(panicControllerProvider.notifier).trigger();
    // After the frame, for the same reason as notification taps: the router
    // may still be resolving the redirect that brought the session in.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final router = _ref.read(appRouterProvider);
      if (layHomeFirst) router.go('/home');
      router.push('/safety/panic');
    });
    // A warm app sitting idle schedules no frame of its own, and the callback
    // above would wait for one.
    WidgetsBinding.instance.scheduleFrame();
  }
}

/// Read only from a build with Firebase: the settings it keeps subscribed ask
/// who is signed in, which has no answer without it.
final safetyShortcutsProvider = Provider<SafetyShortcuts>((ref) {
  // Kept subscribed so the volume setting is known the moment a key arrives,
  // rather than loading on the first press and missing it.
  ref.listen(safetySettingsProvider, (_, __) {});
  final shortcuts = SafetyShortcuts(ref);
  ref.onDispose(shortcuts.dispose);
  return shortcuts;
});
