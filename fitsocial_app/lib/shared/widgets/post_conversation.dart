import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_palette.dart';
import '../../features/auth/application/app_session.dart';
import '../../features/main/application/content_providers.dart';
import '../../features/main/data/content_repository.dart';
import '../../features/main/domain/app_models.dart';
import '../identity/profile_identity.dart';
import '../reactions/fit_reaction.dart';
import 'avatar.dart';
import 'mention_text.dart';
import 'quick_toast.dart';

/// The social half of a feed card, in three pieces the card stacks around its
/// caption: who cheered, what people said, and a way to join in.
///
/// These exist because a card that only shows counts looks like a report. A
/// name under the reactions and two real comments under the caption show that
/// people are talking, and people join a conversation they can see far more
/// readily than one hidden behind "View all 12 comments".

/// How far the lines sit from the card's edge. Matches the card's gutter so
/// they line up with the caption.
const double _gutter = 14;

/// "🔥💪 Thabo and 3 others" — the reactions, with a face on them.
///
/// Leads with somebody the viewer follows when one of them reacted, because
/// "Lerato cheered this" means something and "4 reactions" doesn't.
class PostReactionLine extends ConsumerWidget {
  const PostReactionLine({
    required this.postId,
    required this.likes,
    required this.reactions,
    required this.reactionsBy,
    required this.likedBy,
    super.key,
  });

  final String postId;

  /// The total as the post was loaded.
  final int likes;
  final FitReactionSummary reactions;
  final Map<String, FitReaction> reactionsBy;
  final List<String> likedBy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewerId = ref.watch(currentUserIdProvider);
    final line = ReactionLineModel.from(
      likes: likes,
      reactions: reactions,
      reactionsBy: reactionsBy,
      likedBy: likedBy,
      viewerId: viewerId,
      // The reaction the viewer holds now, which moves the moment they tap —
      // the post itself is only re-read on refresh. Null while it loads, which
      // falls back to what the post was loaded with.
      live: ref.watch(postReactionProvider(postId)),
      following: ref.watch(followingIdsProvider).valueOrNull ?? const {},
    );
    if (line == null) return const SizedBox.shrink();

    final palette = context.palette;
    final featuredName = line.featuredId == null
        ? null
        : ref.watch(displayNameProvider(line.featuredId!)).valueOrNull;
    final base = TextStyle(fontSize: 13.5, height: 1.3, color: palette.text);
    final bold = base.copyWith(fontWeight: FontWeight.w700);

