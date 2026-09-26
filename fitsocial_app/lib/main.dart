import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/theme/app_motion.dart';
import 'app/theme/theme_mode_controller.dart';
import 'core/bootstrap/app_bootstrap.dart';
import 'core/bootstrap/bootstrap_status.dart';
import 'shared/widgets/liquid_glass.dart';

Future<void> main() async {
  final bootstrapStatus = await bootstrapApp();

  // Read before the first frame so someone who chose Light never sees a black
  // flash on cold start. bootstrapApp() has already ensured the bindings, which
  // is what makes the platform channel available this early.
  final themeMode = await const ThemeModeStore().read();

  // Same reasoning: an accessibility choice that took a beat to apply would be
  // the one setting that visibly failed to hold on cold start.
  final accessibilityPrefs = await const AccessibilityPreferencesStore().read();

  // Compiled before the first frame for the same reason as the theme above: the
  // glass would otherwise start frosted and visibly change material a beat
  // later. This never throws -- an unavailable lens resolves to the fallback.
  await LiquidGlassProgram.warmUp();

  runApp(
    ProviderScope(
      overrides: [
        bootstrapStatusProvider.overrideWithValue(bootstrapStatus),
        initialThemeModeProvider.overrideWithValue(themeMode),
        initialAccessibilityPrefsProvider.overrideWithValue(accessibilityPrefs),
      ],
      child: const FitSocialApp(),
    ),
  );
}
