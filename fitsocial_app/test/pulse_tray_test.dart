import 'package:fitsocial_app/features/pulse/domain/pulse_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fixed clock so "expired" and "recent" mean the same thing on every run.
final DateTime now = DateTime.utc(2026, 8, 3, 12);

PulseSegment segment({
  required String id,
  required String authorId,
  required Duration age,
  String authorName = 'Test Athlete',
  PulseMediaType type = PulseMediaType.text,
}) {
  final createdAt = now.subtract(age);
  return PulseSegment(
    id: id,
    authorId: authorId,
    authorName: authorName,
    type: type,
    createdAt: createdAt,
    expiresAt: createdAt.add(PulseTiming.lifetime),
    text: 'Session done',
  );
}

void main() {
  group('buildPulseTray', () {
    test('groups an author\'s segments oldest first', () {
      final entries = buildPulseTray(
        segments: [
          segment(id: 'b', authorId: 'ann', age: const Duration(hours: 1)),
          segment(id: 'a', authorId: 'ann', age: const Duration(hours: 5)),
          segment(id: 'c', authorId: 'ann', age: const Duration(minutes: 2)),
        ],
        seenMarkers: const {},
        currentUserId: 'me',
        now: now,
      );

      expect(entries, hasLength(1));
      expect(
        entries.single.segments.map((s) => s.id),
        ['a', 'b', 'c'],
      );
    });

    test('drops segments whose expiry has passed', () {
      final entries = buildPulseTray(
        segments: [
          segment(id: 'live', authorId: 'ann', age: const Duration(hours: 3)),
          segment(id: 'stale', authorId: 'bob', age: const Duration(hours: 25)),
        ],
        seenMarkers: const {},
        currentUserId: 'me',
        now: now,
      );

      expect(entries.map((e) => e.authorId), ['ann']);
    });

    test('ranks own ring first, then unseen, then watched — newest first', () {
      final entries = buildPulseTray(
        segments: [
          segment(id: 'w1', authorId: 'watched', age: const Duration(minutes: 5)),
          segment(id: 'u1', authorId: 'older', age: const Duration(hours: 6)),
          segment(id: 'u2', authorId: 'newer', age: const Duration(hours: 1)),
          segment(id: 'm1', authorId: 'me', age: const Duration(hours: 9)),
        ],
        // The watched author's only Pulse predates this cursor.
        seenMarkers: {'watched': now},
        currentUserId: 'me',
        now: now,
      );

      expect(
        entries.map((e) => e.authorId),
        ['me', 'newer', 'older', 'watched'],
      );
      expect(entries.last.hasUnseen, isFalse);
      expect(entries[1].hasUnseen, isTrue);
    });

    test('resumes at the first segment newer than the seen cursor', () {
      final entries = buildPulseTray(
        segments: [
          segment(id: 'a', authorId: 'ann', age: const Duration(hours: 8)),
          segment(id: 'b', authorId: 'ann', age: const Duration(hours: 6)),
          segment(id: 'c', authorId: 'ann', age: const Duration(hours: 2)),
        ],
        seenMarkers: {'ann': now.subtract(const Duration(hours: 6))},
        currentUserId: 'me',
        now: now,
      );

      expect(entries.single.firstUnseenIndex, 2);
      expect(entries.single.hasUnseen, isTrue);
    });

    test('replays a fully watched ring from the start', () {
      final entries = buildPulseTray(
        segments: [
          segment(id: 'a', authorId: 'ann', age: const Duration(hours: 8)),
          segment(id: 'b', authorId: 'ann', age: const Duration(hours: 2)),
        ],
        seenMarkers: {'ann': now},
        currentUserId: 'me',
        now: now,
      );

      expect(entries.single.hasUnseen, isFalse);
      expect(entries.single.firstUnseenIndex, 0);
    });

    test('marks the signed-in user\'s own ring', () {
      final entries = buildPulseTray(
        segments: [
          segment(id: 'a', authorId: 'me', age: const Duration(hours: 1)),
        ],
        seenMarkers: const {},
        currentUserId: 'me',
        now: now,
      );

      expect(entries.single.isOwn, isTrue);
      expect(entries.single.displayLabel, 'Pulse');
    });

    test('labels other people by first name', () {
      final entries = buildPulseTray(
        segments: [
          segment(
            id: 'a',
            authorId: 'ann',
            authorName: 'Ann Mokoena',
            age: const Duration(hours: 1),
          ),
        ],
        seenMarkers: const {},
        currentUserId: 'me',
        now: now,
      );

      expect(entries.single.displayLabel, 'Ann');
    });
  });

  group('PulseSegment.displayDuration', () {
    test('holds a still for the standard beat', () {
      expect(
        segment(id: 'a', authorId: 'ann', age: Duration.zero).displayDuration,
        PulseTiming.frameDuration,
      );
    });

    test('runs a video for its own length', () {
      final createdAt = now;
      final video = PulseSegment(
        id: 'v',
        authorId: 'ann',
        authorName: 'Ann',
        type: PulseMediaType.video,
        createdAt: createdAt,
        expiresAt: createdAt.add(PulseTiming.lifetime),
        mediaUrl: 'https://example.test/clip.mp4',
        videoDuration: const Duration(seconds: 18),
      );

      expect(video.displayDuration, const Duration(seconds: 18));
    });

    test('caps a video that claims more than the limit', () {
      final createdAt = now;
      final video = PulseSegment(
        id: 'v',
        authorId: 'ann',
        authorName: 'Ann',
        type: PulseMediaType.video,
        createdAt: createdAt,
        expiresAt: createdAt.add(PulseTiming.lifetime),
        mediaUrl: 'https://example.test/clip.mp4',
        videoDuration: const Duration(minutes: 30),
      );

      expect(video.displayDuration, PulseTiming.maxVideoDuration);
    });
  });

  group('pulseAgeLabel', () {
    test('reads as "now" inside the first minute', () {
      expect(
        pulseAgeLabel(now.subtract(const Duration(seconds: 30)), now),
        'now',
      );
    });

    test('switches to minutes then hours', () {
      expect(pulseAgeLabel(now.subtract(const Duration(minutes: 42)), now), '42m');
      expect(pulseAgeLabel(now.subtract(const Duration(hours: 6)), now), '6h');
    });
  });

  group('pulseInitials', () {
    test('takes first and last initials when there are two names', () {
      expect(pulseInitials('Bear Mdlalose'), 'BM');
    });

    test('takes one letter from a single name', () {
      expect(pulseInitials('Bear'), 'B');
    });

    test('is empty when there is no real name, which is what puts the '
        'empty-profile glyph in the ring', () {
      expect(pulseInitials('   '), '');
      expect(pulseInitials('FitSocial Member'), '');
    });
  });
}
