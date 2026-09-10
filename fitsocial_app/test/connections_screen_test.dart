import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fitsocial_app/features/main/application/content_providers.dart';
import 'package:fitsocial_app/features/main/data/content_repository.dart';
import 'package:fitsocial_app/features/main/data/content_repository_contract.dart';
import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/features/main/presentation/connections_screen.dart';
import 'package:fitsocial_app/shared/widgets/profile_stats_bar.dart';

/// One follow graph, in memory.
///
/// Extends the unconfigured repository so only the reads this feature makes
/// need implementing — anything else still throws, and a test that wanders
/// off the path says so rather than passing quietly.
class _FakeContentRepository extends UnconfiguredContentRepository {
  _FakeContentRepository({
    List<UserSearchResult>? followers,
    List<UserSearchResult>? following,
  })  : _followers = followers ?? const [],
        _following = following ?? const [];

  final List<UserSearchResult> _followers;
  final List<UserSearchResult> _following;

  /// Every list read, as "followers:uid" / "following:uid".
  final calls = <String>[];

  @override
  Future<List<ProfileStat>> getProfileStats(String userId) async => [
        ProfileStat(label: 'Followers', value: '${_followers.length}'),
        ProfileStat(label: 'Following', value: '${_following.length}'),
      ];

  @override
  Future<List<UserSearchResult>> fetchFollowList(
    String userId,
    FollowListKind kind,
  ) async {
    calls.add('${kind.collectionName}:$userId');
    return switch (kind) {
      FollowListKind.followers => _followers,
      FollowListKind.following => _following,
    };
  }

  @override
  Stream<bool> watchIsFollowing(String currentUserId, String targetUserId) =>
      Stream.value(_following.any((user) => user.id == targetUserId));
}

UserSearchResult _user(String id, String name, String handle) {
  return UserSearchResult(
    id: id,
    displayName: name,
    handle: handle,
    initials: name.substring(0, 1),
    postsCount: 0,
  );
}

