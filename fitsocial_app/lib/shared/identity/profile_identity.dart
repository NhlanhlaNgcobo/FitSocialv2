/// One rule for what stands in for a user who has no profile photo.
///
/// Lives outside the widget layer so the domain models that denormalise
/// initials onto search results and feed rows derive them the same way the
/// avatar widget does.
library;

/// The names the app writes when it does not know who someone is.
///
/// Mirrors `PublicAuthorName.fallback` and the legacy value the backfill tool
/// repairs. Both are stand-ins rather than names, so neither may be turned
/// into a monogram.
const Set<String> _placeholderNames = {
  'fitsocial member',
  'fitsocial user',
  'fitsocial',
  'user',
  'anonymous',
};

final RegExp _emailLike = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// Letters and digits, across every script — so a Cyrillic or Greek name gives
/// its own initial rather than falling through to the glyph.
final RegExp _alphanumeric = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// Initials for [name], or an empty string when there is no real name behind it.
///
/// The empty answer is the meaningful one: it is what tells `Avatar` to draw
/// the neutral person glyph instead of letters. An account installed minutes
/// ago has no display name yet, and initialising the app's own stand-in
/// produced monograms like "FM" — letters that read as some real person's
/// initials while belonging to nobody.
///
/// A single-word name gives one letter, not two: "BE" for Bear reads as a
/// two-word name abbreviated, which it isn't.
String avatarInitials(String? name) {
  final trimmed = (name ?? '').trim();
  if (trimmed.isEmpty) return '';
  if (_placeholderNames.contains(trimmed.toLowerCase())) return '';
  // An address is a credential, not a name. It should never reach the UI, but
  // records written before that was enforced still hold one.
  if (_emailLike.hasMatch(trimmed)) return '';

  final parts = trimmed
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) return '';

  final first = _leadingLetter(parts.first);
  if (parts.length == 1) return first;

  final last = _leadingLetter(parts.last);
  if (first.isEmpty) return last;
  if (last.isEmpty) return first;
  return '$first$last';
}

/// First letter or digit in [word], uppercased. Empty when it holds neither —
/// a handle like "@@@" contributes nothing rather than a stray punctuation
/// mark set in the middle of an avatar.
///
/// Walks runes rather than taking `substring(0, 1)`, which would slice a
/// surrogate pair in half and render the replacement box.
String _leadingLetter(String word) {
  for (final rune in word.runes) {
    final char = String.fromCharCode(rune);
    if (_alphanumeric.hasMatch(char)) return char.toUpperCase();
  }
  return '';
}
