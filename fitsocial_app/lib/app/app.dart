import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    );
  }
}