/// The stats bar under a router, so a tap on a column has somewhere to go.
Future<void> pumpStatsBar(
  WidgetTester tester, {
  required ContentRepository repository,
  required String profileUserId,
  String? currentUserId = 'me',
}) async {
  final router = GoRouter(
    initialLocation: '/profile',
    routes: [
      GoRoute(
        path: '/profile',
        builder: (_, __) => Scaffold(
          body: ProfileStatsBar(userId: profileUserId),
        ),
      ),
      GoRoute(
        path: '/connections',
        builder: (context, state) => Scaffold(
          body: Text('CONNECTIONS ${state.uri.queryParameters['tab']}'),
        ),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        contentRepositoryProvider.overrideWithValue(repository),
        currentUserIdProvider.overrideWithValue(currentUserId),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> pumpConnections(
  WidgetTester tester, {
  required ContentRepository repository,
  required FollowListKind initialKind,
  String? currentUserId = 'me',
}) async {
  final router = GoRouter(
    initialLocation: '/connections',
    routes: [
      GoRoute(
        path: '/connections',
        builder: (_, __) => ConnectionsScreen(initialKind: initialKind),
      ),
      GoRoute(
        path: '/user/:userId',
        builder: (context, state) => Scaffold(
          body: Text('PROFILE ${state.pathParameters['userId']}'),
        ),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        contentRepositoryProvider.overrideWithValue(repository),
        currentUserIdProvider.overrideWithValue(currentUserId),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('profile stats bar', () {
    testWidgets('opens your followers from your own profile', (tester) async {
      await pumpStatsBar(
        tester,
        repository: _FakeContentRepository(followers: [
          _user('a', 'Ada', '@ada'),
        ]),
        profileUserId: 'me',
      );

      await tester.tap(find.text('Followers'));
      await tester.pumpAndSettle();

      expect(find.text('CONNECTIONS followers'), findsOneWidget);
    });

    testWidgets('opens who you follow from the other column', (tester) async {
      await pumpStatsBar(
        tester,
        repository: _FakeContentRepository(),
        profileUserId: 'me',
      );

      await tester.tap(find.text('Following'));
      await tester.pumpAndSettle();

      expect(find.text('CONNECTIONS following'), findsOneWidget);
    });

    testWidgets("someone else's counts are not a way in", (tester) async {
      await pumpStatsBar(
        tester,
        repository: _FakeContentRepository(),
        profileUserId: 'them',
      );

      // The numbers still show — they are public. There is simply nothing to
      // tap, so the tap lands on the pane and the page does not move.
      expect(find.text('Followers'), findsOneWidget);
      expect(find.byType(InkWell), findsNothing);

      await tester.tap(find.text('Followers'));
      await tester.pumpAndSettle();

      expect(find.text('CONNECTIONS followers'), findsNothing);
    });

    testWidgets('is inert before the signed-in uid resolves', (tester) async {
      await pumpStatsBar(
        tester,
        repository: _FakeContentRepository(),
        profileUserId: '',
        currentUserId: null,
      );

      // An empty id must not read as "this is me" just because the session
      // has no uid yet.
      expect(find.byType(InkWell), findsNothing);
    });
  });

  group('connections screen', () {
    testWidgets('lists your followers and reads them as you', (tester) async {
      final repository = _FakeContentRepository(
        followers: [_user('a', 'Ada Lovelace', '@ada')],
        following: [_user('b', 'Bear', '@bear')],
      );

      await pumpConnections(
        tester,
        repository: repository,
        initialKind: FollowListKind.followers,
      );

      expect(find.text('Ada Lovelace'), findsOneWidget);
      expect(find.text('@ada'), findsOneWidget);
      // The uid comes from the session, never from the caller.
      expect(repository.calls, contains('followers:me'));
      expect(repository.calls.every((call) => call.endsWith(':me')), isTrue);
    });

    testWidgets('opens on the following tab when asked to', (tester) async {
      await pumpConnections(
        tester,
        repository: _FakeContentRepository(
          followers: [_user('a', 'Ada Lovelace', '@ada')],
          following: [_user('b', 'Bear', '@bear')],
        ),
        initialKind: FollowListKind.following,
      );

      expect(find.text('Bear'), findsOneWidget);
    });

    testWidgets('switches between the two lists', (tester) async {
      await pumpConnections(
        tester,
        repository: _FakeContentRepository(
          followers: [_user('a', 'Ada Lovelace', '@ada')],
          following: [_user('b', 'Bear', '@bear')],
        ),
        initialKind: FollowListKind.followers,
      );

      // The segment carries the count of what is actually listed.
      await tester.tap(find.textContaining('Following'));
      await tester.pumpAndSettle();

      expect(find.text('Bear'), findsOneWidget);
    });

    testWidgets('a row opens that person’s profile', (tester) async {
      await pumpConnections(
        tester,
        repository: _FakeContentRepository(
          followers: [_user('a', 'Ada Lovelace', '@ada')],
        ),
        initialKind: FollowListKind.followers,
      );

      await tester.tap(find.text('Ada Lovelace'));
      await tester.pumpAndSettle();

      expect(find.text('PROFILE a'), findsOneWidget);
    });

    testWidgets('says so when nobody follows you yet', (tester) async {
      await pumpConnections(
        tester,
        repository: _FakeContentRepository(),
        initialKind: FollowListKind.followers,
      );

      expect(find.text('No followers yet'), findsOneWidget);
    });

    testWidgets('reads nothing when signed out', (tester) async {
      final repository = _FakeContentRepository();

      await pumpConnections(
        tester,
        repository: repository,
        initialKind: FollowListKind.followers,
        currentUserId: null,
      );

      expect(repository.calls, isEmpty);
      expect(find.text('No followers yet'), findsOneWidget);
    });
  });
}
