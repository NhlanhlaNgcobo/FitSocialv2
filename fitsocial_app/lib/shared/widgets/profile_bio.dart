import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_palette.dart';
import '../../app/theme/app_spacing.dart';

/// Everything a profile says about itself in words: the bio, the pronouns and
/// location beside it, and the link the user put on their profile.
///
/// One widget rather than four, because the pieces only make sense stacked in
/// this order and both profile screens stack them the same way. Renders nothing
/// when every field is empty, so the caller doesn't leave a gap where an empty
/// profile's text would have been.
class ProfileBio extends StatelessWidget {
  const ProfileBio({
    this.bio = '',
    this.pronouns = '',
    this.location = '',
    this.links = '',
    super.key,
  });

  final String bio;

  /// How the user asks to be referred to. Shown on the meta line beside the
  /// location, since neither is a sentence of its own.
  final String pronouns;

  final String location;

  /// The link the user added to their profile, as they typed it — with or
  /// without a scheme.
  final String links;

  bool get isEmpty =>
      bio.trim().isEmpty &&
      pronouns.trim().isEmpty &&
      location.trim().isEmpty &&
      links.trim().isEmpty;

  /// Pronouns and location on one line. Either can be absent, so the separator
  /// is only earned when both are present.
  String get _meta => [pronouns.trim(), location.trim()]
      .where((part) => part.isNotEmpty)
      .join('  ·  ');

  @override
  Widget build(BuildContext context) {
    if (isEmpty) return const SizedBox.shrink();

    final palette = context.palette;
    final text = bio.trim();
    final meta = _meta;
    final link = links.trim();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        children: [
          if (text.isNotEmpty)
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.text,
                fontSize: 15,
                height: 1.45,
              ),
            ),
          if (meta.isNotEmpty) ...[
            if (text.isNotEmpty) const SizedBox(height: AppSpacing.sm),
            Text(
              meta,
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.muted, fontSize: 14),
            ),
          ],
          if (link.isNotEmpty) ...[
            if (text.isNotEmpty || meta.isNotEmpty)
              const SizedBox(height: AppSpacing.sm),
            _ProfileLink(url: link),
          ],
        ],
      ),
    );
  }
}

/// The profile's link, shown the way a browser shows one — no scheme, no
/// trailing slash — and copied to the clipboard when tapped.
///
/// Copy rather than open: opening it would mean handing an arbitrary
/// user-supplied URL to the platform, and nothing in the app launches external
/// URLs yet. Copying keeps the link useful without that.
class _ProfileLink extends StatelessWidget {
  const _ProfileLink({required this.url});

  final String url;

  /// What the user reads. The scheme is noise on a profile, and a bare trailing
  /// slash is the same page as no slash.
  static String display(String url) {
    var text = url.trim().replaceFirst(RegExp(r'^[a-zA-Z][\w+.-]*://'), '');
    if (text.endsWith('/')) text = text.substring(0, text.length - 1);
    return text;
  }

  /// What gets copied. A link typed as "example.com" is still a link, so the
  /// scheme is put back on the way out rather than demanded on the way in.
  static String canonical(String url) {
    final text = url.trim();
    return RegExp(r'^[a-zA-Z][\w+.-]*://').hasMatch(text)
        ? text
        : 'https://$text';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () => _copy(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.link_rounded,
              size: 16,
              color: palette.brand,
            ),
            const SizedBox(width: 6),
            // Bounded so a long URL ellipsises instead of overflowing the row,
            // which a Row of intrinsic-width children otherwise would.
            Flexible(
              child: Text(
                display(url),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  // A 14px link label, so it takes the text-weight orange
                  // rather than the fill one.
                  color: palette.brandText,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copy(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: canonical(url)));
    messenger.showSnackBar(const SnackBar(content: Text('Link copied.')));
  }
}
