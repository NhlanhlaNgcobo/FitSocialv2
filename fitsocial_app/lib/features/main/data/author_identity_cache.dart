/// The live half of an author's identity, against the copy frozen onto their
/// posts.
///
/// Every post, comment and pulse denormalises `authorName` and
/// `authorAvatarUrl` at write time, so the feed can render from the documents
/// it already reads instead of resolving a profile per card. Nothing ever
/// rewrites those copies, so renaming leaves every earlier post attributed to
/// the old name and every earlier avatar showing the old photo.
///
/// This closes that gap on the read path rather than by fanning a rename out
/// across the author's whole history: the current values are resolved once per
/// author, cached for [AuthorIdentityCache.defaultTtl], and laid over the
/// stored ones by the mapper. The stored copy stays the fallback — it is what
/// still renders when the profile can't be read at all.
///
/// Deliberately free of `cloud_firestore` types: the fetch is injected, which
/// keeps the caching policy here testable without a Firestore instance.
library;

/// A user's public identity as it stands now.
class AuthorIdentity {
  const AuthorIdentity({this.displayName, this.avatarUrl});

  final String? displayName;

  /// Null when the user has no profile photo. That is a real answer rather
  /// than a missing one — it is what lets an avatar the user has since removed
  /// disappear from their old posts instead of lingering there.
  final String? avatarUrl;
}

/// Reads the current identities of [userIds].
///
/// Only ids whose profile document was actually read may appear in the result.
/// An absent entry means "unknown", and the caller keeps whatever the post
/// stored — an account that has been deleted must not have its posts fall back
/// to a placeholder name.
typedef AuthorIdentityFetch = Future<Map<String, AuthorIdentity>> Function(
  List<String> userIds,
);

/// Resolves author identities, remembering what it has already looked up.
///
/// One instance lives on the content repository, so a session's reads
/// accumulate: by the time the user has scrolled a feed, the people they
/// follow are all resolved and opening a post costs nothing further.
class AuthorIdentityCache {
  AuthorIdentityCache(
    this._fetch, {
    Duration? ttl,
    DateTime Function()? clock,
  })  : _ttl = ttl ?? defaultTtl,
        _now = clock ?? DateTime.now;

  /// How long a resolved identity is trusted before it is read again.
  ///
  /// Nothing invalidates this cache on a write, so the interval *is* the
  /// freshness guarantee for everyone but the signed-in user — see [seed].
  /// Five minutes keeps a session's feed to roughly one read per author while
  /// still letting somebody else's rename arrive in the same sitting.
  static const Duration defaultTtl = Duration(minutes: 5);

  final AuthorIdentityFetch _fetch;
  final Duration _ttl;
  final DateTime Function() _now;

  final Map<String, _CacheEntry> _entries = {};

  /// Batches already in flight, by the uid each one covers. Two screens
  /// loading at once ask for overlapping authors; without this each would pay
  /// for the same profile reads.
  final Map<String, Future<void>> _inFlight = {};

  /// Records [identity] for [userId] without a read.
  ///
  /// The signed-in user's own profile is known locally the moment it is saved,
  /// and they are the person most likely to notice a stale name — their own,
  /// on their own posts. Seeding from the session makes their rename show on
  /// the very next feed load rather than after the TTL.
  void seed(String userId, AuthorIdentity identity) {
    if (userId.isEmpty) return;
    _entries[userId] = _CacheEntry(identity, _now());
  }

  /// The current identity of every id in [userIds] that could be resolved.
  ///
  /// Ids that are unknown — never read, read and absent, or lost to an error —
  /// are simply missing from the result. Never throws: a name lookup failing
  /// must cost the feed its freshness, not its posts.
  Future<Map<String, AuthorIdentity>> resolve(Iterable<String> userIds) async {
    final wanted = userIds.where((id) => id.isNotEmpty).toSet();
    if (wanted.isEmpty) return const {};

    final now = _now();
    final missing = <String>[];
    final pending = <Future<void>>{};

    for (final id in wanted) {
      if (!_isStale(_entries[id], now)) continue;
      final inFlight = _inFlight[id];
      if (inFlight != null) {
        pending.add(inFlight);
      } else {
        missing.add(id);
      }
    }

    if (missing.isNotEmpty) pending.add(_fetchInto(missing));
    if (pending.isNotEmpty) await Future.wait(pending);

    return {
      for (final id in wanted)
        if (_entries[id]?.identity case final identity?) id: identity,
    };
  }

  bool _isStale(_CacheEntry? entry, DateTime now) =>
      entry == null || now.difference(entry.readAt) >= _ttl;

  /// Reads [userIds] and records the answers, including the absences.
  ///
  /// A uid the fetch came back without is cached as a null identity rather
  /// than left missing, so an author with no profile document is asked about
  /// once per TTL instead of on every feed load. A failed fetch records
  /// nothing at all, so the next call retries.
  Future<void> _fetchInto(List<String> userIds) {
    final future = () async {
      try {
        final fetched = await _fetch(userIds);
        final readAt = _now();
        for (final id in userIds) {
          _entries[id] = _CacheEntry(fetched[id], readAt);
        }
      } catch (_) {
        // Swallowed on purpose. The caller falls back to the denormalised
        // copy on the post, which is exactly what it rendered before this
        // cache existed.
      } finally {
        for (final id in userIds) {
          _inFlight.remove(id);
        }
      }
    }();

    for (final id in userIds) {
      _inFlight[id] = future;
    }
    return future;
  }
}

class _CacheEntry {
  const _CacheEntry(this.identity, this.readAt);

  /// Null for a uid with no profile document — a resolved absence, which is
  /// why it is cached rather than retried.
  final AuthorIdentity? identity;
  final DateTime readAt;
}
