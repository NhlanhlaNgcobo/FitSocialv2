import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitsocial_app/app/theme/app_theme.dart';
import 'package:fitsocial_app/shared/layout/branch_transition.dart';
import 'package:fitsocial_app/shared/widgets/glass_motion.dart';

/// Records every time it is built fresh, so a test can tell a preserved
/// branch from one that was thrown away and rebuilt.
class Branch extends StatefulWidget {
  const Branch({required this.label, required this.mounts, super.key});

  final String label;
  final List<String> mounts;

  @override
  State<Branch> createState() => _BranchState();
}

class _BranchState extends State<Branch> {
  @override
  void initState() {
    super.initState();
    widget.mounts.add(widget.label);
  }

  @override
  Widget build(BuildContext context) {
    return Center(child: Text(widget.label));
  }
}

/// Opacity the branch showing [label] is currently painted at.
double fadeOf(WidgetTester tester, String label) {
  final fades = find.ancestor(
    of: find.text(label, skipOffstage: false),
    matching: find.byType(Opacity),
  );
  return tester.widget<Opacity>(fades.first).opacity;
}

Widget branches(int currentIndex, List<String> mounts) {
  return MaterialApp(
    home: BranchTransition(
      currentIndex: currentIndex,
      children: [
        Branch(label: 'home', mounts: mounts),
        Branch(label: 'profile', mounts: mounts),
      ],
    ),
  );
}

