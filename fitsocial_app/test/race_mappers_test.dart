import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/races/data/race_mappers.dart';
import 'package:fitsocial_app/features/races/domain/race_models.dart';

/// A well-formed calendar document, as the ingest script writes it.
Map<String, dynamic> _doc({Map<String, dynamic> overrides = const {}}) {
  return {
    'name': 'Chamberlain Country Classic',
    'startAt': Timestamp.fromDate(DateTime.utc(2026, 8, 30, 4, 30)),
    'province': 'GP',
    'city': 'Midrand',
    'venueName': 'Kyalami Corner',
    'distances': [
      {'km': 21.1, 'label': 'Half Marathon', 'priceCents': 15000},
      {'km': 5, 'label': '5 km', 'priceCents': 5000},
      {'km': 10, 'label': '10 km', 'priceCents': 10000, 'startTime': '07:00'},
    ],
    'distanceBuckets': ['5k', '10k', '21.1k'],
    'tags': ['road', 'comrades-qualifier'],
    'organiser': 'Midrand Striders',
    'entryUrl': 'https://example.test/enter',
    'status': 'scheduled',
    'source': 'curated',
    ...overrides,
  };
}

void main() {
  group('raceEventFromDoc', () {
    test('reads a complete document', () {
      final event = raceEventFromDoc('race-1', _doc())!;

      expect(event.id, 'race-1');
      expect(event.name, 'Chamberlain Country Classic');
      expect(event.venue.city, 'Midrand');
      expect(event.venue.province, Province.gauteng);
      expect(event.venue.name, 'Kyalami Corner');
      expect(event.organiser, 'Midrand Striders');
      expect(event.entryUrl, 'https://example.test/enter');
      expect(event.status, RaceStatus.scheduled);
      expect(event.source, RaceSource.curated);
      expect(
        event.tags,
        {RaceTag.road, RaceTag.comradesQualifier},
      );
    });

    test('sorts distances shortest first regardless of stored order', () {
      // The document above lists the half first. A detail screen that showed the
      // distances in whatever order the source happened to use would read as
      // arbitrary.
      final event = raceEventFromDoc('race-1', _doc())!;
      expect(
        event.distances.map((distance) => distance.kilometres),
        [5, 10, 21.1],
      );
    });

    test('keeps a per-distance start time and leaves the others null', () {
      final event = raceEventFromDoc('race-1', _doc())!;
      expect(event.distances[1].startTime, '07:00');
      expect(event.distances[0].startTime, isNull);
    });

    test('refuses a document with no name or no date', () {
      expect(raceEventFromDoc('x', _doc(overrides: {'name': ''})), isNull);
      expect(
        raceEventFromDoc('x', {..._doc()}..remove('startAt')),
        isNull,
      );
      expect(raceEventFromDoc('x', null), isNull);
    });

    test('accepts an ISO date string, for a document written by hand', () {
      final event = raceEventFromDoc(
        'race-1',
        _doc(overrides: {'startAt': '2026-08-30T06:30:00+02:00'}),
      )!;
      expect(event.startAt.toUtc(), DateTime.utc(2026, 8, 30, 4, 30));
    });

    test('survives a broken province rather than hiding the race', () {
      // Wrong-but-visible is recoverable by a moderator; invisible is not.
      final event = raceEventFromDoc(
        'race-1',
        _doc(overrides: {'province': 'XX'}),
      )!;
      expect(event.venue.province, Province.gauteng);
    });

    test('drops malformed distance rows and keeps the good ones', () {
      final event = raceEventFromDoc(
        'race-1',
        _doc(
          overrides: {
            'distances': [
              {'km': 10, 'label': '10 km'},
              {'km': 'ten'},
              {'km': 0},
              'not a map',
              {'label': 'no distance at all'},
            ],
          },
        ),
      )!;
      expect(event.distances, hasLength(1));
      expect(event.distances.single.kilometres, 10);
    });

    test('derives a label for a distance the source did not name', () {
      final event = raceEventFromDoc(
        'race-1',
        _doc(
          overrides: {
            'distances': [
              {'km': 42.2},
              {'km': 21.1},
              {'km': 10},
              {'km': 12.5},
            ],
          },
        ),
      )!;
      expect(
        event.distances.map((distance) => distance.label),
        ['10 km', '12.5 km', 'Half Marathon', 'Marathon'],
      );
    });

    test('ignores tags it does not recognise', () {
      // A tag added to the seed file but not to RaceTag would otherwise throw.
      // Dropping it means the listing loses a badge, not the whole race.
      final event = raceEventFromDoc(
        'race-1',
        _doc(overrides: {'tags': ['road', 'invented-tag', 42, null]}),
      )!;
      expect(event.tags, {RaceTag.road});
    });

    test('falls back to the province name when a city is missing', () {
      final event = raceEventFromDoc(
        'race-1',
        _doc(overrides: {'city': '  '}),
      )!;
      expect(event.venue.city, 'Gauteng');
    });

    test('reads an end date, and treats its absence as single-day', () {
      expect(raceEventFromDoc('race-1', _doc())!.isMultiDay, isFalse);

      final stageRace = raceEventFromDoc(
        'race-1',
        _doc(
          overrides: {
            'endAt': Timestamp.fromDate(DateTime.utc(2026, 9, 1, 21, 59)),
          },
        ),
      )!;
      expect(stageRace.isMultiDay, isTrue);
    });

    test('treats a coordinate pair as a pin only when both are present', () {
      expect(raceEventFromDoc('race-1', _doc())!.venue.hasCoordinates, isFalse);

      final pinned = raceEventFromDoc(
        'race-1',
        _doc(overrides: {'lat': -25.9892, 'lng': 28.1263}),
      )!;
      expect(pinned.venue.hasCoordinates, isTrue);

      final halfPinned = raceEventFromDoc(
        'race-1',
        _doc(overrides: {'lat': -25.9892}),
      )!;
      expect(halfPinned.venue.hasCoordinates, isFalse);
    });

    test('an unknown status or source falls back to the safe default', () {
      final event = raceEventFromDoc(
        'race-1',
        _doc(overrides: {'status': 'who knows', 'source': 'who knows'}),
      )!;
      expect(event.status, RaceStatus.scheduled);
      expect(event.source, RaceSource.curated);
    });
  });

  group('raceSubmissionToDoc', () {
    test('stamps the submitter and starts the review as pending', () {
      final doc = raceSubmissionToDoc(
        'user-1',
        RaceSubmission(
          name: '  Example Race  ',
          startAt: DateTime.utc(2026, 10, 3, 4, 30),
          city: ' Midrand ',
          province: Province.gauteng,
        ),
      );

      expect(doc['submittedBy'], 'user-1');
      expect(doc['reviewState'], 'pending');
      expect(doc['name'], 'Example Race');
      expect(doc['city'], 'Midrand');
      expect(doc['province'], 'GP');
      // The rules require request.time, so the value has to be the sentinel and
      // not a client clock reading.
      expect(doc['submittedAt'], isA<FieldValue>());
    });

    test('omits the optional fields rather than writing empty strings', () {
      // The rules use `'organiser' in entry` to decide whether to check it, so
      // an absent field and an empty one are genuinely different here.
      final doc = raceSubmissionToDoc(
        'user-1',
        RaceSubmission(
          name: 'Example Race',
          startAt: DateTime.utc(2026, 10, 3),
          city: 'Midrand',
          province: Province.gauteng,
        ),
      );
      expect(doc.containsKey('organiser'), isFalse);
      expect(doc.containsKey('entryUrl'), isFalse);
      expect(doc.containsKey('distancesNote'), isFalse);
      expect(doc.containsKey('notes'), isFalse);
    });
  });
}
