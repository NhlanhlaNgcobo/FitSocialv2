import 'app_models.dart';

/// How a shared post is drawn on the card that stands in for it.
///
/// Not [PostType]: that records what the post *is*, and includes distinctions
/// the card does not draw differently (a meal and a photo are both a picture)
/// while missing one it does (a run only gets a map if it actually has a
/// route). Resolved once, at share time, by [SharedPostRef.fromFeedPost].
enum SharedPostKind {
  photo,
  route,
  workout,

  /// Words only — the caption becomes the card.
  text;

  String get key {
    switch (this) {
      case SharedPostKind.photo:
        return 'photo';
      case SharedPostKind.route:
        return 'route';
      case SharedPostKind.workout:
        return 'workout';
      case SharedPostKind.text:
        return 'text';
    }
  }

  static SharedPostKind fromKey(String? value) {
    switch (value) {
      case 'photo':
        return SharedPostKind.photo;
      case 'route':
        return SharedPostKind.route;
      case 'workout':
        return SharedPostKind.workout;
      case 'text':
      default:
        return SharedPostKind.text;
    }
  }
}

/// Enough of a post to draw it somewhere else, plus the id to get back to it.
///
/// Written onto the Pulse document when a post is shared to Pulse, rather than
/// the Pulse holding only a post id and reading it back. Three reasons, in
/// order of weight:
///
///  * The Pulse is played by people who follow its author, who may not follow
///    the *post's* author — a lookup would be denied for exactly the audience
///    the share was meant for.
///  * The card is on screen for every frame of playback, and a read per frame
///    is a query the tray has already paid for once.
///  * A Pulse is a snapshot of a moment. Editing or deleting the post after
///    the fact should not rewrite what somebody already put on their Pulse; it
///    stops the link from resolving, which the viewer says plainly.
///
/// This mirrors how posts already carry their author's name and photo.
class SharedPostRef {
  const SharedPostRef({
    required this.postId,
    required this.authorId,
    required this.authorName,
    required this.kind,
    this.authorAvatarUrl,
    this.activity = '',
    this.caption = '',
    this.imageUrl,
    this.aspectRatio,
    this.route = const [],
  });

  /// Builds a reference from the pieces a card already holds, for the callers
  /// that were handed a post's fields rather than the post — [PostCard] is
  /// built that way, and reassembling a [FeedPost] there just to take it apart
  /// again would be ceremony.
  ///
  /// The precedence between [route], [imageUrl] and [hasWorkout] is the one
  /// the feed card and the detail page already use: a real route outranks the
  /// stored type, and a run with no fixes falls back to being words.
  factory SharedPostRef.of({
    required String postId,
    required String authorId,
    required String authorName,
    String? authorAvatarUrl,
    String activity = '',
    String caption = '',
    String? imageUrl,
    double? aspectRatio,
    List<RoutePoint> route = const [],
    bool hasWorkout = false,
  }) {
    final image = (imageUrl ?? '').trim();
    final trace = _thin(route);
    final SharedPostKind kind;
    if (trace.length >= 2) {
      kind = SharedPostKind.route;
    } else if (image.isNotEmpty) {
      kind = SharedPostKind.photo;
    } else if (hasWorkout) {
      kind = SharedPostKind.workout;
    } else {
      kind = SharedPostKind.text;
    }

    return SharedPostRef(
      postId: postId,
      authorId: authorId,
      authorName: authorName,
      authorAvatarUrl: authorAvatarUrl,
      kind: kind,
      activity: activity.trim(),
      caption: _truncate(caption.trim()),
      imageUrl: image.isEmpty ? null : image,
      aspectRatio: aspectRatio,
      // Only a run carries its shape. On any other kind the trace would be
      // weight on the Pulse document that nothing draws.
      route: kind == SharedPostKind.route ? trace : const [],
    );
  }

  final String postId;
  final String authorId;

  /// The post author's public name and photo as they read when it was shared.
  final String authorName;
  final String? authorAvatarUrl;

  final SharedPostKind kind;

  /// The post's subtitle — "Morning run", "Push day". Empty when it had none.
  final String activity;

  /// The post's words. Truncated on the way in: this is a card inside a story
  /// frame, not the post itself, and the whole point is that it sends you to
  /// the real thing.
  final String caption;

  /// Photo to draw on the card. Null on everything that isn't a photo post.
  final String? imageUrl;

  /// width / height of [imageUrl], so the card keeps the shape the author
  /// cropped to instead of squaring it.
  final double? aspectRatio;

