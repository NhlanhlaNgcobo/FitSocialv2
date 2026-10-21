import 'package:flutter/material.dart';

import '../router/page_transitions.dart';
import 'app_colors.dart';
import 'app_palette.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

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
        // What Material paints a selected ChoiceChip and SegmentedButton
        // with. Left alone, the dark scheme's default is the teal #03DAC6,
        // which no other part of the app uses. The brand's soft orange is
        // what the app's own pickers already mark a selection with.
        secondaryContainer: palette.brandSoft,
        onSecondaryContainer: palette.brandText,
        // The same teal sits in tertiary and its container, which some
        // Material widgets fall back to. Nothing here names them; they should
        // still never be teal.
        tertiary: AppColors.orangeBright,
        onTertiary: AppColors.onBrand,
        tertiaryContainer: palette.brandSoft,
        onTertiaryContainer: palette.brandText,
        // Every other slot is named too. The factories fill whatever is left
        // with Material's stock lavender (#BB86FC dark, #6200EE light) and
        // teal (#03DAC6) -- the extended FAB, menus and dialog tints read them
        // -- and with pure white or black outlines. None of those are FitSocial
        // colours, so nothing is left for Material to choose.
        primaryContainer: palette.brandSoft,
        onPrimaryContainer: palette.brandText,
        primaryFixed: palette.brandSoft,
        primaryFixedDim: palette.brandSoftStroke,
        onPrimaryFixed: palette.brandText,
        onPrimaryFixedVariant: palette.brandText,
        secondaryFixed: palette.brandSoft,
        secondaryFixedDim: palette.brandSoftStroke,
        onSecondaryFixed: palette.brandText,
        onSecondaryFixedVariant: palette.brandText,
        tertiaryFixed: palette.brandSoft,
        tertiaryFixedDim: palette.brandSoftStroke,
        onTertiaryFixed: palette.brandText,
        onTertiaryFixedVariant: palette.brandText,
        inversePrimary: AppColors.orangeBright,
        // No tint: surfaces are the palette's greys, not greys washed in the
        // primary colour.
        surfaceTint: Colors.transparent,
        surface: palette.surface,
        surfaceDim: palette.background,
        surfaceBright: palette.surfaceHigh,
        surfaceContainerLowest: palette.background,
        surfaceContainerLow: palette.surface,
        surfaceContainer: palette.surface,
        surfaceContainerHigh: palette.surfaceHigh,
        surfaceContainerHighest: palette.surfaceHigh,
        onSurfaceVariant: palette.muted,
        outline: palette.stroke,
        outlineVariant: palette.stroke,
        inverseSurface: palette.text,
        onInverseSurface: palette.background,
        onPrimary: AppColors.onBrand,
        onSecondary: AppColors.onBrand,
        onSurface: palette.text,
        error: palette.danger,
      ),
      // Solid brand orange, like the app's other floating button. Material's
      // default would be primaryContainer, the soft orange meant for chips.
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: palette.brand,
        foregroundColor: AppColors.onBrand,
      ),
      // Chips are glass like everything else on the page: no fill of their
      // own, a hairline, and the soft orange only when picked. Material's
      // default filled them with surfaceContainer — a near-black slab on the
      // dark theme that read as a hole in the glass.
      chipTheme: ChipThemeData(
        backgroundColor: Colors.transparent,
        selectedColor: palette.brandSoft,
        disabledColor: Colors.transparent,
        side: BorderSide(color: palette.stroke),
        shape: const StadiumBorder(),
        labelStyle: TextStyle(color: palette.text, fontWeight: FontWeight.w600),
        secondaryLabelStyle:
            TextStyle(color: palette.brandText, fontWeight: FontWeight.w700),
        checkmarkColor: palette.brandText,
        iconTheme: IconThemeData(color: palette.muted, size: 18),
        elevation: 0,
        pressElevation: 0,
        surfaceTintColor: Colors.transparent,
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
        titleTextStyle: AppTypography.title.copyWith(color: palette.text),
      ),
      cardTheme: CardThemeData(
        color: palette.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(color: palette.stroke),
        ),
      ),
      dialogTheme: DialogThemeData(
        // Solid, not glass. A dialog route fills the screen, so wrapping one in
        // LiquidGlass tints the whole page instead of the card and leaves the
        // card see-through over whatever it interrupted. One shape for all of
        // them, set here rather than site by site.
        backgroundColor: palette.surface,
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
          borderRadius: BorderRadius.circular(AppRadius.field),
          borderSide: BorderSide(color: palette.stroke),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.field),
          borderSide: BorderSide(color: palette.stroke),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.field),
          borderSide: const BorderSide(color: AppColors.orange),
        ),
      ),
      // No bottomNavigationBarTheme: navigation is FitSocialBottomNav, a
      // floating glass capsule that styles itself and never builds a
      // Material BottomNavigationBar.
    );
  }
}