    return Padding(
      padding: const EdgeInsets.fromLTRB(_gutter, 0, _gutter, 2),
      child: Row(
        children: [
          _EmojiStack(emojis: line.emojis),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(children: line.spans(featuredName, base, bold)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// What the reaction line says, worked out apart from the widget so the
/// counting can be tested without one.
@visibleForTesting
class ReactionLineModel {
  const ReactionLineModel({
    required this.emojis,
    required this.viewerReacted,
    required this.othersCount,
    required this.featuredId,
  });

  /// Up to three, most given first.
  final List<String> emojis;
  final bool viewerReacted;

  /// Everyone who reacted apart from the viewer.
  final int othersCount;

  /// The one other person named on the line, or null when nobody else has
  /// reacted — or nobody can be told apart.
  final String? featuredId;

  /// Null when nobody has reacted, and there is no line to draw.
  static ReactionLineModel? from({
    required int likes,
    required FitReactionSummary reactions,
    required Map<String, FitReaction> reactionsBy,
    required List<String> likedBy,
    required String? viewerId,
    required AsyncValue<FitReaction?> live,
    required Set<String> following,
  }) {
    final stored = viewerId == null
        ? null
        : (reactionsBy[viewerId] ??
            (likedBy.contains(viewerId) ? FitReaction.defaultReaction : null));
    final mine = live.hasValue ? live.value : stored;

    // The post's own counts, with the viewer's stored reaction swapped for the
    // one they hold now.
    final counts = Map<FitReaction, int>.from(reactions.counts);
    if (stored != null) {
      final left = (counts[stored] ?? 1) - 1;
      if (left > 0) {
        counts[stored] = left;
      } else {
        counts.remove(stored);
      }
    }
    if (mine != null) counts[mine] = (counts[mine] ?? 0) + 1;

    final total = likes - (stored == null ? 0 : 1) + (mine == null ? 0 : 1);
    if (total <= 0) return null;

    final ranked = counts.keys.toList()
      ..sort((a, b) {
        final byCount = counts[b]!.compareTo(counts[a]!);
        if (byCount != 0) return byCount;
        return FitReaction.all.indexOf(a).compareTo(FitReaction.all.indexOf(b));
      });
    final emojis = ranked.take(3).map((reaction) => reaction.emoji).toList();

    final others = <String>{...likedBy, ...reactionsBy.keys}..remove(viewerId);
    final followed = others.where(following.contains);
    final featured = followed.isNotEmpty
        ? followed.first
        : (others.isEmpty ? null : others.first);

    return ReactionLineModel(
      emojis: emojis.isEmpty ? [FitReaction.defaultReaction.emoji] : emojis,
      viewerReacted: mine != null,
      othersCount: total - (mine == null ? 0 : 1),
      featuredId: featured,
    );
  }

  /// The line itself. [featuredName] is null until the name has loaded, and
  /// the line reads as a count until then rather than waiting on it.
  List<InlineSpan> spans(
    String? featuredName,
    TextStyle base,
    TextStyle bold,
  ) {
    final named = featuredName != null && othersCount > 0;
    final rest = othersCount - (named ? 1 : 0);
    final parts = <InlineSpan>[];

    void add(String text, TextStyle style) =>
        parts.add(TextSpan(text: text, style: style));

    if (viewerReacted) add('You', bold);
    if (named) {
      if (viewerReacted) add(rest > 0 ? ', ' : ' and ', base);
      add(featuredName, bold);
    }
    if (rest > 0) {
      if (parts.isNotEmpty) add(' and ', base);
      final noun = parts.isEmpty
          ? (rest == 1 ? 'person' : 'people')
          : (rest == 1 ? 'other' : 'others');
      add('$rest $noun', parts.isEmpty ? bold : base);
    }
    return parts;
  }
}

/// Up to three reaction emoji, overlapping like a row of faces.
class _EmojiStack extends StatelessWidget {
  const _EmojiStack({required this.emojis});

  final List<String> emojis;

  static const double _size = 20;
  static const double _step = 13;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SizedBox(
      width: _size + _step * (emojis.length - 1),
      height: _size,
      child: Stack(
        children: [
          for (var i = emojis.length - 1; i >= 0; i--)
            Positioned(
              left: _step * i,
              child: Container(
                width: _size,
                height: _size,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: palette.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: palette.stroke),
                ),
                child: Text(
                  emojis[i],
                  style: const TextStyle(fontSize: 11.5, height: 1),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// "View all 12 comments", then the two newest, one or two lines each.
///
/// Every line opens the full sheet: the preview is a window onto the
/// conversation, not a second place to have it.
class PostCommentPreview extends ConsumerWidget {
  const PostCommentPreview({
    required this.postId,
    required this.comments,
    this.onOpenComments,
    super.key,
  });

  final String postId;
  final int comments;
  final VoidCallback? onOpenComments;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (comments <= 0) return const SizedBox.shrink();
    final palette = context.palette;
    final preview =
        ref.watch(commentPreviewProvider(postId)).valueOrNull ?? const [];

    final showLink = comments > preview.length;
    final linkLabel =
        comments == 1 ? 'View 1 comment' : 'View all $comments comments';

    return GestureDetector(
      onTap: onOpenComments,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(_gutter, 6, _gutter, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showLink)
              Text(
                linkLabel,
                style: TextStyle(fontSize: 13, color: palette.muted),
              ),
            for (final comment in preview)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: MentionText(
                  text: comment.text,
                  leadingName: comment.authorName,
                  leadingUserId: comment.authorId,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.35,
                    color: palette.text,
                  ),
                  leadingStyle: TextStyle(
                    fontSize: 13.5,
                    height: 1.35,
                    color: palette.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The way in: your own face, "Add a comment…", and one-tap replies.
///
/// The one-tap replies are the point. Typing a comment is a decision; tapping
/// 🔥 is a reflex, and a reflex is what gets a quiet feed talking. On a
/// milestone they are words rather than emoji — "Congrats! 🎉" — because a
/// milestone is somebody's moment and deserves a sentence.
///
/// The replies are offered on other people's posts only, and go once the
/// viewer has said something: after that, the box is still there for more.
class PostQuickReply extends ConsumerStatefulWidget {
  const PostQuickReply({
    required this.postId,
    required this.authorId,
    this.isMilestone = false,
    this.onCompose,
    super.key,
  });

  final String postId;
  final String authorId;
  final bool isMilestone;

  /// Opens the full comment box with the keyboard up.
  final VoidCallback? onCompose;

  static const List<String> emojiReplies = ['🔥', '💪', '👏'];
  static const List<String> milestoneReplies = [
    'Congrats! 🎉',
    "Let's go 💪",
    'Keep it up 🔥',
  ];

  @override
  ConsumerState<PostQuickReply> createState() => _PostQuickReplyState();
}

class _PostQuickReplyState extends ConsumerState<PostQuickReply> {
  bool _sending = false;

  /// Set once a quick reply lands, so the chips step aside for the rest of the
  /// session rather than waiting on the preview to show the viewer's comment.
  bool _replied = false;

  Future<void> _send(String text) async {
    if (_sending) return;
    setState(() => _sending = true);
    HapticFeedback.lightImpact();

    try {
      await ref.read(contentRepositoryProvider).addComment(
            ref.read(appSessionProvider).profile,
            widget.postId,
            text,
          );
      if (!mounted) return;
      setState(() => _replied = true);
      ref.read(feedPostsProvider.notifier).incrementCommentCount(widget.postId);
      ref
        ..invalidate(commentPreviewProvider(widget.postId))
        ..invalidate(commentsProvider(widget.postId));
    } catch (error) {
      debugPrint('Quick reply failed: $error');
      if (mounted) {
        showQuickToast(
          context,
          "Couldn't post that. Try again.",
          icon: Icons.error_outline_rounded,
          tone: ToastTone.danger,
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final viewerId = ref.watch(currentUserIdProvider);
    final profile = ref.watch(appSessionProvider).profile;
    if (viewerId == null) return const SizedBox.shrink();

    final alreadySaidSomething = _replied ||
        (ref.watch(commentPreviewProvider(widget.postId)).valueOrNull ??
                const <Comment>[])
            .any((comment) => comment.authorId == viewerId);
    final offerReplies = viewerId != widget.authorId && !alreadySaidSomething;

    final box = GestureDetector(
      onTap: widget.onCompose,
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          Avatar(
            initials: avatarInitials(profile?.displayName),
            size: 24,
            imageUrl: profile?.avatarUrl,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Add a comment…',
              style: TextStyle(fontSize: 13, color: palette.muted),
            ),
          ),
          if (offerReplies && !widget.isMilestone)
            for (final emoji in PostQuickReply.emojiReplies)
              _ReplyChip(
                label: emoji,
                compact: true,
                onTap: _sending ? null : () => _send(emoji),
              ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(_gutter, 8, _gutter - 4, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (offerReplies && widget.isMilestone) ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final reply in PostQuickReply.milestoneReplies)
                  _ReplyChip(
                    label: reply,
                    onTap: _sending ? null : () => _send(reply),
                  ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          box,
        ],
      ),
    );
  }
}

class _ReplyChip extends StatelessWidget {
  const _ReplyChip({
    required this.label,
    required this.onTap,
    this.compact = false,
  });

  final String label;
  final VoidCallback? onTap;

  /// An emoji alone: no pill, just a comfortable target.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    if (compact) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Text(label, style: const TextStyle(fontSize: 17, height: 1.1)),
        ),
      );
    }
    return Material(
      color: palette.brandSoft,
      shape: StadiumBorder(side: BorderSide(color: palette.brandSoftStroke)),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: palette.brandText,
            ),
          ),
        ),
      ),
    );
  }
}
