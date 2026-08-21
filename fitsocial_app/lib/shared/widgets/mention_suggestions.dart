import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_palette.dart';
import '../../app/theme/app_spacing.dart';
import '../../features/auth/domain/username.dart';
import '../../features/main/application/content_providers.dart';
import '../../features/main/domain/app_models.dart';
import '../../features/main/domain/mentions.dart';
import 'avatar.dart';
import '../../shared/widgets/liquid_glass.dart';

/// The account picker that opens while an `@` is being typed.
///
/// Deliberately a sibling of the field rather than a floating overlay: the two
/// places that need it — the comment bar pinned above the keyboard, and the
/// caption box on the compose page — want the list on opposite sides of the
/// input, and an overlay would have to be told which. As a plain widget the
/// host simply puts it where it belongs and the layout does the rest.
///
/// Draws nothing at all when the cursor is not inside a handle, so it can be
/// placed unconditionally.
class MentionSuggestions extends ConsumerStatefulWidget {
  const MentionSuggestions({
    required this.controller,
    required this.focusNode,
    this.maxHeight = 216,
    super.key,
  });

  final TextEditingController controller;

  /// Suggestions only make sense while the field is being typed in. Without
  /// this the list would hang around after the keyboard closed.
  final FocusNode focusNode;

  final double maxHeight;

  @override
  ConsumerState<MentionSuggestions> createState() => _MentionSuggestionsState();
}

class _MentionSuggestionsState extends ConsumerState<MentionSuggestions> {
  /// Long enough that typing a handle straight through costs one query rather
  /// than one per letter, short enough that the list still feels attached to
  /// the keyboard.
  static const _debounce = Duration(milliseconds: 180);

  Timer? _debounceTimer;

  /// The handle under the cursor right now — what decides whether the list is
  /// open at all, and where an accepted suggestion gets written back to.
  MentionQuery? _query;

  /// The prefix actually being queried. Trails [_query] by the debounce, which
  /// is what stops the list flickering through partial matches.
  String? _settledPrefix;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
    widget.focusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(MentionSuggestions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTextChanged);
      widget.controller.addListener(_onTextChanged);
    }
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocusChanged);
      widget.focusNode.addListener(_onFocusChanged);
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    widget.controller.removeListener(_onTextChanged);
    widget.focusNode.removeListener(_onFocusChanged);
    super.dispose();
  }

  void _onFocusChanged() {
    if (!widget.focusNode.hasFocus) _close();
  }

  void _onTextChanged() {
    final selection = widget.controller.selection;
    // A ranged selection is not a cursor: the user is selecting text, not
    // writing a name.
    if (!selection.isValid || !selection.isCollapsed) {
      _close();
      return;
    }

    final query = mentionQueryAt(widget.controller.text, selection.baseOffset);
    if (query == null) {
      _close();
      return;
    }

    setState(() => _query = query);

    // The prefix only settles once typing pauses, so the query provider isn't
    // keyed on every intermediate word.
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, () {
      if (!mounted) return;
      setState(() => _settledPrefix = query.prefix);
    });
  }

  void _close() {
    _debounceTimer?.cancel();
    if (_query == null && _settledPrefix == null) return;
    setState(() {
      _query = null;
      _settledPrefix = null;
    });
  }

  /// Writes the chosen handle over the one being typed and puts the cursor
  /// after it.
  void _accept(String username) {
    final query = _query;
    if (query == null) return;

    final completion = completeMention(widget.controller.text, query, username);
    widget.controller.value = TextEditingValue(
      text: completion.text,
      selection: TextSelection.collapsed(offset: completion.cursor),
    );
    _close();
  }

  @override
  Widget build(BuildContext context) {
    final query = _query;
    final prefix = _settledPrefix;
    if (query == null || prefix == null) return const SizedBox.shrink();

    final results = ref.watch(mentionSuggestionsProvider(prefix)).valueOrNull;
    // Nothing is drawn while the first query is in flight. A spinner here
    // would flash open and shut under the user's hands on every '@'.
    if (results == null) return const SizedBox.shrink();

    final mentionable = results.where(_isMentionable).toList(growable: false);
    if (mentionable.isEmpty) return const SizedBox.shrink();

    // Never taller than a share of what the keyboard has left. In a Scaffold's
    // bottom bar an unbounded list would push the whole bar past the top of
    // the screen, which Flutter asserts on rather than clips.
    final media = MediaQuery.of(context);
    final free = media.size.height - media.viewInsets.bottom;
    final cap = math.min(widget.maxHeight, free * 0.4);

    final palette = context.palette;
    return LiquidGlass(
      // Painted by the lens rather than by a fill of its own: a pane
      // over the app backdrop, like every other card.
      borderRadius: BorderRadius.circular(18),
      child: Container(
        constraints: BoxConstraints(maxHeight: cap),
        margin: const EdgeInsets.only(bottom: AppSpacing.xs),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: palette.stroke),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListView.builder(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: mentionable.length,
          itemBuilder: (context, index) {
            final user = mentionable[index];
            return _SuggestionTile(
              user: user,
              username: normalizeUsername(user.handle),
              onTap: _accept,
            );
          },
        ),
      ),
    );
  }

  /// Whether picking this account would actually produce a working mention.
  ///
  /// Accounts predating usernames carry a placeholder handle that no
  /// reservation backs, so inserting it would render as plain text and notify
  /// nobody. Better to leave them out of the list than to offer a dud.
  static bool _isMentionable(UserSearchResult user) {
    return validateUsernameFormat(user.handle) == null;
  }
}

class _SuggestionTile extends StatelessWidget {
  const _SuggestionTile({
    required this.user,
    required this.username,
    required this.onTap,
  });

  final UserSearchResult user;
  final String username;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return InkWell(
      onTap: () => onTap(username),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm + 2,
          vertical: 8,
        ),
        child: Row(
          children: [
            Avatar(
              initials: user.initials,
              size: 32,
              imageUrl: user.avatarUrl,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '@$username',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    user.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.muted,
                      fontSize: 12.5,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
