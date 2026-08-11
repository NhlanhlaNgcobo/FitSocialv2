import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_palette.dart';
import '../../features/auth/domain/username.dart';
import '../../features/main/application/content_providers.dart';
import '../../features/main/data/content_repository.dart';
import '../../features/main/domain/app_models.dart';
import '../../features/main/domain/mentions.dart';
import 'quick_toast.dart';

/// A caption or a comment, with every `@handle` in it drawn as a link.
///
/// The links are parsed from the words at render time rather than read from a
/// stored list. A post's `mentionedUserIds` exists to drive notifications, not
/// to decide what the sentence looks like — if the two ever disagree, what the
/// author actually wrote has to win.
///
/// Handles are not resolved to accounts until one is tapped. Resolving on
/// render would mean a read per mention per card in the feed, to answer a
/// question nobody has asked yet; a handle nobody holds simply says so when it
/// is followed.
class MentionText extends ConsumerStatefulWidget {
  const MentionText({
    required this.text,
    this.style,
    this.leadingName,
    this.leadingUserId,
    this.leadingStyle,
    this.maxLines,
    this.overflow,
    super.key,
  });

  final String text;

  /// Style of the words themselves. The mention spans inherit it and override
  /// only colour and weight, so a link sits at the same size and leading as
  /// the sentence around it.
  final TextStyle? style;

  /// Drawn in front of [text], separated by two spaces — the Instagram caption
  /// convention of the author's name running into their own words. Null leaves
  /// the text to start on its own.
  final String? leadingName;

  /// Whose profile [leadingName] opens. Null leaves the name as plain words —
  /// which is what a caller without a uid to hand should pass, rather than a
  /// link that goes nowhere.
  ///
  /// Unlike a mention this needs no lookup: the caller already knows who wrote
  /// the words it is printing the name of.
  final String? leadingUserId;

  final TextStyle? leadingStyle;

  final int? maxLines;
  final TextOverflow? overflow;

  @override
  ConsumerState<MentionText> createState() => _MentionTextState();
}

class _MentionTextState extends ConsumerState<MentionText> {
  /// One recognizer per link, held so they can be disposed. A [TextSpan]'s
  /// recognizer is not owned by the span — dropping them on rebuild leaks the
  /// gesture arena entries.
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  /// Opens the profile behind [username], or says there isn't one.
  Future<void> _openMention(String username) async {
    final router = GoRouter.of(context);
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    final repository = ref.read(contentRepositoryProvider);

    String? userId;
    try {
      userId = await repository.resolveUsername(username);
    } catch (_) {
      // Treated as "couldn't open it" rather than "no such person": a failed
      // read must not tell the reader an account doesn't exist.
      userId = null;
    }
    if (!mounted) return;

    if (userId == null) {
      if (overlay == null) return;
      showQuickToastOn(
        overlay,
        "Couldn't open @$username",
        icon: Icons.person_off_outlined,
      );
      return;
    }
    router.push('/user/$userId');
  }

  /// The tap on [MentionText.leadingName], or null when there is nobody to
  /// send it to — no uid was given, or the name is the reader's own, which is
  /// the same rule `ProfileLink` applies to a name drawn as a widget.
  ///
  /// Called from build, so the recognizer it registers is disposed with the
  /// rest of them on the next one.
  TapGestureRecognizer? _leadingRecognizer() {
    final userId = widget.leadingUserId;
    if (userId == null ||
        userId.isEmpty ||
        userId == ref.watch(currentUserIdProvider)) {
      return null;
    }

    final recognizer = TapGestureRecognizer()
      ..onTap = () => GoRouter.of(context).push('/user/$userId');
    _recognizers.add(recognizer);
    return recognizer;
  }

  @override
  Widget build(BuildContext context) {
    // Rebuilt from scratch each time: the text can change under us (a comment
    // stream, a caption edit) and a stale recognizer would point at whoever
    // used to be named there.
    _disposeRecognizers();

    final palette = context.palette;
    final baseStyle = widget.style ?? TextStyle(color: palette.text);
    final linkStyle = baseStyle.copyWith(
      color: palette.brandText,
      fontWeight: FontWeight.w600,
    );

    final spans = <InlineSpan>[];
    final name = widget.leadingName;
    if (name != null && name.isNotEmpty) {
      spans
        ..add(
          TextSpan(
            text: name,
            style: widget.leadingStyle ??
                baseStyle.copyWith(fontWeight: FontWeight.w700),
            // Deliberately keeps the name's own styling rather than taking the
            // link colour a mention gets: this is the author of the caption
            // being named, not somebody they wrote about.
            recognizer: _leadingRecognizer(),
          ),
        )
        ..add(const TextSpan(text: '  '));
    }

    var cursor = 0;
    for (final mention in parseMentions(widget.text)) {
      if (mention.start > cursor) {
        spans.add(
          TextSpan(text: widget.text.substring(cursor, mention.start)),
        );
      }

      final recognizer = TapGestureRecognizer()
        ..onTap = () => _openMention(mention.username);
      _recognizers.add(recognizer);

      spans.add(
        TextSpan(
          text: widget.text.substring(mention.start, mention.end),
          style: linkStyle,
          recognizer: recognizer,
        ),
      );
      cursor = mention.end;
    }
    if (cursor < widget.text.length) {
      spans.add(TextSpan(text: widget.text.substring(cursor)));
    }

    return Text.rich(
      TextSpan(style: baseStyle, children: spans),
      maxLines: widget.maxLines,
      overflow: widget.overflow ?? TextOverflow.clip,
    );
  }
}

/// "with @bear and @nhlanhla" — the people attached to a post from its
/// composer, as a line under the header.
///
/// Separate from [MentionText] because these are not words the author wrote:
/// they are a stored list, already resolved to uids, so each name navigates
/// without a lookup.
class TaggedUsersLine extends StatefulWidget {
  const TaggedUsersLine({required this.tagged, super.key});

  final List<TaggedUser> tagged;

  @override
  State<TaggedUsersLine> createState() => _TaggedUsersLineState();
}

class _TaggedUsersLineState extends State<TaggedUsersLine> {
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    if (widget.tagged.isEmpty) return const SizedBox.shrink();

    final palette = context.palette;
    final baseStyle = TextStyle(fontSize: 12.5, color: palette.muted);
    final linkStyle = baseStyle.copyWith(
      color: palette.brandText,
      fontWeight: FontWeight.w600,
    );

    final spans = <InlineSpan>[const TextSpan(text: 'with ')];
    for (var i = 0; i < widget.tagged.length; i++) {
      if (i > 0) {
        // An Oxford-free "a, b and c" — the list is short by construction, so
        // the last separator is worth spelling out rather than another comma.
        spans.add(
          TextSpan(text: i == widget.tagged.length - 1 ? ' and ' : ', '),
        );
      }

      final tagged = widget.tagged[i];
      final recognizer = TapGestureRecognizer()
        ..onTap = () => context.push('/user/${tagged.id}');
      _recognizers.add(recognizer);

      // The handle where there is one, the display name where there isn't:
      // accounts predating usernames would otherwise be drawn as a bare '@'.
      final username = normalizeUsername(tagged.handle);
      spans.add(
        TextSpan(
          text: username.isEmpty ? tagged.displayName : '@$username',
          style: linkStyle,
          recognizer: recognizer,
        ),
      );
    }

    return Text.rich(
      TextSpan(style: baseStyle, children: spans),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}
