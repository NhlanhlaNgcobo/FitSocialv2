import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/theme/theme_mode_controller.dart';
import 'core/bootstrap/app_bootstrap.dart';
import 'core/bootstrap/bootstrap_status.dart';

Future<void> main() async {
  final bootstrapStatus = await bootstrapApp();

  // Read before the first frame so someone who chose Light never sees a black
  // flash on cold start. bootstrapApp() has already ensured the bindings, which
  // is what makes the platform channel available this early.
  final themeMode = await const ThemeModeStore().read();

  runApp(
    ProviderScope(
      overrides: [
        bootstrapStatusProvider.overrideWithValue(bootstrapStatus),
        initialThemeModeProvider.overrideWithValue(themeMode),
      ],
      child: const FitSocialApp(),
    ),
  );
}
