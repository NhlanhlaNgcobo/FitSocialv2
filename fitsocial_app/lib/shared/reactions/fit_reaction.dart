import 'package:flutter/material.dart';

/// The seven ways to react to a Pulse.
///
/// The *mechanics* here are Facebook's, and deliberately so — one reaction per
/// person, a tray on long-press, slide to aim — because that is the interaction
/// people already have muscle memory for. The *set* is not. Facebook's seven
/// carry Sad and Angry, which exist to let a newsfeed respond to bad news; a
/// Pulse is someone's training day, and handing every viewer a one-tap way to
/// boo it would be a strange thing to build into a fitness app.
///
/// So these are seven ways to cheer somebody on, and there is no way to jeer.
/// That asymmetry is the point, not an oversight.
///
/// Three rules come with the model, and the rest of the feature follows:
///   * one reaction per person per Pulse — picking a second replaces the first,
///     it does not add to it;
///   * a bare tap means [defaultReaction], because most people just want to
///     show up, and making them choose every time would slow it to a crawl;
///   * tapping the reaction you already gave takes it back.
enum FitReaction {
  love,
  fire,
  respect,
  strong,
  champion,
  celebrate,
  rocket;

  /// Stored form. Explicit rather than [name] so renaming a value here can
  /// never silently orphan the reactions already written to Firestore.
  String get key {
    switch (this) {
      case FitReaction.love:
        return 'love';
      case FitReaction.fire:
        return 'fire';
      case FitReaction.respect:
        return 'respect';
      case FitReaction.strong:
        return 'strong';
      case FitReaction.champion:
        return 'champion';
      case FitReaction.celebrate:
        return 'celebrate';
      case FitReaction.rocket:
        return 'rocket';
    }
  }

  /// The emoji itself. Drawn as text rather than shipped as art: the system
  /// emoji font already renders these at any size, in colour, on every
  /// platform, and a reaction that fails to load is worse than one that looks
  /// slightly different between phones.
  String get emoji {
    switch (this) {
      case FitReaction.love:
        return '\u{1F9E1}';
      case FitReaction.fire:
        return '\u{1F525}';
      case FitReaction.respect:
        return '\u{1F4AF}';
      case FitReaction.strong:
        // Carries an explicit medium skin-tone modifier rather than the
        // default yellow, so every viewer sees the same arm.
        return '\u{1F4AA}\u{1F3FD}';
      case FitReaction.champion:
        return '\u{1F3C6}';
      case FitReaction.celebrate:
        return '\u{1F973}';
      case FitReaction.rocket:
        return '\u{1F680}';
    }
  }

  /// What it is called out loud — the tooltip over the tray, and the word used
  /// in the author's breakdown.
  String get label {
    switch (this) {
      case FitReaction.love:
        return 'Love';
      case FitReaction.fire:
        return 'Fire';
      case FitReaction.respect:
        return 'Respect';
      case FitReaction.strong:
        return 'Strong';
      case FitReaction.champion:
        return 'Champion';
      case FitReaction.celebrate:
        return 'Celebrate';
      case FitReaction.rocket:
        return 'Progress';
    }
  }

  /// Tint used when this reaction is the one the viewer gave, so the bar reads
  /// as chosen at a glance rather than only by which emoji is showing.
  ///
  /// Each is pulled towards the colour of its own emoji so the badge and the
  /// glyph don't fight, and the seven are spread across the wheel so two
  /// adjacent ones are never confusable at badge size. Love takes the brand
  /// orange, which is what makes the default tap look like FitSocial.
  Color get accent {
    switch (this) {
      case FitReaction.love:
        return const Color(0xFFFF6B1A);
      case FitReaction.fire:
        return const Color(0xFFFF3B30);
      case FitReaction.respect:
        return const Color(0xFFE23D5A);
      case FitReaction.strong:
        return const Color(0xFF2FA84F);
      case FitReaction.champion:
        return const Color(0xFFF5B301);
      case FitReaction.celebrate:
        return const Color(0xFFB44BF7);
      case FitReaction.rocket:
        return const Color(0xFF3AA9C9);
    }
  }

  /// Tray order — also the tie-break order when two reactions have the same
  /// count, so a summary never reshuffles between reads.
  static const all = <FitReaction>[
    FitReaction.love,
    FitReaction.fire,
    FitReaction.respect,
    FitReaction.strong,
    FitReaction.champion,
    FitReaction.celebrate,
    FitReaction.rocket,
  ];

  /// What a bare tap gives, and what the untouched bar shows in outline.
  ///
  /// Named rather than spelled out at each call site so the "cheapest way to
  /// show up" can be changed in one place if the ordering ever does.
  static const defaultReaction = FitReaction.love;

