/// The links FitSocial hands out, and the routes incoming ones land on.
///
/// One shared post has two spellings of the same address:
///
///   https://fitsocialv2.web.app/post/{id}   — what gets shared
///   fitsocial://app/post/{id}               — what the landing page hands off
///
/// The https form is the only one a stranger ever sees. On a phone with the app
/// installed it opens straight into FitSocial (an Android App Link / iOS
/// Universal Link); on every other device it opens the hosted page in
/// `hosting/`, which offers the store. The custom scheme exists because that
/// page needs a way to reach an installed app that the OS did *not* claim the
/// https link for — an unverified App Link, a desktop browser handing off to a
/// phone, an APK installed outside the store.
///
/// Both forms carry the same path, which is what lets go_router match either
/// one without a translation step: it routes on `Uri.path`, and
/// `fitsocial://app/post/{id}` has the path `/post/{id}` just as the https URL
/// does. The `app` host is a placeholder for exactly that reason — a scheme
/// with no host would push the first segment into the host slot and leave the
/// path empty.
library;

abstract final class FitSocialLinks {
  /// Firebase Hosting site for the `fitsocialv2` project. Swap this for the
  /// custom domain once one is attached — and update
  /// `hosting/.well-known/assetlinks.json` and the Android intent filter with
  /// it at the same time, or verified App Links stop resolving.
  static const String webHost = 'fitsocialv2.web.app';

  /// Registered in AndroidManifest.xml and Info.plist. See the library note
  /// above for why this is not the primary form.
  static const String customScheme = 'fitsocial';

  /// Host segment of a custom-scheme link. Carries no meaning; it is only
  /// there so the path survives parsing.
  static const String customSchemeHost = 'app';

  /// Where a phone without FitSocial is sent. Read by the hosted landing page,
  /// which is the only thing that opens a store.
  static const String androidPackage = 'com.fitsocial.fitsocial_app';

  /// Path prefixes that name a piece of shareable content.
  ///
  /// Anything outside this set is not a link we published, so it is neither
  /// held over a sign-in nor treated as a destination — see [routeFor].
  static const Set<String> _shareablePrefixes = {'post', 'user'};

  /// The link to hand out for a post. This is what the OS share sheet sends.
  static Uri post(String postId) => _web('post', postId);

  /// The link to hand out for someone's profile.
  static Uri profile(String userId) => _web('user', userId);

  /// The custom-scheme twin of [post], for the landing page's hand-off.
  static Uri postScheme(String postId) => _scheme('post', postId);

  /// In-app route for an incoming link, or null when the link is not one of
  /// ours — a stray `https://fitsocialv2.web.app/privacy` must not be mistaken
  /// for a destination inside the app.
  ///
  /// Accepts both spellings: host is checked only on http(s) links, because a
  /// custom-scheme link can only have reached the app by being addressed to it.
  static String? routeFor(Uri uri) {
    final isWeb = uri.scheme == 'https' || uri.scheme == 'http';
    if (isWeb) {
      if (uri.host.toLowerCase() != webHost) return null;
    } else if (uri.scheme != customScheme) {
      return null;
    }

    final segments = uri.pathSegments
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    if (segments.length != 2) return null;

    final kind = segments.first.toLowerCase();
    if (!_shareablePrefixes.contains(kind)) return null;

    final id = Uri.decodeComponent(segments[1]);
    if (!_isSafeId(id)) return null;

    return '/$kind/${Uri.encodeComponent(id)}';
  }

  /// Whether an in-app route is one a stranger could have arrived on, and
  /// therefore worth holding onto across a sign-in.
  ///
  /// Deliberately a whitelist rather than "anything that isn't an auth route":
  /// the pending route is replayed after authentication, and replaying an
  /// arbitrary path would let a crafted link choose where a user lands the
  /// first time they open the app.
  static bool isShareableRoute(String location) {
    final path = Uri.tryParse(location)?.path ?? location;
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.length != 2) return false;
    return _shareablePrefixes.contains(segments.first.toLowerCase()) &&
        _isSafeId(Uri.decodeComponent(segments[1]));
  }

  /// Firestore document ids are alphanumeric, but ids also arrive from
  /// untrusted links — so the shape is checked rather than assumed. Rejects
  /// anything that could re-enter the router as a second path segment.
  static bool _isSafeId(String id) {
    if (id.isEmpty || id.length > 128) return false;
    return RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id);
  }

  static Uri _web(String kind, String id) =>
      Uri.https(webHost, '/$kind/${Uri.encodeComponent(id)}');

  static Uri _scheme(String kind, String id) => Uri(
        scheme: customScheme,
        host: customSchemeHost,
        path: '/$kind/${Uri.encodeComponent(id)}',
      );
}
