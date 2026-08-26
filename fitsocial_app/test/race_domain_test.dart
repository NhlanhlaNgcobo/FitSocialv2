import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/races/data/race_query_plan.dart';
import 'package:fitsocial_app/features/races/domain/race_formatting.dart';
import 'package:fitsocial_app/features/races/domain/race_models.dart';

/// A Saturday in Johannesburg, pinned so a timeframe never depends on the day
/// the suite happens to run.
final _now = DateTime(2026, 8, 22, 9);

RaceEvent _event({
  String id = 'race-1',
  String name = 'Kyalami Country Classic',
  DateTime? startAt,
  DateTime? endAt,
  Province province = Province.gauteng,
  String city = 'Midrand',
  List<RaceDistance> distances = const [
    RaceDistance(kilometres: 10, label: '10 km', priceCents: 9000),
    RaceDistance(kilometres: 21.1, label: 'Half Marathon', priceCents: 15000),
  ],
  Set<RaceTag> tags = const {RaceTag.road},
  String? organiser,
}) {
  return RaceEvent(
    id: id,
    name: name,
    startAt: startAt ?? DateTime(2026, 9, 12, 6, 30),
    endAt: endAt,
    venue: RaceVenue(city: city, province: province),
    distances: distances,
    tags: tags,
    organiser: organiser,
  );
}

