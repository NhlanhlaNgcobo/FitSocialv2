/// Up Next: today's suggestions, as functions/up_next.js writes them to
/// `users/{uid}/upNext/{dayKey}`.
///
/// The server words every suggestion; the app only shows it, filters out what
/// was dismissed, and follows its route.
library;

class UpNextSuggestion {
  const UpNextSuggestion({
    required this.id,
    required this.kind,
    required this.title,
    required this.reason,
    required this.route,
  });

  /// Stable for the day: `streak`, `meal`, `week`, or `goal:<goalId>`.
  final String id;

  /// `streak`, `goal`, `meal` or `week`, for the icon and analytics.
  final String kind;
  final String title;
  final String reason;

  /// Where tapping it goes, an app route.
  final String route;

  static UpNextSuggestion? fromMap(Object? raw) {
    if (raw is! Map) return null;
    String text(Object? value) => value is String ? value.trim() : '';
    final id = text(raw['id']);
    final title = text(raw['title']);
    final route = text(raw['route']);
    // A route that is not an app path would send the router somewhere odd.
    if (id.isEmpty || title.isEmpty || !route.startsWith('/')) return null;
    return UpNextSuggestion(
      id: id,
      kind: text(raw['kind']),
      title: title,
      reason: text(raw['reason']),
      route: route,
    );
  }
}

/// Today's suggestions that have not been dismissed, best first.
List<UpNextSuggestion> visibleSuggestions(Map<String, dynamic>? data) {
  if (data == null) return const [];
  final dismissed = <String>{
    for (final id in (data['dismissed'] as List?) ?? const [])
      if (id is String) id,
  };
  return [
    for (final raw in (data['suggestions'] as List?) ?? const [])
      if (UpNextSuggestion.fromMap(raw) case final s?)
        if (!dismissed.contains(s.id)) s,
  ].take(3).toList();
}
