import 'package:flutter/material.dart';

import '../router/page_transitions.dart';
import 'app_colors.dart';
import 'app_palette.dart';

abstract final class AppTheme {
  static ThemeData get darkTheme => _build(AppPalette.dark);

  static ThemeData get lightTheme => _build(AppPalette.light);

  /// Both themes come out of here so they cannot drift apart. Anything that
  /// differs between them differs because the [palette] differs — there is no
  /// second copy of this configuration to forget to update.
  static ThemeData _build(AppPalette palette) {
    final base = palette.isDark
        ? ThemeData.dark(useMaterial3: true)
        : ThemeData.light(useMaterial3: true);

    return base.copyWith(
      // Transparent so the app's single LiquidBackdrop shows through every
      // page. The ground is painted once in FitSocialApp; a Scaffold that
      // painted its own would cover it and leave that screen's glass with
      // nothing to bend. Screens that genuinely need an opaque ground — the
      // media viewers — still pin their own.
      scaffoldBackgroundColor: Colors.transparent,
      // Carried on the ThemeData so `context.palette` resolves anywhere under
      // the app, and so Flutter crossfades the colours when the mode changes
      // instead of snapping.
      extensions: [palette],
      // One motion for every screen change in the app. Set here rather than
      // route by route so nothing can be added later that transitions
      // differently by omission.
      //
      // Apple platforms keep their own: the Cupertino transition is what
      // carries the interactive swipe-back gesture, and replacing it would
      // trade a system-level affordance for a visual preference.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: SmoothPageTransitionsBuilder(),
          TargetPlatform.fuchsia: SmoothPageTransitionsBuilder(),
          TargetPlatform.linux: SmoothPageTransitionsBuilder(),
          TargetPlatform.windows: SmoothPageTransitionsBuilder(),
        },
      ),
      // Built from the ColorScheme.dark/light factories rather than the raw
      // constructor so the slots this app never names keep sensible defaults
      // for their brightness.
      colorScheme: (palette.isDark
              ? const ColorScheme.dark()
              : const ColorScheme.light())
          .copyWith(
        primary: AppColors.orange,
        secondary: AppColors.orangeBright,
        surface: palette.surface,
        onPrimary: AppColors.onBrand,
        onSecondary: AppColors.onBrand,
        onSurface: palette.text,
        error: palette.danger,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: palette.text,
        displayColor: palette.text,
      ),
      iconTheme: IconThemeData(color: palette.text),
      dividerColor: palette.stroke,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: palette.text),
        titleTextStyle: TextStyle(
          color: palette.text,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: palette.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: palette.stroke),
        ),
      ),
      dialogTheme: DialogThemeData(
        // Transparent, because every dialog is wrapped in liquid glass and the
        // lens supplies the surface. One shape for all of them, set here rather
        // than site by site — an inconsistency that was invisible while they
        // were opaque slabs and obvious once they are panes.
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: palette.stroke),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: palette.stroke),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: palette.stroke),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.orange),
        ),
      ),
      // No bottomNavigationBarTheme: navigation is FitSocialBottomNav, a
      // floating glass capsule that styles itself and never builds a
      // Material BottomNavigationBar.
    );
  }
}