  /// Null for a key this build doesn't know, so a reaction written by a newer
  /// app is skipped rather than rendered as the wrong one.
  static FitReaction? fromKey(String? value) {
    for (final reaction in all) {
      if (reaction.key == value) return reaction;
    }
    return null;
  }
}

/// One person's reaction to one Pulse.
///
/// Name and photo are denormalised the same way a viewer record does it, so
/// the author's breakdown renders from the query it already runs instead of a
/// profile read per reactor.
class FitReactionRecord {
  const FitReactionRecord({
    required this.userId,
    required this.name,
    required this.reaction,
    required this.reactedAt,
    this.avatarUrl,
  });

  final String userId;
  final String name;
  final FitReaction reaction;
  final DateTime reactedAt;
  final String? avatarUrl;
}

/// The reactions on one Pulse, counted.
class FitReactionSummary {
  const FitReactionSummary({required this.counts, required this.total});

  /// Only reactions with at least one taker appear. Iterating this is safe in
  /// any order; use [ranked] when order matters.
  final Map<FitReaction, int> counts;

  final int total;

  static const empty = FitReactionSummary(counts: {}, total: 0);

  bool get isEmpty => total == 0;

  int countOf(FitReaction reaction) => counts[reaction] ?? 0;

  /// Every reaction that was given, most-given first, ties broken by tray
  /// order. Facebook shows only the leading three on a post; [topReactions]
  /// is that slice, and this is the full list for the breakdown sheet.
  List<FitReaction> get ranked {
    final present = counts.keys.toList()
      ..sort((a, b) {
        final byCount = countOf(b).compareTo(countOf(a));
        if (byCount != 0) return byCount;
        return FitReaction.all
            .indexOf(a)
            .compareTo(FitReaction.all.indexOf(b));
      });
    return present;
  }

  /// The ones stacked on the summary row — at most three, the way Facebook
  /// caps its own.
  List<FitReaction> get topReactions =>
      ranked.take(3).toList(growable: false);
}

/// Counts [records] into a [FitReactionSummary].
///
/// Pure, so the ranking and tie-breaking rules can be tested without Firestore.
FitReactionSummary summarizeFitReactions(
  Iterable<FitReactionRecord> records,
) {
  final counts = <FitReaction, int>{};
  var total = 0;
  for (final record in records) {
    counts[record.reaction] = (counts[record.reaction] ?? 0) + 1;
    total++;
  }
  return FitReactionSummary(counts: counts, total: total);
}

/// Reads the `reactionCounts` map stored on a Pulse document.
///
/// Defensive on every axis, because this map is maintained by increments from
/// many clients rather than written whole by one:
///   * a key this build doesn't know is skipped, so a reaction added in a later
///     release doesn't render as a blank;
///   * a zero or negative count is dropped rather than shown, because taking a
///     reaction back leaves the key behind at zero;
///   * a non-numeric value counts as nothing at all.
FitReactionSummary readFitReactionCounts(Object? stored) {
  if (stored is! Map) return FitReactionSummary.empty;

  final counts = <FitReaction, int>{};
  var total = 0;
  for (final entry in stored.entries) {
    final key = entry.key;
    final reaction = FitReaction.fromKey(key is String ? key : null);
    if (reaction == null) continue;
    final value = entry.value;
    final count = value is num ? value.toInt() : 0;
    if (count <= 0) continue;
    counts[reaction] = count;
    total += count;
  }
  return FitReactionSummary(counts: counts, total: total);
}

/// The same, for a place that already knows the true total independently of
/// the breakdown — posts, where `likesCount` has been counting since before
/// there were reactions to break down.
///
/// Anything [knownTotal] claims that `reactionCounts` cannot account for is
/// attributed to [FitReaction.defaultReaction]. That is what makes a like cast
/// under the old single-button model show up as 🧡 without a migration: those
/// posts carry a count and no map at all, and this reads them as a pile of
/// Loves. A breakdown that has drifted *above* the total is left alone rather
/// than trimmed — the map is the more detailed record of the two, and quietly
/// deleting from it would lose more than it fixed.
FitReactionSummary readReactionCountsAgainstTotal(
  Object? stored,
  int knownTotal,
) {
  final counted = readFitReactionCounts(stored);
  final unaccounted = knownTotal - counted.total;
  if (unaccounted <= 0) return counted;

  final counts = Map<FitReaction, int>.from(counted.counts);
  counts[FitReaction.defaultReaction] =
      (counts[FitReaction.defaultReaction] ?? 0) + unaccounted;
  return FitReactionSummary(counts: counts, total: knownTotal);
}

/// "1 reaction" / "12 reactions" — the label under the author's own Pulse.
String reactionCountLabel(int count) =>
    count == 1 ? '1 reaction' : '$count reactions';
