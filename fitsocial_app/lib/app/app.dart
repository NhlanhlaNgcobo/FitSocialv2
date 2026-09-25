import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/bootstrap/bootstrap_status.dart';
import '../features/notifications/application/push_tap_router.dart';
import '../features/safety/application/safety_providers.dart';
import '../features/safety/application/safety_shortcuts.dart';
import '../shared/widgets/liquid_backdrop.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';
import 'theme/theme_mode_controller.dart';

class FitSocialApp extends ConsumerStatefulWidget {
  const FitSocialApp({super.key});

  @override
  ConsumerState<FitSocialApp> createState() => _FitSocialAppState();
}

class _FitSocialAppState extends ConsumerState<FitSocialApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // A panic still open from before the app was closed -- including one kept
    // running by the duress PIN -- picks its live location back up. Only from
    // the foreground: neither platform lets background location start there.
    WidgetsBinding.instance.addPostFrameCallback((_) => _resumeSafety());
    // The app-icon "Send alert" shortcut and the volume-button pattern. Early,
    // like push taps: a shortcut that launched the app is waiting to be read.
    if (ref.read(bootstrapStatusProvider).canUseFirebase) {
      ref.read(safetyShortcutsProvider).start();
    }
    // Started here rather than lazily from a screen, because the case it exists
    // for is the one where no screen has been built yet: a notification tapped
    // while the app was not running. `getInitialMessage` has an answer waiting
    // from the moment the engine starts, and asking late means asking after the
    // router has already sent the user to the feed.
    ref.read(pushTapRouterProvider).start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _resumeSafety();
  }

  void _resumeSafety() {
    // A build without Firebase has no alerts to resume, and asking who is
    // signed in would throw.
    if (!ref.read(bootstrapStatusProvider).canUseFirebase) return;
    ref.read(panicControllerProvider.notifier).resumeOpenEvent();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'FitSocial',
      debugShowCheckedModeBanner: false,
      // Both themes are always supplied; [themeMode] decides. On
      // ThemeMode.system that hands the choice to the OS and MaterialApp
      // re-resolves it whenever the platform brightness changes, with no work
      // from us.
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: router,
      // The one ground the whole app looks through, painted below the Navigator
      // so every route shares it — pushed or not, inside the tab shell or not.
      //
      // Below the Navigator rather than inside each page on purpose. A page
      // transition then crossfades two screens over one continuous backdrop
      // instead of sliding two backdrops past each other, and the ground stays
      // still while the screens move, which is what a ground should do.
      builder: (context, child) => Stack(
        children: [
          const Positioned.fill(child: LiquidBackdrop()),
          if (child != null) child,
        ],
      ),
    );
  }
}