/// A screen with a button that pushes another one, for exercising the route
/// transition end to end.
Widget pushable() {
  return MaterialApp(
    theme: AppTheme.darkTheme,
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(
                  body: Center(child: Text('pushed')),
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  // Both transitions drive an app-wide flag, so a test that left it down would
  // take the next one with it.
  setUp(GlassMotion.resetForTest);
  tearDown(GlassMotion.resetForTest);

  group('BranchTransition', () {
    testWidgets('shows only the current branch once settled', (tester) async {
      await tester.pumpWidget(branches(0, []));
      await tester.pumpAndSettle();

      expect(find.text('home'), findsOneWidget);
      // Parked branches are offstage, which the default finder skips.
      expect(find.text('profile'), findsNothing);
      expect(find.text('profile', skipOffstage: false), findsOneWidget);
    });

    testWidgets('costs the settled branch nothing to be wrapped',
        (tester) async {
      await tester.pumpWidget(branches(0, []));
      await tester.pumpAndSettle();

      // Opacity at 1 and an identity scale both paint straight through, so a
      // tab merely being used carries no compositing layer.
      expect(fadeOf(tester, 'home'), 1);
      expect(
        tester
            .widget<Transform>(
              find
                  .ancestor(
                    of: find.text('home'),
                    matching: find.byType(Transform),
                  )
                  .first,
            )
            .transform
            .isIdentity(),
        isTrue,
      );
    });

    testWidgets('the outgoing branch clears before the incoming one arrives',
        (tester) async {
      final mounts = <String>[];
      await tester.pumpWidget(branches(0, mounts));
      await tester.pumpAndSettle();

      await tester.pumpWidget(branches(1, mounts));
      await tester.pump();

      // Opening frames: the old branch is still fully there, the new one has
      // not started. Overlapping them is what makes a cross-fade look muddy.
      expect(fadeOf(tester, 'home'), closeTo(1, 0.05));
      expect(fadeOf(tester, 'profile'), 0);

      // A third of the way in, the hand-off point: the old one is gone.
      await tester.pump(const Duration(milliseconds: 100));
      expect(fadeOf(tester, 'home'), closeTo(0, 0.05));

      // And the new one is on its way in without having jumped to full.
      await tester.pump(const Duration(milliseconds: 100));
      final arriving = fadeOf(tester, 'profile');
      expect(arriving, greaterThan(0));
      expect(arriving, lessThan(1));

      await tester.pumpAndSettle();
      expect(find.text('profile'), findsOneWidget);
      expect(find.text('home'), findsNothing);
    });

    testWidgets('the arriving branch scales up into place', (tester) async {
      await tester.pumpWidget(branches(0, []));
      await tester.pumpAndSettle();

      await tester.pumpWidget(branches(1, []));
      await tester.pump(const Duration(milliseconds: 200));
      // getRect walks the ancestor transforms, so this is the size the branch
      // is actually painted at rather than the size it was laid out to.
      final midFlight = tester.getRect(
        find.text('profile', skipOffstage: false),
      );

      await tester.pumpAndSettle();
      final settled = tester.getRect(find.text('profile'));

      expect(midFlight.width, lessThan(settled.width));
    });

    testWidgets('holds the glass still for the fade, and not past it',
        (tester) async {
      await tester.pumpWidget(branches(0, []));
      await tester.pumpAndSettle();
      expect(GlassMotion.settled.value, isTrue);

      await tester.pumpWidget(branches(1, []));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      // Mid cross-fade: both branches are in opacity buffers, where a backdrop
      // filter has nothing to read.
      expect(GlassMotion.settled.value, isFalse);

      // The arriving branch is opaque well before it has finished scaling, so
      // the lens comes back while the screen is still moving rather than on a
      // still frame -- which is the only moment the hand-off could be noticed.
      await tester.pump(const Duration(milliseconds: 110));
      expect(tester.hasRunningAnimations, isTrue);
      expect(GlassMotion.settled.value, isTrue);

      await tester.pumpAndSettle();
      expect(GlassMotion.settled.value, isTrue);
    });

    testWidgets('releases the glass even if it is torn down mid-change',
        (tester) async {
      await tester.pumpWidget(branches(0, []));
      await tester.pumpAndSettle();

      await tester.pumpWidget(branches(1, []));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(GlassMotion.settled.value, isFalse);

      // Whatever takes the shell away, it must not leave every pane of glass
      // in the app frozen behind it.
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();

      expect(GlassMotion.settled.value, isTrue);
    });

    testWidgets('switching tabs never rebuilds a branch from scratch',
        (tester) async {
      final mounts = <String>[];
      await tester.pumpWidget(branches(0, mounts));
      await tester.pumpAndSettle();
      expect(mounts, ['home', 'profile']);

      await tester.pumpWidget(branches(1, mounts));
      await tester.pumpAndSettle();
      await tester.pumpWidget(branches(0, mounts));
      await tester.pumpAndSettle();

      expect(
        mounts,
        ['home', 'profile'],
        reason: 'a tab switch must not cost the branch its scroll position, '
            'its form text or its in-flight requests',
      );
    });
  });

  group('SmoothPageTransitionsBuilder', () {
    testWidgets('a pushed screen rises and fades into place', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const Scaffold(
                        body: Center(child: Text('pushed')),
                      ),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final midFlight = tester.getRect(find.text('pushed'));

      await tester.pumpAndSettle();
      final settled = tester.getRect(find.text('pushed'));

      expect(
        midFlight.top,
        greaterThan(settled.top),
        reason: 'it should still be travelling up toward its resting place',
      );
    });

    testWidgets('the transition is not an instant cut', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const Scaffold(
                        body: Center(child: Text('pushed')),
                      ),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));

      final fades = find.ancestor(
        of: find.text('pushed'),
        matching: find.byType(FadeTransition),
      );
      final opacity = tester.widget<FadeTransition>(fades.first).opacity.value;

      expect(opacity, greaterThan(0));
      expect(opacity, lessThan(1));
    });

    testWidgets('builds its curves once, not once for every frame',
        (tester) async {
      await tester.pumpWidget(pushable());

      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));

      Animation<double> fade() {
        return tester
            .widget<FadeTransition>(
              find
                  .ancestor(
                    of: find.text('pushed'),
                    matching: find.byType(FadeTransition),
                  )
                  .first,
            )
            .opacity;
      }

      final first = fade();
      await tester.pump(const Duration(milliseconds: 16));
      final second = fade();

      // ModalRoute rebuilds the transition from a listener on the route's
      // animations, so this runs once a frame. A CurvedAnimation registers a
      // status listener on its parent in its constructor and removes it only
      // in dispose -- built here and dropped, every navigation would leave a
      // few hundred of them attached to the controller for every later frame
      // to notify.
      expect(
        identical(first, second),
        isTrue,
        reason: 'the curve must survive the frame that rebuilt the transition',
      );

      await tester.pumpAndSettle();
    });

    testWidgets('holds the glass still for the fade, and not past it',
        (tester) async {
      await tester.pumpWidget(pushable());
      expect(GlassMotion.settled.value, isTrue);

      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Both screens are in opacity buffers here, and a backdrop filter inside
      // one has no backdrop left to bend.
      expect(GlassMotion.settled.value, isFalse);

      // Opaque, but still travelling the last of its distance.
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.hasRunningAnimations, isTrue);
      expect(GlassMotion.settled.value, isTrue);

      await tester.pumpAndSettle();
      expect(GlassMotion.settled.value, isTrue);
    });

    testWidgets('gives the glass back when a route is popped away',
        (tester) async {
      await tester.pumpWidget(pushable());
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(GlassMotion.settled.value, isFalse);

      await tester.pumpAndSettle();
      expect(GlassMotion.settled.value, isTrue);
    });
  });
}
