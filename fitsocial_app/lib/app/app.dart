import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/widgets/liquid_backdrop.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';
import 'theme/theme_mode_controller.dart';

class FitSocialApp extends ConsumerWidget {
  const FitSocialApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
