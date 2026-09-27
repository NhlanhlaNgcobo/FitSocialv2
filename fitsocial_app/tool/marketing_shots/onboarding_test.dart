import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/auth/presentation/login_screen.dart';
import 'package:fitsocial_app/features/auth/presentation/profile_setup_screen.dart';
import 'package:fitsocial_app/features/auth/presentation/splash_screen.dart';
import 'package:fitsocial_app/features/auth/presentation/welcome_screen.dart';

import 'shot_fakes.dart';
import 'shot_harness.dart';

/// Types [text] into the [index]th text field, a character every [every]
/// frames from frame [from].
Future<void> typeInto(WidgetTester t, int index, String text, int i, int from,
    {double every = 2.5}) async {
  if (i < from) return;
  final n = ((i - from) / every).floor() + 1;
  if (n > text.length + 1) return;
  await t.enterText(find.byType(TextField).at(index), text.substring(0, n.clamp(0, text.length)));
}

void main() {
  testWidgets('splash', (tester) async {
    await shootFrames(tester, 'clip_splash', shotApp(const SplashScreen(), overrides: newAccount),
        count: 54, step: tickStep, before: null);
  });

  testWidgets('welcome', (tester) async {
    await shootFrames(tester, 'clip_welcome', shotApp(const WelcomeScreen(), overrides: newAccount),
        count: 75, step: tickStep);
  });

  testWidgets('sign up', (tester) async {
    await shoot(tester, 'signup',
        shotApp(const LoginScreen(isLoginMode: false), overrides: newAccount));
  });

  testWidgets('welcome still', (tester) async {
    await shoot(tester, 'welcome', shotApp(const WelcomeScreen(), overrides: newAccount));
  });

  testWidgets('profile typing', (tester) async {
    await shootFrames(tester, 'clip_profile_typing',
        shotApp(const ProfileSetupScreen(), overrides: newAccount),
        count: 105, step: (t, i, _) async {
      await typeInto(t, 0, 'Sipho Ndlovu', i, 6);
      await typeInto(t, 1, 'sipho.runs', i, 44);
      await t.pump(const Duration(microseconds: 33333));
    });
  });

  testWidgets('profile setup', (tester) async {
    await shoot(tester, 'profile_setup',
        shotApp(const ProfileSetupScreen(), overrides: newAccount));
  });
}
