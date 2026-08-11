import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/app/router/pending_deep_link.dart';
import 'package:fitsocial_app/shared/links/share_links.dart';

void main() {
  group('FitSocialLinks', () {
    test('a shared post is a link to the app, not the post text', () {
      final link = FitSocialLinks.post('abc123');

      expect(link.toString(), 'https://fitsocialv2.web.app/post/abc123');
      expect(link.scheme, 'https');
    });

    test('the custom-scheme twin carries the same path', () {
      // The path is what the router matches on, so the two spellings have to
      // agree on it — see FitSocialLinks' library note.
      expect(
        FitSocialLinks.postScheme('abc123').toString(),
        'fitsocial://app/post/abc123',
      );
      expect(FitSocialLinks.postScheme('abc123').path, '/post/abc123');
    });

    test('both spellings of an incoming link resolve to the same route', () {
      expect(
        FitSocialLinks.routeFor(Uri.parse('https://fitsocialv2.web.app/post/p1')),
        '/post/p1',
      );
      expect(
        FitSocialLinks.routeFor(Uri.parse('fitsocial://app/post/p1')),
        '/post/p1',
      );
      expect(
        FitSocialLinks.routeFor(Uri.parse('https://fitsocialv2.web.app/user/u1')),
        '/user/u1',
      );
    });

    test('a trailing slash and an odd case still resolve', () {
      expect(
        FitSocialLinks.routeFor(
          Uri.parse('https://FitSocialV2.web.app/Post/p1/'),
        ),
        '/post/p1',
      );
    });

    test('links that are not ours resolve to nothing', () {
      // Another host entirely.
      expect(
        FitSocialLinks.routeFor(Uri.parse('https://example.com/post/p1')),
        isNull,
      );
      // Our host, but a page rather than a piece of content.
      expect(
        FitSocialLinks.routeFor(Uri.parse('https://fitsocialv2.web.app/privacy')),
        isNull,
      );
      // Our host, a kind we do not publish.
      expect(
        FitSocialLinks.routeFor(
          Uri.parse('https://fitsocialv2.web.app/settings/danger'),
        ),
        isNull,
      );
      // Somebody else's scheme.
      expect(FitSocialLinks.routeFor(Uri.parse('other://app/post/p1')), isNull);
    });

    test('an id that could re-enter the router as a path is refused', () {
      expect(
        FitSocialLinks.routeFor(
          Uri.parse('https://fitsocialv2.web.app/post/..%2F..%2Fsettings'),
        ),
        isNull,
      );
      expect(
        FitSocialLinks.routeFor(Uri.parse('https://fitsocialv2.web.app/post/')),
        isNull,
      );
    });
  });

  group('PendingDeepLink', () {
    test('holds a content route across whatever comes between', () {
      final pending = PendingDeepLink()..remember('/post/p1');

      expect(pending.route, '/post/p1');
      expect(pending.take(), '/post/p1');
      // Followed once: a second sign-in must not replay the same link.
      expect(pending.take(), isNull);
    });

    test('refuses to hold anything a shared link could not point at', () {
      // The parked route is replayed after sign-in, so remembering an
      // arbitrary path would let a crafted link choose where a new user lands.
      final pending = PendingDeepLink()
        ..remember('/settings')
        ..remember('/edit-profile')
        ..remember('/home');

      expect(pending.route, isNull);
    });

    test('keeps the newest link when two arrive before either is redeemed', () {
      final pending = PendingDeepLink()
        ..remember('/post/p1')
        ..remember('/user/u9');

      expect(pending.take(), '/user/u9');
    });
  });
}
