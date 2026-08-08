import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/app/theme/app_palette.dart';
import 'package:fitsocial_app/shared/identity/profile_identity.dart';
import 'package:fitsocial_app/shared/widgets/avatar.dart';

void main() {
  group('avatarInitials', () {
    test('takes the first and last name', () {
      expect(avatarInitials('Bear Mdlalose'), 'BM');
      expect(avatarInitials('  neo   mokoena '), 'NM');
      expect(avatarInitials('Ana Sofia de Souza'), 'AS');
    });

    test('takes one letter from a single name', () {
      expect(avatarInitials('Thandi'), 'T');
    });

    test('is empty for an account that has no name yet', () {
      expect(avatarInitials(null), '');
      expect(avatarInitials('   '), '');
    });

    test('is empty for the stand-ins the app writes in place of a name', () {
      // What a brand-new install carries until the user sets a name. Turning
      // these into "FM"/"FU" put a stranger's monogram on every new profile.
      expect(avatarInitials('FitSocial Member'), '');
      expect(avatarInitials('FitSocial User'), '');
      expect(avatarInitials('fitsocial member'), '');
    });

    test('is empty for an email that leaked into the name field', () {
      expect(avatarInitials('bear@example.com'), '');
    });

    test('skips punctuation to reach the first real letter', () {
      expect(avatarInitials('@bear'), 'B');
      expect(avatarInitials('...'), '');
    });

    test('an emoji is decoration, not an initial', () {
      expect(avatarInitials('😀 Runner'), 'R');
    });

    test('keeps a whole code point rather than half a surrogate pair', () {
      expect(avatarInitials('𝐁ear Mdlalose'), '𝐁M');
    });
  });

  group('Avatar', () {
    Widget host(Widget child) {
      return MaterialApp(
        theme: ThemeData(extensions: const [AppPalette.dark]),
        home: Scaffold(body: Center(child: child)),
      );
    }

    testWidgets('shows the monogram when the user has a name but no photo',
        (tester) async {
      await tester.pumpWidget(host(Avatar(initials: avatarInitials('Bear M'))));

      expect(find.text('BM'), findsOneWidget);
      expect(find.byIcon(Icons.person_rounded), findsNothing);
    });

    testWidgets('shows the neutral glyph — never a stock portrait — for a '
        'fresh account with no name and no photo', (tester) async {
      await tester.pumpWidget(
        host(Avatar(initials: avatarInitials('FitSocial Member'))),
      );

      expect(find.byIcon(Icons.person_rounded), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(find.byType(Text), findsNothing);
    });
  });
}
