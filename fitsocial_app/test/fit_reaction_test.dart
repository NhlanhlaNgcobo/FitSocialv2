import 'package:fitsocial_app/shared/reactions/fit_reaction.dart';
import 'package:flutter_test/flutter_test.dart';

FitReactionRecord _record(
  String userId,
  FitReaction reaction, {
  int minutesAgo = 0,
}) {
  return FitReactionRecord(
    userId: userId,
    name: userId,
    reaction: reaction,
    reactedAt: DateTime(2026, 8, 9, 12).subtract(Duration(minutes: minutesAgo)),
  );
}

void main() {
  group('FitReaction keys', () {
    test('every reaction round-trips through its stored key', () {
      for (final reaction in FitReaction.all) {
        expect(FitReaction.fromKey(reaction.key), reaction);
      }
    });

    test('carries the seven reactions in tray order', () {
      expect(
        FitReaction.all.map((reaction) => reaction.key).toList(),
        ['love', 'fire', 'respect', 'strong', 'champion', 'celebrate',
         'rocket'],
      );
    });

    test('a bare tap gives the first of them', () {
      // The default has to be in the tray, or the pill would show a reaction the
      // long-press cannot reach.
      expect(FitReaction.all, contains(FitReaction.defaultReaction));
      expect(FitReaction.defaultReaction, FitReaction.all.first);
    });

    test('offers no way to jeer', () {
      // Deliberate: Facebook carries Sad and Angry so a newsfeed can respond
      // to bad news. A Pulse is somebody's training day.
      for (final key in ['sad', 'angry', 'dislike', 'boo']) {
        expect(FitReaction.fromKey(key), isNull, reason: '$key must not map');
      }
    });

    test('an unknown or missing key resolves to nothing rather than a guess',
        () {
      // A reaction added in a later release must be skipped, not rendered as
      // the wrong one.
      expect(FitReaction.fromKey('deadlift'), isNull);
      expect(FitReaction.fromKey(''), isNull);
      expect(FitReaction.fromKey(null), isNull);
    });
  });

  group('summarizeFitReactions', () {
    test('counts each reaction and totals them', () {
      final summary = summarizeFitReactions([
        _record('a', FitReaction.love),
        _record('b', FitReaction.love),
        _record('c', FitReaction.fire),
      ]);

      expect(summary.total, 3);
      expect(summary.countOf(FitReaction.love), 2);
      expect(summary.countOf(FitReaction.fire), 1);
      expect(summary.countOf(FitReaction.rocket), 0);
    });

    test('no reactions is empty rather than a row of zeros', () {
      final summary = summarizeFitReactions(const []);
      expect(summary.isEmpty, isTrue);
      expect(summary.ranked, isEmpty);
      expect(summary.topReactions, isEmpty);
    });

    test('ranks by count, breaking ties on tray order', () {
      // champion and love are level; love leads because it sits earlier in the
      // tray. Without a fixed tie-break the row would reshuffle between reads.
      final summary = summarizeFitReactions([
        _record('a', FitReaction.champion),
        _record('b', FitReaction.love),
        _record('c', FitReaction.fire),
        _record('d', FitReaction.fire),
        _record('e', FitReaction.fire),
      ]);

      expect(summary.ranked, [
        FitReaction.fire,
        FitReaction.love,
        FitReaction.champion,
      ]);
    });

    test('shows at most three, the way Facebook caps its own summary', () {
      final summary = summarizeFitReactions([
        for (final reaction in FitReaction.all)
          _record(reaction.key, reaction),
      ]);

      expect(summary.total, 7);
      expect(summary.ranked, hasLength(7));
      expect(summary.topReactions, hasLength(3));
      expect(summary.topReactions, FitReaction.all.take(3));
    });
  });

  group('readFitReactionCounts', () {
    test('reads the stored map', () {
      final summary = readFitReactionCounts({'love': 4, 'rocket': 1});
      expect(summary.total, 5);
      expect(summary.countOf(FitReaction.love), 4);
      expect(summary.countOf(FitReaction.rocket), 1);
    });

    test('drops reactions that fell back to zero', () {
      // Taking a reaction back decrements the key rather than removing it, so
      // a stored zero is the normal state of an unpicked reaction.
      final summary = readFitReactionCounts(
        {'love': 2, 'strong': 0, 'champion': -1},
      );

      expect(summary.total, 2);
      expect(summary.ranked, [FitReaction.love]);
      expect(summary.countOf(FitReaction.strong), 0);
    });

    test('ignores keys and values it does not understand', () {
      // 'like' is here on purpose: it was a key in an earlier build, and a
      // document still carrying one must not be counted under a reaction this
      // build no longer has.
      final summary = readFitReactionCounts({
        'love': 3,
        'like': 9,
        'fire': 'lots',
      });

      expect(summary.total, 3);
      expect(summary.ranked, [FitReaction.love]);
    });

    test('a missing or malformed field reads as no reactions at all', () {
      expect(readFitReactionCounts(null).isEmpty, isTrue);
      expect(readFitReactionCounts(7).isEmpty, isTrue);
      expect(readFitReactionCounts(const <String, int>{}).isEmpty, isTrue);
    });
  });

  group('readReactionCountsAgainstTotal', () {
    test('a post with old likes and no breakdown reads as all default', () {
      // Exactly the shape of every like cast before reactions existed: a
      // likesCount and no map at all. Reading it as empty would blank the
      // summary row on posts that plainly have engagement.
      final summary = readReactionCountsAgainstTotal(null, 4);

      expect(summary.total, 4);
      expect(summary.countOf(FitReaction.defaultReaction), 4);
      expect(summary.ranked, [FitReaction.defaultReaction]);
    });

    test('a partly migrated post splits between the two', () {
      // Three old likes plus two reactions given since.
      final summary = readReactionCountsAgainstTotal({'fire': 2}, 5);

      expect(summary.total, 5);
      expect(summary.countOf(FitReaction.fire), 2);
      expect(summary.countOf(FitReaction.defaultReaction), 3);
    });

    test('a fully accounted post is left exactly as stored', () {
      final summary = readReactionCountsAgainstTotal(
        {'fire': 2, 'champion': 1},
        3,
      );

      expect(summary.total, 3);
      expect(summary.countOf(FitReaction.defaultReaction), 0);
      expect(summary.ranked, [FitReaction.fire, FitReaction.champion]);
    });

    test('a breakdown ahead of the total is trusted over the total', () {
      // Counter drift, which increments can produce. The map is the more
      // detailed record, so it wins rather than being trimmed to fit.
      final summary = readReactionCountsAgainstTotal({'fire': 5}, 2);

      expect(summary.total, 5);
      expect(summary.countOf(FitReaction.fire), 5);
    });

    test('no likes at all stays empty', () {
      expect(readReactionCountsAgainstTotal(null, 0).isEmpty, isTrue);
    });
  });

  group('count labels', () {
    test('singular and plural', () {
      expect(reactionCountLabel(0), '0 reactions');
      expect(reactionCountLabel(1), '1 reaction');
      expect(reactionCountLabel(12), '12 reactions');

    });
  });
}