  /// The run's GPS trace, thinned to [maxRoutePoints], so the card can draw the
  /// shape that was actually run instead of a glyph standing in for it.
  ///
  /// Carried on the snapshot for the same reason the author's name is: the
  /// people playing the Pulse may not be allowed to read the post it came from.
  /// Empty on everything that isn't a run, and on shares written before the
  /// card knew how to draw one — those still get the placeholder.
  final List<RoutePoint> route;

  /// Longest caption carried onto the card. Two lines at the size it is set
  /// in, which is as much as fits under the picture before the card starts
  /// competing with the Pulse around it.
  static const int maxCaptionLength = 140;

  /// Fixes kept on the snapshot. The post itself stores up to 1500, which is
  /// the resolution a full-screen map needs; a thumbnail a third of a phone
  /// wide cannot show the difference, and every one of these is copied onto a
  /// Pulse document that is read on every frame of playback.
  static const int maxRoutePoints = 80;

  bool get hasImage => (imageUrl ?? '').isNotEmpty;

  /// A polyline needs at least two fixes; a single point is not a route.
  bool get hasRoute => route.length >= 2;

  static SharedPostRef fromFeedPost(FeedPost post) {
    return SharedPostRef.of(
      postId: post.id,
      authorId: post.authorId,
      authorName: post.userName,
      authorAvatarUrl: post.authorAvatarUrl,
      activity: post.activity,
      caption: post.caption,
      imageUrl: post.imageUrl,
      aspectRatio: post.imageAspectRatio,
      route: post.routePoints,
      hasWorkout: post.workoutData != null || post.postType == PostType.workout,
    );
  }

  static String _truncate(String value) {
    if (value.length <= maxCaptionLength) return value;
    return '${value.substring(0, maxCaptionLength - 1).trimRight()}…';
  }

  /// Evenly samples [route] down to [maxRoutePoints], always keeping the last
  /// fix — the finish is a landmark on the shape, and dropping it would leave
  /// a loop looking like it stopped short.
  static List<RoutePoint> _thin(List<RoutePoint> route) {
    if (route.length <= maxRoutePoints) return List.unmodifiable(route);

    final step = route.length / (maxRoutePoints - 1);
    return List.unmodifiable([
      for (var i = 0; i < maxRoutePoints - 1; i++) route[(i * step).floor()],
      route.last,
    ]);
  }

  Map<String, dynamic> toMap() => {
        'postId': postId,
        'authorId': authorId,
        'authorName': authorName,
        if (authorAvatarUrl != null) 'authorAvatarUrl': authorAvatarUrl,
        'kind': kind.key,
        if (activity.isNotEmpty) 'activity': activity,
        if (caption.isNotEmpty) 'caption': caption,
        if (imageUrl != null) 'imageUrl': imageUrl,
        if (aspectRatio != null) 'aspectRatio': aspectRatio,
        if (route.isNotEmpty)
          'route': [for (final point in route) point.toMap()],
      };

  /// Null for anything missing the post id, which is the one field the card
  /// cannot do without — a share that leads nowhere is not a share.
  static SharedPostRef? fromMap(Object? value) {
    if (value is! Map) return null;
    final postId = (value['postId'] ?? '').toString().trim();
    if (postId.isEmpty) return null;

    final caption = (value['caption'] ?? '').toString().trim();
    final image = (value['imageUrl'] ?? '').toString().trim();

    return SharedPostRef(
      postId: postId,
      authorId: (value['authorId'] ?? '').toString().trim(),
      // Sanitised on read as well as write, the same way every other
      // denormalised author name in the app is: this is shown to everyone, and
      // the document was written by a client.
      authorName: PublicAuthorName.sanitize(value['authorName'] as String?),
      authorAvatarUrl: (value['authorAvatarUrl'] ?? '').toString().trim().isEmpty
          ? null
          : (value['authorAvatarUrl'] as String).trim(),
      kind: SharedPostKind.fromKey(value['kind'] as String?),
      activity: (value['activity'] ?? '').toString().trim(),
      caption: _truncate(caption),
      imageUrl: image.isEmpty ? null : image,
      aspectRatio: (value['aspectRatio'] as num?)?.toDouble(),
      // Thinned again on the way back in: the length is capped on write, but
      // the document was written by a client and this is drawn on every frame.
      route: _thin(RoutePoint.listFromFirestore(value['route'])),
    );
  }
}
