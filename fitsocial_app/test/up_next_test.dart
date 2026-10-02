import 'package:fitsocial_app/core/config/feature_flags.dart';
import 'package:fitsocial_app/features/main/application/content_providers.dart';
import 'package:fitsocial_app/features/up_next/data/up_next_repository.dart';
import 'package:fitsocial_app/features/up_next/domain/up_next.dart';
import 'package:fitsocial_app/features/up_next/presentation/up_next_carousel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeUpNextRepository implements UpNextRepository {
  _FakeUpNextRepository(this.suggestions);

  final List<UpNextSuggestion> suggestions;
  final dismissed = <String>[];
  int refreshes = 0;

  @override
  Stream<List<UpNextSuggestion>> watchDay(String userId, String dayKey) =>
      Stream.value(suggestions);

  @override
  Future<void> refresh() async => refreshes += 1;

  @override
  Future<void> dismiss(String userId, String dayKey, String id) async =>
      dismissed.add(id);
}

const _streak = UpNextSuggestion(
  id: 'streak',
  kind: 'streak',
  title: 'Keep your 4-day streak going',
  reason: 'Any session today keeps it alive.',
  route: '/create',
);

const _goal = UpNextSuggestion(
  id: 'goal:g1',
  kind: 'goal',
  title: '2,300 steps to your weekly goal',
  reason: 'A 25-minute walk gets you there.',
  route: '/goals',
);

Widget _host(_FakeUpNextRepository repository, {bool enabled = true}) {
  final flags = FeatureFlags.defaults.withFlag(FeatureFlag.upNext, enabled);
  return ProviderScope(
    overrides: [
      currentUserIdProvider.overrideWithValue('me'),
      upNextRepositoryProvider.overrideWithValue(repository),
      featureFlagsProvider.overrideWith((ref) => Stream.value(flags)),
    ],
    child: const MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: UpNextCarousel())),
    ),
  );
}

void main() {
  group('reading the day', () {
    test('dismissed suggestions are left out, and three at most', () {
      final visible = visibleSuggestions({
        'dismissed': ['streak'],
        'suggestions': [
          for (final id in ['streak', 'a', 'b', 'c', 'd'])
            {
              'id': id,
              'kind': 'goal',
              'title': 'T $id',
              'reason': 'R',
              'route': '/goals'
            },
        ],
      });
      expect(visible.map((s) => s.id), ['a', 'b', 'c']);
    });

    test('malformed suggestions are skipped', () {
      final visible = visibleSuggestions({
        'suggestions': [
          {'id': 'x', 'title': 'No route'},
          {'id': 'y', 'title': 'Not a path', 'route': 'https://example.com'},
          'nonsense',
          {'id': 'z', 'title': 'Fine', 'route': '/goals'},
        ],
      });
      expect(visible.map((s) => s.id), ['z']);
    });

    test('no document, no suggestions', () {
      expect(visibleSuggestions(null), isEmpty);
    });
  });

  group('carousel', () {
    testWidgets('shows the suggestions with their reasons', (tester) async {
      await tester.pumpWidget(_host(_FakeUpNextRepository([_streak, _goal])));
      await tester.pumpAndSettle();
      expect(find.text('UP NEXT'), findsOneWidget);
      expect(find.text('Keep your 4-day streak going'), findsOneWidget);
      expect(find.text('Any session today keeps it alive.'), findsOneWidget);
    });

    testWidgets('a dismissal goes to the server', (tester) async {
      final repository = _FakeUpNextRepository([_goal]);
      await tester.pumpWidget(_host(repository));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Not today'));
      await tester.pumpAndSettle();
      expect(repository.dismissed, ['goal:g1']);
    });

    testWidgets('draws nothing while switched off, and does not ask',
        (tester) async {
      final repository = _FakeUpNextRepository([_streak]);
      await tester.pumpWidget(_host(repository, enabled: false));
      await tester.pumpAndSettle();
      expect(find.text('UP NEXT'), findsNothing);
      expect(repository.refreshes, 0);
    });

    testWidgets('draws nothing when there is nothing to suggest',
        (tester) async {
      await tester.pumpWidget(_host(_FakeUpNextRepository(const [])));
      await tester.pumpAndSettle();
      expect(find.text('UP NEXT'), findsNothing);
    });
  });
}
