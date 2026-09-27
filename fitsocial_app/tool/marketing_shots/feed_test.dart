import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/main/application/content_providers.dart';
import 'package:fitsocial_app/features/main/presentation/home_screen.dart';
import 'package:fitsocial_app/features/main/presentation/post_compose_screen.dart';
import 'package:fitsocial_app/features/main/presentation/tag_people_sheet.dart';
import 'package:fitsocial_app/features/pulse/application/pulse_providers.dart';
import 'package:fitsocial_app/shared/reactions/fit_reaction.dart';
import 'package:fitsocial_app/shared/widgets/reaction_bar.dart';

import 'shot_data.dart';
import 'shot_fakes.dart';
import 'shot_harness.dart';

List<Override> feedOverrides() => [
      ...signedIn(),
      feedPostsProvider
          .overrideWith((ref) => FeedPostsNotifier(const ShotContent(), null)),
      activePulsesProvider.overrideWith((ref) => Stream.value(trayPulses)),
      pulseSeenMarkersProvider
          .overrideWith((ref) => Stream.value(const <String, DateTime>{})),
    ];

Widget feedApp() => shotApp(inShell(const HomeScreen()), overrides: feedOverrides());

Future<void> openComments(WidgetTester t) async {
  mainScroll(t).jumpTo(420);
  await t.pump(const Duration(milliseconds: 200));
  await t.tap(find.text('12').first);
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  clipsMain();

  testWidgets('comments', (tester) async {
    await shoot(tester, 'comments', feedApp(), before: openComments);
  });

  testWidgets('comments reply', (tester) async {
    await shoot(tester, 'comments_reply', feedApp(), before: (t) async {
      await openComments(t);
      await t.tap(find.text('Reply').first);
      await t.pump(const Duration(milliseconds: 400));
    });
  });

  testWidgets('compose', (tester) async {
    await shoot(tester, 'compose',
        shotApp(const PostComposeScreen(), pushed: true, overrides: feedOverrides()),
        before: (t) async {
      await t.enterText(find.byType(TextField).first,
          'Saturday long run crew. 25 km along the beachfront, coffee after.');
      await t.pump(const Duration(milliseconds: 300));
    });
  });
}

/// Centre of each reaction in the open tray, in tray order.
List<Offset> trayCentres(WidgetTester t) => [
      for (final r in FitReaction.values)
        if (find.text(r.emoji).evaluate().isNotEmpty) t.getCenter(find.text(r.emoji).last),
    ];

void clipsMain() {
  testWidgets('react clip', (tester) async {
    TestGesture? finger;
    var centres = <Offset>[];
    await shootFrames(
      tester,
      'clip_react',
      feedApp(),
      before: (t) async {
        mainScroll(t).jumpTo(420);
        await t.pump(const Duration(milliseconds: 300));
      },
      // Ends with the finger resting on the fire; the card after the pick is
      // the react_done still (the pick itself writes through FirebaseAuth).
      count: 72,
      step: (t, i, _) async {
        if (i == 6) {
          finger = await t.startGesture(t.getCenter(find.byType(ReactionTrigger).first));
        }
        if (i == 24) centres = trayCentres(t);
        // Glide across the tray, then settle back on the fire.
        if (i >= 26 && i <= 56 && centres.isNotEmpty) {
          final k = ((i - 26) / 30 * (centres.length - 1));
          final a = centres[k.floor()], b = centres[(k.floor() + 1).clamp(0, centres.length - 1)];
          await finger!.moveTo(Offset.lerp(a, b, k - k.floor())!);
        }
        if (i > 56 && i <= 64 && centres.length > 1) {
          await finger!.moveTo(Offset.lerp(centres.last, centres[1], (i - 56) / 8)!);
        }
        await t.pump(const Duration(microseconds: 33333));
      },
    );
  });

  testWidgets('react done', (tester) async {
    await shoot(
      tester,
      'react_done',
      shotApp(inShell(const HomeScreen()), overrides: [
        ...feedOverrides(),
        postReactionProvider.overrideWith((ref, postId) =>
            Stream.value(postId == 'p-sipho-run' ? FitReaction.fire : null)),
      ]),
      before: (t) async {
        mainScroll(t).jumpTo(420);
        await t.pump(const Duration(milliseconds: 300));
      },
    );
  });

  testWidgets('tag clip', (tester) async {
    await shootFrames(
      tester,
      'clip_tag',
      shotApp(const PostComposeScreen(), pushed: true, overrides: feedOverrides()),
      before: (t) async {
        await t.enterText(find.byType(TextField).first,
            'Saturday long run crew. 25 km along the beachfront, coffee after.');
        await t.pump(const Duration(milliseconds: 300));
        FocusManager.instance.primaryFocus?.unfocus();
      },
      count: 105,
      step: (t, i, _) async {
        if (i == 8) await t.tap(find.byType(TagPeopleRow));
        if (i >= 30 && i < 34) await t.enterText(find.byType(TextField).last, 'a'.substring(0, 1));
        if (i == 52) await t.tap(find.text('Ayanda Zulu').last);
        if (i == 64) await t.tap(find.text('Lerato Mokoena').last);
        if (i == 80) await t.tap(find.text('Done'));
        await t.pump(const Duration(microseconds: 33333));
      },
    );
  });
}
