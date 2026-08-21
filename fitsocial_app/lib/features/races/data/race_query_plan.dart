import '../domain/race_models.dart';

/// Which of the filter's disjunctive clauses the server gets to answer.
enum RaceServerClause { none, provinces, distances, tags }

/// How one [RaceFilter] is split between Firestore and the client.
///
/// This exists because of a hard Firestore constraint: a query carries at most
/// one disjunctive (`in` / `array-contains-any`) clause, while the filter row
/// offers three. Something has to decide which one travels to the server, and
/// doing that inline in the repository would make the rule invisible and
/// untestable. It is a plain value object with no Firestore types in it, so the
/// decision can be asserted directly in a unit test.
class RaceQueryPlan {
  const RaceQueryPlan({
    required this.from,
    required this.until,
    required this.serverClause,
    required this.clientClauses,
  });

  /// Builds the plan for [filter] as of [now].
  factory RaceQueryPlan.from({
    required RaceFilter filter,
    required DateTime now,
  }) {
    final today = DateTime(now.year, now.month, now.day);

    // The lower bound sits behind today rather than on it. A three-day stage
    // race that started on Friday is still an upcoming event on Saturday, and a
    // bound of exactly today would have excluded it by its start date. Ten days
    // is longer than any multi-day event on the SA calendar and cheap to
    // over-read; the finished ones are dropped by RaceEvent.isPast.
    final from = today.subtract(const Duration(days: 10));

    final until = filter.timeframe.endFrom(now);

    // Provinces first when there are few enough to fit `whereIn`. Geography is
    // the most selective filter on this calendar by a wide margin — a runner in
    // the Western Cape is excluding roughly eight ninths of the country — so
    // spending the one server clause there returns the smallest page.
    //
    // Distances come next because the chip row is used more than the tag row,
    // and a distance filter still cuts the set by a useful fraction. Tags get
    // the clause only when they are the sole filter, which is the case that
    // matters: "Comrades qualifiers" on its own is a real query somebody runs.
    final RaceServerClause serverClause;
    if (filter.provinces.isNotEmpty &&
        filter.provinces.length <= whereInLimit) {
      serverClause = RaceServerClause.provinces;
    } else if (filter.buckets.isNotEmpty &&
        filter.buckets.length <= whereInLimit) {
      serverClause = RaceServerClause.distances;
    } else if (filter.tags.isNotEmpty && filter.tags.length <= whereInLimit) {
      serverClause = RaceServerClause.tags;
    } else {
      serverClause = RaceServerClause.none;
    }

    // Whatever the server did not take, the client finishes. Recorded rather
    // than recomputed so a caller can see how much local work a filter implies,
    // and so a test can pin it.
    final clientClauses = <RaceServerClause>{
      if (filter.provinces.isNotEmpty) RaceServerClause.provinces,
      if (filter.buckets.isNotEmpty) RaceServerClause.distances,
      if (filter.tags.isNotEmpty) RaceServerClause.tags,
    }..remove(serverClause);

    return RaceQueryPlan(
      from: from,
      until: until,
      serverClause: serverClause,
      clientClauses: clientClauses,
    );
  }

  /// Firestore's cap on values in an `in` or `array-contains-any` clause.
  static const int whereInLimit = 30;

  /// Inclusive lower bound on `startAt`.
  final DateTime from;

  /// Exclusive upper bound on `startAt`. Null for [RaceTimeframe.all].
  final DateTime? until;

  /// The clause the query carries.
  final RaceServerClause serverClause;

  /// The clauses [RaceFilter.matches] has to apply to what comes back.
  final Set<RaceServerClause> clientClauses;

  /// Whether any filtering happens after the read.
  bool get filtersOnClient => clientClauses.isNotEmpty;

  /// How many documents to ask for, to end up with [limit] after local filtering.
  ///
  /// Over-fetching is the price of the one-clause limit. The multiplier is
  /// deliberately modest and capped: a filter that needs more than 600 documents
  /// read to fill one screen is better served by the user narrowing the
  /// timeframe than by the app quietly reading the whole calendar.
  int fetchLimit(int limit) {
    if (!filtersOnClient) return limit;
    final scaled = limit * (1 + clientClauses.length);
    return scaled > maxFetch ? maxFetch : scaled;
  }

  /// Hard ceiling on documents read for one page.
  static const int maxFetch = 600;
}
