import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitsocial_app/app/theme/app_colors.dart';
import 'package:fitsocial_app/app/theme/app_palette.dart';
import 'package:fitsocial_app/app/theme/app_theme.dart';
import 'package:fitsocial_app/shared/widgets/fit_social_logo.dart';

Widget host({
  bool animated = false,
  bool showTagline = false,
  AppPalette palette = AppPalette.dark,
}) {
  return MaterialApp(
    // The real app theme, not a bare MaterialApp: the wordmark reads its
    // foreground colour off the palette, so a host without one would be
    // testing the fallback rather than the thing that ships.
    theme: palette.isDark ? AppTheme.darkTheme : AppTheme.lightTheme,
    home: Scaffold(
      body: Center(
        child: FitSocialLogo(
          size: 24,
          animated: animated,
          showTagline: showTagline,
        ),
      ),
    ),
  );
}

String assetOf(WidgetTester tester) {
  final image = tester.widget<Image>(find.byType(Image)).image;
  return (image as AssetImage).assetName;
}

void main() {
  testWidgets('spells the F with the brand mark and sets the rest',
      (tester) async {
    await tester.pumpWidget(host());

    expect(assetOf(tester), kFitSocialMarkAsset);
    expect(find.text('itSocial'), findsOneWidget);
  });

  // The mark's bars lean right, leaving its lower-right corner empty. Type set
  // flush against that box leaves a wedge of dead space at the baseline and the
  // F reads as an icon parked beside a word, so the type has to start before
  // the mark's box ends.
  testWidgets('the type tucks into the mark rather than clearing it',
      (tester) async {
    await tester.pumpWidget(host());

    final mark = tester.getRect(find.byType(Image));
    final text = tester.getRect(find.text('itSocial'));

    expect(text.left, lessThan(mark.right));
  });

  // The name is orange up to "Fit" and white from "Social". The mark supplies
  // the F, so the orange has to carry on through "it" or the split lands in
  // the wrong place and reads as "F" + "itSocial".
  testWidgets('keeps "it" orange and turns white only at "Social"',
      (tester) async {
    await tester.pumpWidget(host());

    final spans = <String, Color?>{};
    (tester.widget<Text>(find.text('itSocial')).textSpan! as TextSpan)
        .visitChildren((span) {
      if (span is TextSpan && span.text != null) {
        spans[span.text!] = span.style?.color;
      }
      return true;
    });

    expect(spans['it'], AppColors.orangeBright);
    expect(spans['Social'], AppPalette.dark.text);
  });

  // The orange half is the brand and never moves; the other half is ordinary
  // foreground and has to follow the theme, or the wordmark goes invisible on
  // the light one.
  testWidgets('takes its foreground half from the active theme',
      (tester) async {
    await tester.pumpWidget(host(palette: AppPalette.light));

    final spans = <String, Color?>{};
    (tester.widget<Text>(find.text('itSocial')).textSpan! as TextSpan)
        .visitChildren((span) {
      if (span is TextSpan && span.text != null) {
        spans[span.text!] = span.style?.color;
      }
      return true;
    });

    expect(spans['it'], AppColors.orangeBright);
    expect(spans['Social'], AppPalette.light.text);
  });

  // The mark *is* the F. Typing one as well would read "FFitSocial", and
  // dropping the mark for a plain "FitSocial" throws the brand away.
  testWidgets('never renders the F as a letter', (tester) async {
    await tester.pumpWidget(host());

    expect(find.text('FitSocial'), findsNothing);
    expect(find.text('Fit'), findsNothing);
  });

  testWidgets('carries the whole word for screen readers', (tester) async {
    await tester.pumpWidget(host());

    expect(
      tester.widget<Image>(find.byType(Image)).semanticLabel,
      'FitSocial',
    );
  });

  testWidgets('shows the tagline only when asked', (tester) async {
    await tester.pumpWidget(host());
    expect(find.text('Train. Fuel. Share. Grow.'), findsNothing);

    await tester.pumpWidget(host(showTagline: true));
    expect(find.text('Train. Fuel. Share. Grow.'), findsOneWidget);
  });

  // A `late final` controller is only built on first use, so an unanimated
  // logo reached dispose() having never touched it — and constructing one
  // against a deactivated element throws. That took out the app bar and the
  // profile-setup screen on the way out of every route.
  testWidgets('an unanimated logo disposes cleanly', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));

    expect(tester.takeException(), isNull);
  });

  testWidgets('the animated logo runs a highlight over the mark',
      (tester) async {
    await tester.pumpWidget(host(animated: true));

    expect(find.byType(ShaderMask), findsOneWidget);

    await tester.pumpWidget(host());
    expect(
      find.byType(ShaderMask),
      findsNothing,
      reason: 'a still logo should not pay for a mask it never animates',
    );
  });
}
