import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/app/theme/app_theme.dart';
import 'package:fitsocial_app/features/main/application/content_providers.dart';
import 'package:fitsocial_app/features/races/application/race_providers.dart';
import 'package:fitsocial_app/features/races/data/race_repository.dart';
import 'package:fitsocial_app/features/races/data/race_repository_contract.dart';
import 'package:fitsocial_app/features/races/domain/race_models.dart';
import 'package:fitsocial_app/features/races/presentation/race_artwork.dart';
import 'package:fitsocial_app/features/races/presentation/race_detail_screen.dart';
import 'package:fitsocial_app/features/races/presentation/race_widgets.dart';
import 'package:fitsocial_app/features/races/presentation/races_screen.dart';

/// Pinned so a timeframe filter and a countdown never depend on the day the
/// suite runs.
final _now = DateTime(2026, 8, 22, 9);

RaceEvent _event({
  required String id,
  required String name,
  required DateTime startAt,
  Province province = Province.gauteng,
  String city = 'Midrand',
  List<RaceDistance> distances = const [
    RaceDistance(kilometres: 10, label: '10 km', priceCents: 9000),
    RaceDistance(kilometres: 21.1, label: 'Half Marathon', priceCents: 15000),
  ],
  Set<RaceTag> tags = const {RaceTag.road},
  String? entryUrl = 'https://example.test/enter',
  RaceStatus status = RaceStatus.scheduled,
}) {
  return RaceEvent(
    id: id,
    name: name,
    startAt: startAt,
    venue: RaceVenue(city: city, province: province),
    distances: distances,
    tags: tags,
    entryUrl: entryUrl,
    status: status,
    organiser: 'Midrand Striders',
  );
}

/// The calendar, in memory.
///
/// Applies the filter the same way the Firestore repository does — the timeframe
/// window, then [RaceFilter.matches] — so a test that asserts on what the screen
/// shows is asserting on the real filtering rule rather than on a fake that
/// happens to agree with it.
class _FakeRaceRepository implements RaceRepository {
  _FakeRaceRepository(this.events);

  List<RaceEvent> events;
  final Set<String> saved = <String>{};
  final List<RaceSubmission> submissions = <RaceSubmission>[];
  final List<({String eventId, String? platform})> taps = [];

  /// Makes tap recording fail, to prove it cannot break the entry flow.
  bool tapsThrow = false;
  final StreamController<Set<String>> _savedIds =
      StreamController<Set<String>>.broadcast();

  int fetchCount = 0;

  @override
  Future<List<RaceEvent>> fetchEvents({
    required RaceFilter filter,
    required DateTime now,
    int limit = 200,
  }) async {
    fetchCount++;
    final until = filter.timeframe.endFrom(now);
    return events
        .where((event) => !event.isPast(now))
        .where((event) => until == null || event.startAt.isBefore(until))
        .where(filter.matches)
        .toList(growable: false)
      ..sort((a, b) => a.startAt.compareTo(b.startAt));
  }

  @override
  Future<RaceEvent?> fetchEvent(String eventId) async {
    for (final event in events) {
      if (event.id == eventId) return event;
    }
    return null;
  }

  @override
  Stream<Set<String>> watchSavedEventIds(String userId) =>
      _savedIds.stream.startWith(saved.toSet());

  @override
  Stream<List<RaceEvent>> watchSavedEvents(String userId) => Stream.value(
        events.where((event) => saved.contains(event.id)).toList(),
      );

  @override
  Future<void> setSaved({
    required String userId,
    required String eventId,
    required bool saved,
  }) async {
    if (saved) {
      this.saved.add(eventId);
    } else {
      this.saved.remove(eventId);
    }
    _savedIds.add(this.saved.toSet());
  }

  @override
  Future<void> recordEntryTap({
    required String userId,
    required String eventId,
    String? platform,
  }) async {
    if (tapsThrow) throw StateError('offline');
    taps.add((eventId: eventId, platform: platform));
  }

  @override
  Future<void> submitRace({
    required String userId,
    required RaceSubmission submission,
  }) async {
    submissions.add(submission);
  }
}

extension _StartWith<T> on Stream<T> {
  /// Emits [first] before whatever the controller sends later.
  ///
  /// The screens read the saved set on build, so a bare broadcast stream would
  /// leave them in a loading state until the first toggle.
  Stream<T> startWith(T first) async* {
    yield first;
    yield* this;
  }
}

