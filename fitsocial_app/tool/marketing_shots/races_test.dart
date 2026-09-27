import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/races/data/race_repository.dart';
import 'package:fitsocial_app/features/races/data/race_repository_contract.dart';
import 'package:fitsocial_app/features/races/domain/race_models.dart';
import 'package:fitsocial_app/features/races/presentation/race_detail_screen.dart';
import 'package:fitsocial_app/features/races/presentation/races_screen.dart';
import 'package:fitsocial_app/features/races/presentation/saved_races_screen.dart';
import 'package:fitsocial_app/features/races/presentation/submit_race_screen.dart';

import 'shot_fakes.dart';
import 'shot_harness.dart';

final _today = DateTime.now();
DateTime _in(int days, int h, [int m = 0]) =>
    DateTime(_today.year, _today.month, _today.day + days, h, m);

/// A fictional calendar: real places, invented events.
final raceCalendar = <RaceEvent>[
  RaceEvent(
    id: 'durban-half',
    name: 'Durban Beachfront Half',
    startAt: _in(15, 6),
    venue: const RaceVenue(city: 'Durban', province: Province.kwazuluNatal, name: 'uShaka Marine World'),
    distances: const [
      RaceDistance(kilometres: 21.1, label: 'Half Marathon', priceCents: 26000),
      RaceDistance(kilometres: 10, label: '10 km', priceCents: 16000),
      RaceDistance(kilometres: 5, label: '5 km fun run', priceCents: 8000),
    ],
    tags: const {RaceTag.road, RaceTag.comradesQualifier},
    organiser: 'Beachfront Striders',
    description: 'Flat and fast along the promenade from uShaka to Suncoast and back. '
        'A Comrades qualifying course, water every 3 km.',
    entryUrl: 'https://example.com/enter',
  ),
  RaceEvent(
    id: 'umhlanga-night',
    name: 'Umhlanga Lights 10K',
    startAt: _in(9, 18, 30),
    venue: const RaceVenue(city: 'Umhlanga', province: Province.kwazuluNatal),
    distances: const [RaceDistance(kilometres: 10, label: '10 km', priceCents: 18000)],
    tags: const {RaceTag.road, RaceTag.nightRace},
    organiser: 'North Coast Runners',
  ),
  RaceEvent(
    id: 'karkloof-trail',
    name: 'Midlands Forest Trail',
    startAt: _in(22, 6, 30),
    venue: const RaceVenue(city: 'Howick', province: Province.kwazuluNatal),
    distances: const [
      RaceDistance(kilometres: 35, label: '35 km', priceCents: 42000),
      RaceDistance(kilometres: 15, label: '15 km', priceCents: 25000),
    ],
    tags: const {RaceTag.trail},
    organiser: 'Midlands Trail Co.',
  ),
  RaceEvent(
    id: 'peninsula-marathon',
    name: 'Atlantic Seaboard Marathon',
    startAt: _in(36, 5, 30),
    venue: const RaceVenue(city: 'Cape Town', province: Province.westernCape),
    distances: const [
      RaceDistance(kilometres: 42.2, label: 'Marathon', priceCents: 48000),
      RaceDistance(kilometres: 21.1, label: 'Half Marathon', priceCents: 30000),
    ],
    tags: const {RaceTag.road, RaceTag.comradesQualifier, RaceTag.twoOceansQualifier},
    organiser: 'Seaboard Athletics',
  ),
  RaceEvent(
    id: 'soweto-sunrise',
    name: 'Soweto Sunrise 21',
    startAt: _in(29, 6),
    venue: const RaceVenue(city: 'Soweto', province: Province.gauteng),
    distances: const [RaceDistance(kilometres: 21.1, label: 'Half Marathon', priceCents: 22000)],
    tags: const {RaceTag.road},
    organiser: 'Jozi Harriers',
  ),
];

class _Races implements RaceRepository {
  @override
  Future<List<RaceEvent>> fetchEvents({required RaceFilter filter, required DateTime now, int limit = 200}) async =>
      raceCalendar.where(filter.matches).toList()..sort((a, b) => a.startAt.compareTo(b.startAt));
  @override
  Future<RaceEvent?> fetchEvent(String eventId) async =>
      raceCalendar.where((e) => e.id == eventId).firstOrNull;
  @override
  Stream<Set<String>> watchSavedEventIds(String userId) =>
      Stream.value({'durban-half', 'peninsula-marathon'});
  @override
  Stream<List<RaceEvent>> watchSavedEvents(String userId) => Stream.value(
      raceCalendar.where((e) => e.id == 'durban-half' || e.id == 'peninsula-marathon').toList()
        ..sort((a, b) => a.startAt.compareTo(b.startAt)));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<Override> raceOverrides() => [
      ...signedIn(),
      raceRepositoryProvider.overrideWithValue(_Races()),
    ];

void main() {
  testWidgets('races', (tester) async {
    await shoot(tester, 'races',
        shotApp(const RacesScreen(), pushed: true, overrides: raceOverrides()), height: 1500);
  });
  testWidgets('race detail', (tester) async {
    await shoot(tester, 'race_detail',
        shotApp(const RaceDetailScreen(eventId: 'durban-half'), pushed: true, overrides: raceOverrides()),
        height: 1400);
  });
  testWidgets('saved races', (tester) async {
    await shoot(tester, 'races_saved',
        shotApp(const SavedRacesScreen(), pushed: true, overrides: raceOverrides()));
  });
  testWidgets('submit race', (tester) async {
    await shoot(tester, 'race_submit',
        shotApp(const SubmitRaceScreen(), pushed: true, overrides: raceOverrides()));
  });

  testWidgets('races scroll', (tester) async {
    await shootFrames(tester, 'clip_races_scroll',
        shotApp(const RacesScreen(), pushed: true, overrides: raceOverrides()),
        count: 120, step: scrollStep(0, 900));
  });
}
