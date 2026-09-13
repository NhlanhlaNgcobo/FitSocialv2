import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/app/router/pending_deep_link.dart';
import 'package:fitsocial_app/shared/links/share_links.dart';

void main() {
  group('FitSocialLinks', () {
    test('the privacy policy is a plain web page on the same host', () {
      expect(
        FitSocialLinks.privacyPolicy.toString(),
        'https://fitsocialv2.web.app/privacy',
      );
    });

    test('the account-deletion link points into the policy', () {
      // Play asks for a deletion URL separately from the policy URL. It is an
      // anchor rather than a second page so the two cannot drift apart.
      expect(
        FitSocialLinks.accountDeletion.toString(),
        'https://fitsocialv2.web.app/privacy#delete',
      );
    });

    test('neither is treated as a destination inside the app', () {
      // If routeFor ever accepted these, opening the policy from Settings
      // would re-enter the app instead of reaching a browser.
      expect(FitSocialLinks.routeFor(FitSocialLinks.privacyPolicy), isNull);
      expect(FitSocialLinks.routeFor(FitSocialLinks.accountDeletion), isNull);
      expect(FitSocialLinks.isShareableRoute('/privacy'), isFalse);
    });

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

    test('a live activity link opens the viewer, and survives a sign-in', () {
      // A UUID, the shape the sharer's phone mints.
      const id = '3f2c8b1e-6a4d-4e9f-9b2a-1c5d7e8f9a0b';
      final link = FitSocialLinks.live(id);

      expect(link.toString(), 'https://fitsocialv2.web.app/live/$id');
      expect(FitSocialLinks.routeFor(link), '/live/$id');
      expect(
        FitSocialLinks.routeFor(Uri.parse('fitsocial://app/live/$id')),
        '/live/$id',
      );
      // The person at home may not have the app open, or be signed in, when
      // the link arrives. It has to be held over the sign-in like a post is.
      expect(FitSocialLinks.isShareableRoute('/live/$id'), isTrue);
      expect(FitSocialLinks.isPushRoute('/live/$id'), isTrue);
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

    test('a push may open a challenge board, a shared link may not', () {
      // The two whitelists answer different questions. A challenge board is
      // not something FitSocial hands out as a link, so an incoming URL must
      // not reach it — but a challenge invitation has to be able to.
      expect(FitSocialLinks.isPushRoute('/challenge/board/ch1'), isTrue);
      expect(FitSocialLinks.isShareableRoute('/challenge/board/ch1'), isFalse);
    });

    test('everything a shared link may open, a push may open too', () {
      expect(FitSocialLinks.isPushRoute('/post/p1'), isTrue);
      expect(FitSocialLinks.isPushRoute('/user/u1'), isTrue);
    });

    test('a push route is still a whitelist, not anywhere at all', () {
      for (final route in [
        '/settings',
        '/edit-profile',
        '/home',
        // The right shape, the wrong middle segment.
        '/challenge/settings/ch1',
        // The right prefix, the wrong depth.
        '/challenge/board',
        '/challenge/board/ch1/edit',
        // An id that could re-enter the router as another path segment.
        '/challenge/board/..%2F..%2Fsettings',
        '/challenge/board/',
      ]) {
        expect(
          FitSocialLinks.isPushRoute(route),
          isFalse,
          reason: 'push should refuse $route',
        );
      }
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

    test('a challenge board is not a shareable link, so it is never parked', () {
      // A notification can open a challenge board; a link cannot. Redeeming a
      // parked route is a redirect that replaces the stack, which is why a
      // tapped notification keeps its destination in PushTapRouter instead of
      // here — see the note on this class.
      final pending = PendingDeepLink()..remember('/challenge/board/ch1');

      expect(pending.route, isNull);
    });
  });
}