/// Gives the test a tall surface.
///
/// The default 600x800 shows about two race cards once the cover band is on
/// them, so assertions about the third would fail on layout rather than on
/// behaviour. Widget tests only find what is actually rendered, and a lazy
/// sliver list does not build what is off screen.
void _tallSurface(WidgetTester tester, {double height = 2400}) {
  tester.view.physicalSize = Size(600, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Widget _app({
  required Widget child,
  required _FakeRaceRepository repository,
  String? userId = 'me',
}) {
  return ProviderScope(
    overrides: [
      raceRepositoryProvider.overrideWithValue(repository),
      raceClockProvider.overrideWithValue(_now),
      currentUserIdProvider.overrideWithValue(userId),
    ],
    child: MaterialApp(
      theme: AppTheme.darkTheme,
      home: child,
    ),
  );
}

void main() {
  final thisWeek = _event(
    id: 'weekend-10k',
    name: 'Weekend Warrior 10',
    startAt: DateTime(2026, 8, 23, 7),
  );
  final nextMonth = _event(
    id: 'gun-run',
    name: 'Peninsula Half',
    startAt: DateTime(2026, 9, 12, 6, 30),
    province: Province.westernCape,
    city: 'Cape Town',
    tags: const {RaceTag.road, RaceTag.comradesQualifier},
  );
  final trailUltra = _event(
    id: 'berg-ultra',
    name: 'Berg Skyline Ultra',
    startAt: DateTime(2026, 10, 4, 5),
    province: Province.kwazuluNatal,
    city: 'Underberg',
    distances: const [
      RaceDistance(kilometres: 65, label: '65 km', priceCents: 120000),
    ],
    tags: const {RaceTag.trail},
  );

  group('RacesScreen', () {
    testWidgets('lists upcoming races under month headers', (tester) async {
      final repository = _FakeRaceRepository([thisWeek, nextMonth, trailUltra]);
      _tallSurface(tester);
      await tester.pumpWidget(
        _app(child: const RacesScreen(), repository: repository),
      );
      await tester.pumpAndSettle();

      expect(find.text('Weekend Warrior 10'), findsOneWidget);
      expect(find.text('Peninsula Half'), findsOneWidget);
      expect(find.text('AUGUST 2026'), findsOneWidget);
      expect(find.text('SEPTEMBER 2026'), findsOneWidget);
    });

    testWidgets('shows the count and where it is looking', (tester) async {
      final repository = _FakeRaceRepository([thisWeek, nextMonth, trailUltra]);
      _tallSurface(tester);
      await tester.pumpWidget(
        _app(child: const RacesScreen(), repository: repository),
      );
      await tester.pumpAndSettle();

      expect(find.text('3 races · Southern Africa'), findsOneWidget);
    });

    testWidgets('the timeframe chip narrows the list', (tester) async {
      final repository = _FakeRaceRepository([thisWeek, nextMonth, trailUltra]);
      _tallSurface(tester);
      await tester.pumpWidget(
        _app(child: const RacesScreen(), repository: repository),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('This week'));
      await tester.pumpAndSettle();

      expect(find.text('Weekend Warrior 10'), findsOneWidget);
      expect(find.text('Peninsula Half'), findsNothing);
      expect(find.text('1 race · Southern Africa'), findsOneWidget);
    });

    testWidgets('the qualifier chip keeps only qualifying races',
        (tester) async {
      final repository = _FakeRaceRepository([thisWeek, nextMonth, trailUltra]);
      _tallSurface(tester);
      await tester.pumpWidget(
        _app(child: const RacesScreen(), repository: repository),
      );
      await tester.pumpAndSettle();

      // Two chips carry this label — the filter pill and the badge on the
      // qualifying row — so the tap targets the pill in the scrolling filter row.
      await tester.tap(find.text('Comrades qualifier').first);
      await tester.pumpAndSettle();

      expect(find.text('Peninsula Half'), findsOneWidget);
      expect(find.text('Weekend Warrior 10'), findsNothing);
      expect(find.text('Berg Skyline Ultra'), findsNothing);
    });

    testWidgets('searching filters by name', (tester) async {
      final repository = _FakeRaceRepository([thisWeek, nextMonth, trailUltra]);
      _tallSurface(tester);
      await tester.pumpWidget(
        _app(child: const RacesScreen(), repository: repository),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'berg');
      await tester.pumpAndSettle();

      expect(find.text('Berg Skyline Ultra'), findsOneWidget);
      expect(find.text('Peninsula Half'), findsNothing);
    });

    testWidgets('an empty result offers to clear the filters', (tester) async {
      final repository = _FakeRaceRepository([thisWeek]);
      _tallSurface(tester);
      await tester.pumpWidget(
        _app(child: const RacesScreen(), repository: repository),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'nothing matches');
      await tester.pumpAndSettle();

      expect(find.text('No races match those filters'), findsOneWidget);

      await tester.tap(find.text('Clear filters'));
      await tester.pumpAndSettle();

      expect(find.text('Weekend Warrior 10'), findsOneWidget);
    });

    testWidgets('an empty calendar invites a submission', (tester) async {
      final repository = _FakeRaceRepository([]);
      _tallSurface(tester);
      await tester.pumpWidget(
        _app(child: const RacesScreen(), repository: repository),
      );
      await tester.pumpAndSettle();

      expect(find.text('No races listed yet'), findsOneWidget);
      expect(find.text('Submit a race'), findsWidgets);
    });

    testWidgets('the bookmark saves a race', (tester) async {
      final repository = _FakeRaceRepository([thisWeek]);
      _tallSurface(tester);
      await tester.pumpWidget(
        _app(child: const RacesScreen(), repository: repository),
      );
      await tester.pumpAndSettle();

      // Scoped to the card: the app bar carries the same icon for "my races",
      // and Scaffold builds the bar after the body, so an unscoped .last finds
      // the wrong one.
      await tester.tap(
        find.descendant(
          of: find.byType(RaceCard),
          matching: find.byIcon(Icons.bookmark_border_rounded),
        ),
      );
      await tester.pumpAndSettle();

      expect(repository.saved, {'weekend-10k'});
      expect(find.text('Saved to my races'), findsOneWidget);
    });

    testWidgets('a signed-out visitor is offered no save button',
        (tester) async {
      final repository = _FakeRaceRepository([thisWeek]);
      _tallSurface(tester);
      await tester.pumpWidget(
        _app(
          child: const RacesScreen(),
          repository: repository,
          userId: null,
        ),
      );
      await tester.pumpAndSettle();

      // The list still renders. The router never lets a signed-out session
      // reach this screen, so this is about the widget not depending on a user
      // rather than about a state a real visitor is in.
      expect(find.text('Weekend Warrior 10'), findsOneWidget);
      // The row has no save control. The app bar's "my races" action keeps its
      // own copy of the icon, so this is scoped to the card.
      expect(
        find.descendant(
          of: find.byType(RaceCard),
          matching: find.byIcon(Icons.bookmark_border_rounded),
        ),
        findsNothing,
      );
    });

    testWidgets('shows the price as a "from" when distances differ',
        (tester) async {
      final repository = _FakeRaceRepository([thisWeek]);
      _tallSurface(tester);
      await tester.pumpWidget(
        _app(child: const RacesScreen(), repository: repository),
      );
      await tester.pumpAndSettle();

      expect(find.text('from R90'), findsOneWidget);
    });
  });

  group('Entry tap attribution', _tapTests);

  group('Cover art', _coverTests);

  group('RaceDetailScreen', () {
    testWidgets('shows the distances with their fees', (tester) async {
      final repository = _FakeRaceRepository([nextMonth]);
      _tallSurface(tester);
      await tester.pumpWidget(
        _app(
          child: const RaceDetailScreen(eventId: 'gun-run'),
          repository: repository,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Peninsula Half'), findsOneWidget);
      expect(find.text('Half Marathon'), findsOneWidget);
      expect(find.text('R150'), findsOneWidget);
      expect(find.text('R90'), findsOneWidget);
      expect(find.text('ENTER THIS RACE'), findsOneWidget);
    });

    testWidgets('a distance inherits the first start when it has no time of '
        'its own', (tester) async {
      final repository = _FakeRaceRepository([nextMonth]);
      _tallSurface(tester);
      await tester.pumpWidget(
        _app(
          child: const RaceDetailScreen(eventId: 'gun-run'),
          repository: repository,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('21.1 km · starts 06:30'), findsOneWidget);
    });

    testWidgets('an unpublished fee reads as unknown, not free',
        (tester) async {
      final repository = _FakeRaceRepository([
        _event(
          id: 'league',
          name: 'Club League Race',
          startAt: DateTime(2026, 9, 5, 6),
          distances: const [RaceDistance(kilometres: 8, label: '8 km')],
        ),
      ]);
      _tallSurface(tester);
      await tester.pumpWidget(
        _app(
          child: const RaceDetailScreen(eventId: 'league'),
          repository: repository,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('—'), findsOneWidget);
      expect(find.text('Free'), findsNothing);
    });

    testWidgets('a race with no entry link says entries are on the day',
        (tester) async {
      final repository = _FakeRaceRepository([
        _event(
          id: 'league',
          name: 'Club League Race',
          startAt: DateTime(2026, 9, 5, 6),
          entryUrl: null,
        ),
      ]);
      _tallSurface(tester);
      await tester.pumpWidget(
        _app(
          child: const RaceDetailScreen(eventId: 'league'),
          repository: repository,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('ENTRIES ON THE DAY'), findsOneWidget);
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('a cancelled race explains itself and refuses entry',
        (tester) async {
      final repository = _FakeRaceRepository([
        _event(
          id: 'off',
          name: 'Washed Out Half',
          startAt: DateTime(2026, 9, 5, 6),
          status: RaceStatus.cancelled,
        ),
      ]);
      _tallSurface(tester);
      await tester.pumpWidget(
        _app(
          child: const RaceDetailScreen(eventId: 'off'),
          repository: repository,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('This race has been cancelled by the organiser.'),
        findsOneWidget,
      );
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('a stale link lands on "not found" rather than a spinner',
        (tester) async {
      final repository = _FakeRaceRepository([nextMonth]);
      _tallSurface(tester);
      await tester.pumpWidget(
        _app(
          child: const RaceDetailScreen(eventId: 'deleted-long-ago'),
          repository: repository,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Race not found'), findsOneWidget);
    });

    testWidgets('no "last checked" line when nobody has verified the listing',
        (tester) async {
      final repository = _FakeRaceRepository([nextMonth]);
      _tallSurface(tester);
      await tester.pumpWidget(
        _app(
          child: const RaceDetailScreen(eventId: 'gun-run'),
          repository: repository,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('From an official fixture list'), findsOneWidget);
      expect(find.textContaining('last checked'), findsNothing);
    });
  });
}

// ── Cover art ───────────────────────────────────────────────────────────────
//
// The generated cover is what most of this calendar will actually show, so it
// gets the same scrutiny as the data: it has to appear for every race, stay
// identical across rebuilds, and differ between races.
void _coverTests() {
  final noPhoto = _event(
    id: 'no-photo',
    name: 'Bonteheuwel 10km',
    startAt: DateTime(2026, 9, 5, 6),
  );

  testWidgets('every race gets a cover, with or without a photograph',
      (tester) async {
    _tallSurface(tester);
    final repository = _FakeRaceRepository([noPhoto]);
    await tester.pumpWidget(
      _app(child: const RacesScreen(), repository: repository),
    );
    await tester.pumpAndSettle();

    expect(find.byType(RaceCover), findsOneWidget);
    // No imageUrl, so it must resolve to generated art rather than a network
    // image that would throw in a test harness.
    expect(find.byType(RaceArtwork), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('the same race paints the same art twice running',
      (tester) async {
    // Guards the FNV-1a seed. Dart makes no promise that String.hashCode is
    // stable, and art that changed colour between launches would look like a
    // bug to the user.
    Future<_RaceArtworkProbe> paint() async {
      final repository = _FakeRaceRepository([noPhoto]);
      _tallSurface(tester);
      await tester.pumpWidget(
        _app(child: const RacesScreen(), repository: repository),
      );
      await tester.pumpAndSettle();
      final art = tester.widget<RaceArtwork>(find.byType(RaceArtwork));
      return _RaceArtworkProbe(art.event.name, art.event.venue.city);
    }

    final first = await paint();
    final second = await paint();
    expect(first.seed, second.seed);
  });

  testWidgets('different races get different art', (tester) async {
    final other = _event(
      id: 'other',
      name: 'Chapman\u2019s Peak Half Marathon',
      startAt: DateTime(2026, 9, 6, 6),
      city: 'Cape Town',
    );
    _tallSurface(tester);
    final repository = _FakeRaceRepository([noPhoto, other]);
    await tester.pumpWidget(
      _app(child: const RacesScreen(), repository: repository),
    );
    await tester.pumpAndSettle();

    final arts = tester.widgetList<RaceArtwork>(find.byType(RaceArtwork));
    expect(arts.length, 2);
    final seeds = arts
        .map((a) => _RaceArtworkProbe(a.event.name, a.event.venue.city).seed)
        .toSet();
    expect(seeds.length, 2, reason: 'two races must not share one cover');
  });
}

/// Recomputes the painter's seed from the same inputs, so the test asserts on
/// the derivation rather than on pixels.
class _RaceArtworkProbe {
  _RaceArtworkProbe(this.name, this.city);

  final String name;
  final String city;

  int get seed {
    const offset = 0x811c9dc5;
    const prime = 0x01000193;
    var hash = offset;
    for (final unit in '$name|$city'.codeUnits) {
      hash = ((hash ^ unit) * prime) & 0xffffffff;
    }
    return hash;
  }
}


// ── Entry tap attribution ───────────────────────────────────────────────────
//
// Phase 1 of entry-link attribution. The tap is recorded for measurement the
// user never asked for, alongside the one thing they did ask for — opening the
// entry page — so the tests that matter most are the ones proving it cannot get
// in the way.
void _tapTests() {
  final withEntry = _event(
    id: 'gun-run',
    name: 'Peninsula Half',
    startAt: DateTime(2026, 9, 12, 6, 30),
    entryUrl: 'https://example.test/enter',
  );

  Future<void> pumpDetail(
    WidgetTester tester,
    _FakeRaceRepository repository,
  ) async {
    _tallSurface(tester);
    await tester.pumpWidget(
      _app(
        child: const RaceDetailScreen(eventId: 'gun-run'),
        repository: repository,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('tapping Enter records the tap with its platform',
      (tester) async {
    final repository = _FakeRaceRepository([
      _event(
        id: 'gun-run',
        name: 'Peninsula Half',
        startAt: DateTime(2026, 9, 12, 6, 30),
      ),
    ]);
    // The platform is what a partner report would be reconciled against, so it
    // has to travel with the tap rather than be looked up later.
    repository.events = [
      RaceEvent(
        id: 'gun-run',
        name: 'Peninsula Half',
        startAt: DateTime(2026, 9, 12, 6, 30),
        venue: const RaceVenue(city: 'Cape Town', province: Province.westernCape),
        distances: const [RaceDistance(kilometres: 10, label: '10 km')],
        entryUrl: 'https://example.test/enter',
        entryPlatform: 'entryninja',
      ),
    ];
    await pumpDetail(tester, repository);

    await tester.tap(find.text('ENTER THIS RACE'));
    await tester.pumpAndSettle();

    expect(repository.taps, hasLength(1));
    expect(repository.taps.single.eventId, 'gun-run');
    expect(repository.taps.single.platform, 'entryninja');
  });

  testWidgets('a failed recording does not break the entry flow',
      (tester) async {
    // The point of the whole design: measurement must never cost somebody their
    // race entry. If this test fails, the tap is being awaited or its error is
    // escaping.
    final repository = _FakeRaceRepository([withEntry])..tapsThrow = true;
    await pumpDetail(tester, repository);

    await tester.tap(find.text('ENTER THIS RACE'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(repository.taps, isEmpty);
  });

  testWidgets('a race with no entry link records nothing', (tester) async {
    final repository = _FakeRaceRepository([
      _event(
        id: 'gun-run',
        name: 'Peninsula Half',
        startAt: DateTime(2026, 9, 12, 6, 30),
        entryUrl: null,
      ),
    ]);
    await pumpDetail(tester, repository);

    // The button is disabled, so there is nothing to tap through to and nothing
    // to attribute.
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
    expect(repository.taps, isEmpty);
  });

  testWidgets('a signed-out user records nothing', (tester) async {
    final repository = _FakeRaceRepository([withEntry]);
    _tallSurface(tester);
    await tester.pumpWidget(
      _app(
        child: const RaceDetailScreen(eventId: 'gun-run'),
        repository: repository,
        userId: null,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('ENTER THIS RACE'));
    await tester.pumpAndSettle();

    // There is no user to attribute it to, and inventing one would corrupt the
    // distinct-tapper count.
    expect(repository.taps, isEmpty);
  });
}