void main() {
  group('DistanceBucket.forKilometres', () {
    test('maps the standard road distances to their own bands', () {
      expect(DistanceBucket.forKilometres(5), DistanceBucket.fiveK);
      expect(DistanceBucket.forKilometres(10), DistanceBucket.tenK);
      expect(DistanceBucket.forKilometres(15), DistanceBucket.fifteenK);
      expect(DistanceBucket.forKilometres(21.1), DistanceBucket.half);
      expect(DistanceBucket.forKilometres(30), DistanceBucket.thirtyK);
      expect(DistanceBucket.forKilometres(42.2), DistanceBucket.marathon);
    });

    test('is generous with routes that are not measured to the metre', () {
      // The point of the wide bands: these are all real races that advertise
      // themselves as a 10 km or a half, and a filter that hid them because the
      // route was measured honestly would be the filter's fault.
      expect(DistanceBucket.forKilometres(9.8), DistanceBucket.tenK);
      expect(DistanceBucket.forKilometres(11.5), DistanceBucket.tenK);
      expect(DistanceBucket.forKilometres(21.4), DistanceBucket.half);
      expect(DistanceBucket.forKilometres(20), DistanceBucket.half);
    });

    test('anything past a marathon is an ultra', () {
      expect(DistanceBucket.forKilometres(50), DistanceBucket.ultra);
      expect(DistanceBucket.forKilometres(56), DistanceBucket.ultra);
      expect(DistanceBucket.forKilometres(90), DistanceBucket.ultra);
    });

    test('a short fun run is not a 5 km', () {
      expect(DistanceBucket.forKilometres(3), DistanceBucket.fun);
      expect(DistanceBucket.forKilometres(2), DistanceBucket.fun);
    });
  });

  group('RaceEvent', () {
    test('reports the cheapest published fee, marked as a "from"', () {
      expect(_event().priceFromCents, 9000);
      expect(_event().priceFromLabel, 'from R90');
    });

    test('a single-distance race quotes its fee flat, not as a "from"', () {
      final event = _event(
        distances: const [
          RaceDistance(kilometres: 42.2, label: 'Marathon', priceCents: 32000),
        ],
      );
      expect(event.priceFromLabel, 'R320');
    });

    test('an unpublished fee is not free', () {
      // The distinction that matters at a start line: no announced fee reads as
      // unknown, and only an explicit zero reads as free.
      final unknown = _event(
        distances: const [RaceDistance(kilometres: 10, label: '10 km')],
      );
      expect(unknown.priceFromCents, isNull);
      expect(unknown.priceFromLabel, isNull);

      final free = _event(
        distances: const [
          RaceDistance(kilometres: 5, label: 'Fun run', priceCents: 0),
        ],
      );
      expect(free.priceFromLabel, 'Free');
    });

    test('collects the distance bands it covers', () {
      expect(
        _event().buckets,
        {DistanceBucket.tenK, DistanceBucket.half},
      );
    });

    test('a multi-day event stays upcoming through its last day', () {
      final stageRace = _event(
        startAt: DateTime(2026, 8, 21, 7),
        endAt: DateTime(2026, 8, 23, 23, 59),
      );
      // Saturday, mid-race. The start is behind us and the finish is not.
      expect(stageRace.isPast(_now), isFalse);
      expect(
        stageRace.isPast(DateTime(2026, 8, 24, 9)),
        isTrue,
      );
    });

    test('daysUntil is not shortened by a clock change in the way', () {
      // Egypt starts summer time on 24 April 2026, so the run-up to a race on
      // the 26th is an hour short of nineteen 24-hour days -- and a countdown
      // measuring elapsed time reads 18 for the whole fortnight before it.
      final race = _event(startAt: DateTime(2026, 4, 26, 7));
      expect(race.daysUntil(DateTime(2026, 4, 7, 20)), 19);
    });

    test('daysUntil counts calendar days, not elapsed hours', () {
      // 18:00 today to 06:00 tomorrow is twelve hours but one day, and a
      // countdown that called it zero would say "Today" on the wrong morning.
      final tomorrowMorning = _event(startAt: DateTime(2026, 8, 23, 6));
      expect(tomorrowMorning.daysUntil(DateTime(2026, 8, 22, 18)), 1);
    });
  });

  group('RaceTimeframe', () {
    test('this week runs to the end of Sunday, not seven days out', () {
      // Saturday the 22nd: "this week" has to include tomorrow's races and stop
      // there, because somebody asking what is on this weekend means this one.
      final end = RaceTimeframe.thisWeek.endFrom(_now);
      expect(end, DateTime(2026, 8, 24));
    });

    test('this month runs to month end', () {
      expect(RaceTimeframe.thisMonth.endFrom(_now), DateTime(2026, 9, 1));
    });

    test('all upcoming has no end', () {
      expect(RaceTimeframe.all.endFrom(_now), isNull);
    });

    test('a rolling window crossing a year end still resolves', () {
      final november = DateTime(2026, 11, 10);
      expect(
        RaceTimeframe.threeMonths.endFrom(november),
        DateTime(2027, 2, 10),
      );
    });
  });

  group('RaceFilter.matches', () {
    test('an empty filter matches everything', () {
      expect(const RaceFilter().matches(_event()), isTrue);
    });

    test('provinces are an OR — any of the chosen ones', () {
      const filter = RaceFilter(
        provinces: {Province.gauteng, Province.westernCape},
      );
      expect(filter.matches(_event(province: Province.gauteng)), isTrue);
      expect(filter.matches(_event(province: Province.westernCape)), isTrue);
      expect(filter.matches(_event(province: Province.limpopo)), isFalse);
    });

    test('distances are an OR — a race with any chosen band matches', () {
      const filter = RaceFilter(buckets: {DistanceBucket.marathon});
      expect(filter.matches(_event()), isFalse);
      expect(
        filter.matches(
          _event(
            distances: const [
              RaceDistance(kilometres: 10, label: '10 km'),
              RaceDistance(kilometres: 42.2, label: 'Marathon'),
            ],
          ),
        ),
        isTrue,
      );
    });

    test('tags are an AND — trail plus qualifier means both', () {
      const filter = RaceFilter(
        tags: {RaceTag.trail, RaceTag.comradesQualifier},
      );
      expect(
        filter.matches(_event(tags: const {RaceTag.trail})),
        isFalse,
      );
      expect(
        filter.matches(
          _event(tags: const {RaceTag.trail, RaceTag.comradesQualifier}),
        ),
        isTrue,
      );
    });

    test('the query searches name, city and organiser', () {
      final event = _event(
        name: 'Chamberlain Country Classic',
        city: 'Midrand',
        organiser: 'Midrand Striders',
      );
      expect(const RaceFilter(query: 'chamberlain').matches(event), isTrue);
      expect(const RaceFilter(query: 'midrand').matches(event), isTrue);
      expect(const RaceFilter(query: 'striders').matches(event), isTrue);
      expect(const RaceFilter(query: 'stellenbosch').matches(event), isFalse);
    });

    test('the query also searches the venue, for renamed cities', () {
      // Gqeberha's races are listed under the new name while their venue
      // addresses still say "Port Elizabeth". Somebody searching the old name
      // has to find them.
      final event = RaceEvent(
        id: 'crusaders',
        name: 'CRUSADERS 21.1km, 10km & 5km',
        startAt: DateTime(2026, 10, 17, 6),
        venue: const RaceVenue(
          name: 'African Sky',
          addressLine: '120 Nassau Road, Port Elizabeth',
          city: 'Gqeberha',
          province: Province.easternCape,
        ),
        distances: const [RaceDistance(kilometres: 10, label: '10 km')],
      );
      expect(const RaceFilter(query: 'gqeberha').matches(event), isTrue);
      expect(const RaceFilter(query: 'port elizabeth').matches(event), isTrue);
      expect(const RaceFilter(query: 'african sky').matches(event), isTrue);
      expect(const RaceFilter(query: 'durban').matches(event), isFalse);
    });

    test('the query ignores case and surrounding spaces', () {
      expect(
        const RaceFilter(query: '  KYALAMI ').matches(_event()),
        isTrue,
      );
    });
  });

  group('RaceFilter toggles', () {
    test('toggling adds then removes, without mutating the original', () {
      const base = RaceFilter();
      final withGauteng = base.toggleProvince(Province.gauteng);
      expect(withGauteng.provinces, {Province.gauteng});
      expect(base.provinces, isEmpty);

      final without = withGauteng.toggleProvince(Province.gauteng);
      expect(without.provinces, isEmpty);
    });

    test('equality is by value, so an unchanged filter does not refetch', () {
      // This is what stops the events provider re-reading Firestore on every
      // rebuild: Riverpod compares the filter, and two filters holding the same
      // sets have to be equal for that to work.
      const a = RaceFilter(
        provinces: {Province.gauteng, Province.westernCape},
        buckets: {DistanceBucket.half},
      );
      const b = RaceFilter(
        provinces: {Province.westernCape, Province.gauteng},
        buckets: {DistanceBucket.half},
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('hasActiveFilters ignores the default timeframe', () {
      expect(const RaceFilter().hasActiveFilters, isFalse);
      expect(
        const RaceFilter(timeframe: RaceTimeframe.thisWeek).hasActiveFilters,
        isTrue,
      );
    });
  });

  group('RaceQueryPlan', () {
    test('spends the one server clause on provinces when there are any', () {
      final plan = RaceQueryPlan.from(
        filter: const RaceFilter(
          provinces: {Province.gauteng},
          buckets: {DistanceBucket.half},
          tags: {RaceTag.comradesQualifier},
        ),
        now: _now,
      );
      expect(plan.serverClause, RaceServerClause.provinces);
      expect(
        plan.clientClauses,
        {RaceServerClause.distances, RaceServerClause.tags},
      );
    });

    test('falls back to distances when no province is chosen', () {
      final plan = RaceQueryPlan.from(
        filter: const RaceFilter(
          buckets: {DistanceBucket.half},
          tags: {RaceTag.trail},
        ),
        now: _now,
      );
      expect(plan.serverClause, RaceServerClause.distances);
      expect(plan.clientClauses, {RaceServerClause.tags});
    });

    test('a tag-only filter is answered by the server', () {
      // The case that matters: "Comrades qualifiers" on its own is a real query
      // somebody runs, and it should not read the whole calendar to answer it.
      final plan = RaceQueryPlan.from(
        filter: const RaceFilter(tags: {RaceTag.comradesQualifier}),
        now: _now,
      );
      expect(plan.serverClause, RaceServerClause.tags);
      expect(plan.filtersOnClient, isFalse);
    });

    test('an unfiltered calendar needs no clause and no over-fetch', () {
      final plan = RaceQueryPlan.from(filter: const RaceFilter(), now: _now);
      expect(plan.serverClause, RaceServerClause.none);
      expect(plan.fetchLimit(200), 200);
    });

    test('over-fetches for each clause left to the client, up to the cap', () {
      final one = RaceQueryPlan.from(
        filter: const RaceFilter(
          provinces: {Province.gauteng},
          buckets: {DistanceBucket.half},
        ),
        now: _now,
      );
      expect(one.fetchLimit(100), 200);

      final capped = RaceQueryPlan.from(
        filter: const RaceFilter(
          provinces: {Province.gauteng},
          buckets: {DistanceBucket.half},
          tags: {RaceTag.trail},
        ),
        now: _now,
      );
      expect(capped.fetchLimit(300), RaceQueryPlan.maxFetch);
    });

    test('reaches back before today so a stage race in progress survives', () {
      final plan = RaceQueryPlan.from(filter: const RaceFilter(), now: _now);
      expect(plan.from.isBefore(DateTime(2026, 8, 22)), isTrue);
      expect(plan.from, DateTime(2026, 8, 12));
    });

    test('carries the timeframe as the upper bound', () {
      final plan = RaceQueryPlan.from(
        filter: const RaceFilter(timeframe: RaceTimeframe.thisMonth),
        now: _now,
      );
      expect(plan.until, DateTime(2026, 9, 1));

      final unbounded = RaceQueryPlan.from(
        filter: const RaceFilter(timeframe: RaceTimeframe.all),
        now: _now,
      );
      expect(unbounded.until, isNull);
    });
  });

  group('RaceFormat', () {
    test('writes dates the South African way round', () {
      expect(RaceFormat.date(DateTime(2026, 8, 30)), '30 Aug 2026');
      expect(RaceFormat.dayAndDate(DateTime(2026, 8, 30)), 'Sun 30 Aug');
      expect(RaceFormat.monthHeader(DateTime(2026, 8, 30)), 'August 2026');
    });

    test('uses a 24-hour clock', () {
      expect(RaceFormat.time(DateTime(2026, 8, 30, 6, 30)), '06:30');
      expect(RaceFormat.time(DateTime(2026, 8, 30, 17, 5)), '17:05');
    });

    test('collapses a same-month range to one month name', () {
      final stageRace = _event(
        startAt: DateTime(2026, 9, 12),
        endAt: DateTime(2026, 9, 14),
      );
      expect(RaceFormat.dateRange(stageRace), '12–14 Sep 2026');
    });

    test('spells out a range that crosses a month', () {
      final event = _event(
        startAt: DateTime(2026, 9, 30),
        endAt: DateTime(2026, 10, 2),
      );
      expect(RaceFormat.dateRange(event), '30 Sep 2026 – 2 Oct 2026');
    });

    test('a single-day event has no range', () {
      expect(RaceFormat.dateRange(_event()), '12 Sep 2026');
    });

    test('counts down in the words a runner would use', () {
      expect(
        RaceFormat.countdown(_event(startAt: DateTime(2026, 8, 22, 6)), _now),
        'Today',
      );
      expect(
        RaceFormat.countdown(_event(startAt: DateTime(2026, 8, 23, 6)), _now),
        'Tomorrow',
      );
      expect(
        RaceFormat.countdown(_event(startAt: DateTime(2026, 8, 25, 6)), _now),
        'In 3 days',
      );
      expect(
        RaceFormat.countdown(_event(startAt: DateTime(2026, 9, 12, 6)), _now),
        'In 3 weeks',
      );
    });

    test('a race that has been and gone has no countdown', () {
      expect(
        RaceFormat.countdown(_event(startAt: DateTime(2026, 8, 1)), _now),
        isNull,
      );
    });

    test('summarises distances, and truncates a long list', () {
      expect(RaceFormat.distanceSummary(_event()), '10 km · Half Marathon');
      expect(
        RaceFormat.distanceSummary(
          _event(
            distances: const [
              RaceDistance(kilometres: 5, label: '5 km'),
              RaceDistance(kilometres: 10, label: '10 km'),
              RaceDistance(kilometres: 15, label: '15 km'),
              RaceDistance(kilometres: 21.1, label: '21.1 km'),
              RaceDistance(kilometres: 42.2, label: '42.2 km'),
            ],
          ),
          max: 3,
        ),
        '5 km · 10 km · 15 km +2',
      );
    });

    test('says so when the organiser has published no distances', () {
      expect(
        RaceFormat.distanceSummary(_event(distances: const [])),
        'Distances to be confirmed',
      );
    });
  });

  group('Province', () {
    test('separates the nine SA provinces from the neighbours', () {
      expect(Province.southAfrican, hasLength(9));
      expect(Province.gauteng.isSouthAfrican, isTrue);
      expect(Province.namibia.isSouthAfrican, isFalse);
    });

    test('round-trips through its stored code', () {
      for (final province in Province.values) {
        expect(Province.byCode(province.code), province);
      }
      expect(Province.byCode('ZZ'), isNull);
      expect(Province.byCode(null), isNull);
    });
  });
}
