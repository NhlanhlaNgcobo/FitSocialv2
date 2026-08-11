/// What an `@` in a caption or a comment means, in one place.
///
/// Mentions are parsed out of the text rather than stored beside it, so the
/// words the author wrote and the people they named can never disagree. The
/// resolved uids *are* stored — see `mentionedUserIds` on posts and comments —
/// but only as an index for notifications; deleting that field would cost the
/// alerts, never the link.
///
/// The grammar here has to agree with [validateUsernameFormat]: a run of
/// characters that could not be a username is not a mention, however it looks.
library;

import '../../auth/domain/username.dart';

/// How many people one post or comment may notify.
///
/// Not a storage limit — a `@everyone` limit. Without a ceiling, one comment
/// listing fifty handles is fifty inbox entries, and the cheapest spam vector
/// in the app. Mentions past the cap still render as links; they just don't
/// raise a notification.
const int maxMentionsPerItem = 10;

/// Matches `@` followed by anything a username could be made of.
///
/// The lookbehind is what keeps an email address out: in `bear@example.com`
/// the `@` follows a word character, so it is punctuation in the middle of an
/// address rather than the start of a mention. Doubled `@@` is excluded on the
/// same grounds.
///
/// Deliberately looser than the username grammar — it over-matches and then
/// [MentionSpan.of] decides. Trailing punctuation is the reason: "thanks
/// @bear." has to mention `bear`, so the pattern must be allowed to swallow
/// the full stop and hand it back.
final RegExp _mentionPattern = RegExp(
  r'(?<![A-Za-z0-9._@])@([A-Za-z0-9._]+)',
);

/// Characters a username may not end on, which is exactly how a mention runs
/// into the sentence around it.
final RegExp _trailingPunctuation = RegExp(r'[._]+$');

/// One `@handle` found in a body of text.
class MentionSpan {
  const MentionSpan({
    required this.start,
    required this.end,
    required this.username,
  });

  /// Index of the `@` in the source string.
  final int start;

  /// Index just past the last character of the handle — *after* trailing
  /// punctuation has been given back to the sentence, so `[start, end)` is the
  /// run that should be drawn as a link and nothing more.
  final int end;

  /// The normalized username, without the '@'. This is the `usernames`
  /// document id, which is what makes it resolvable to an account.
  final String username;

  /// The text as it appears, '@' included.
  String get label => '@$username';

  /// The span [match] describes, or null when what follows the '@' could not
  /// be a username — `@..`, `@a`, a reserved name, or a bare '@'.
  static MentionSpan? of(RegExpMatch match) {
    final raw = match.group(1) ?? '';
    // Give back any trailing dots and underscores: they end the sentence, not
    // the handle, and a username may not close on either.
    final trimmed = raw.replaceFirst(_trailingPunctuation, '');
    if (trimmed.isEmpty) return null;

    final username = normalizeUsername(trimmed);
    if (validateUsernameFormat(username) != null) return null;

    return MentionSpan(
      start: match.start,
      // match.start is the '@'; +1 for it, then the handle that survived.
      end: match.start + 1 + trimmed.length,
      username: username,
    );
  }
}

/// Every mention in [text], in the order they were written.
///
/// The same handle written twice yields two spans — this is what the renderer
/// walks, and both occurrences have to become links. Use
/// [mentionedUsernames] for the deduplicated set.
List<MentionSpan> parseMentions(String text) {
  if (!text.contains('@')) return const [];

  final spans = <MentionSpan>[];
  for (final match in _mentionPattern.allMatches(text)) {
    final span = MentionSpan.of(match);
    if (span != null) spans.add(span);
  }
  return spans;
}

/// The distinct accounts [text] names, in first-mention order, capped at
/// [maxMentionsPerItem].
///
/// Order is preserved rather than sorted so the cap falls on the mentions the
/// author wrote last, which is the half they are least likely to have meant.
List<String> mentionedUsernames(String text) {
  final seen = <String>{};
  for (final span in parseMentions(text)) {
    seen.add(span.username);
    if (seen.length >= maxMentionsPerItem) break;
  }
  return seen.toList(growable: false);
}

/// The handle being typed at [cursor], or null when the cursor is not inside
/// one.
///
/// This is what drives the suggestion list under a composer: it answers "is
/// the user part-way through writing a mention, and if so, what have they typed
/// so far". A zero-length query (the cursor just after a bare '@') counts — the
/// list should open on the '@' itself rather than waiting for a first letter.
///
/// Returns null once the token stops being a plausible username, so typing
/// past 20 characters or into a second '@' closes the list rather than leaving
/// it hanging on a query that can never match.
MentionQuery? mentionQueryAt(String text, int cursor) {
  if (cursor < 0 || cursor > text.length) return null;

  // Walk back from the cursor to the '@' that opens this token. Anything that
  // could not appear in a username ends the search: the user has moved on.
  var index = cursor - 1;
  while (index >= 0) {
    final char = text[index];
    if (char == '@') break;
    if (!_isUsernameChar(char)) return null;
    // A token longer than a username can never resolve to one.
    if (cursor - index > usernameMaxLength) return null;
    index--;
  }
  if (index < 0) return null;

  // The same rule the parser uses: an '@' glued to a word is punctuation.
  if (index > 0 && _isWordChar(text[index - 1])) return null;

  return MentionQuery(
    start: index,
    end: cursor,
    prefix: normalizeUsername(text.substring(index + 1, cursor)),
  );
}

/// [text] with the handle under construction replaced by [username], plus
/// where to put the cursor afterwards.
///
/// A trailing space is part of the insertion on purpose: the next thing typed
/// after picking someone is a word, not more of their name, and without it the
/// suggestion list re-opens on the handle that was just completed.
MentionCompletion completeMention(
  String text,
  MentionQuery query,
  String username,
) {
  final replacement = '@$username ';
  return MentionCompletion(
    text: text.replaceRange(query.start, query.end, replacement),
    cursor: query.start + replacement.length,
  );
}

/// The partially-typed handle a composer should offer suggestions for.
class MentionQuery {
  const MentionQuery({
    required this.start,
    required this.end,
    required this.prefix,
  });

  /// Index of the '@' that opens the token.
  final int start;

  /// Where the cursor is — the end of what has been typed so far.
  final int end;

  /// What follows the '@', normalized. Empty when the cursor sits right after
  /// a bare '@'.
  final String prefix;
}

/// The result of accepting a suggestion: the new text, and where the cursor
/// belongs in it.
class MentionCompletion {
  const MentionCompletion({required this.text, required this.cursor});

  final String text;
  final int cursor;
}

bool _isUsernameChar(String char) => RegExp(r'[A-Za-z0-9._]').hasMatch(char);

bool _isWordChar(String char) => RegExp(r'[A-Za-z0-9._@]').hasMatch(char);
