import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_palette.dart';
import '../../features/main/application/content_providers.dart';
import '../../features/main/data/content_repository.dart';
import '../../features/main/domain/app_models.dart';
import 'quick_toast.dart';

/// The bodies of the posts that ask something of whoever reads them: a poll
/// to vote in, a session to join. Both read their live state from the post
/// itself, so a vote or an RSVP from somebody else shows up while the card is
/// on screen — watching a poll move is half of why people come back to it.

/// A poll: the question, then its answers as bars once there's a vote to show.
///
/// Results stay hidden until the viewer has voted, so the first tap is an
/// honest answer rather than a vote for whatever is winning. The author sees
/// them from the start — it's their question.
class PollCard extends ConsumerStatefulWidget {
  const PollCard({
    required this.postId,
    required this.authorId,
    required this.question,
    required this.poll,
    this.margin = EdgeInsets.zero,
    super.key,
  });

  final String postId;
  final String authorId;
  final String question;

  /// The poll as the feed loaded it. Stands in until the live copy arrives.
  final PostPoll poll;
  final EdgeInsetsGeometry margin;

  @override
  ConsumerState<PollCard> createState() => _PollCardState();
}

class _PollCardState extends ConsumerState<PollCard> {
  /// The viewer's tap, shown before the write lands.
  PostPoll? _optimistic;

  Future<void> _vote(String userId, PostPoll current, int option) async {
    // Tapping your own answer takes the vote back.
    final next = current.voteOf(userId) == option ? null : option;
    HapticFeedback.selectionClick();
    setState(() => _optimistic = current.withVote(userId, next));
    try {
      await ref
          .read(contentRepositoryProvider)
          .setPollVote(widget.postId, userId, next);
    } catch (error) {
      debugPrint('Voting failed: $error');
      if (mounted) {
        showQuickToast(
          context,
          "Couldn't save your vote. Try again.",
          icon: Icons.error_outline_rounded,
          tone: ToastTone.danger,
        );
      }
    } finally {
      if (mounted) setState(() => _optimistic = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final viewerId = ref.watch(currentUserIdProvider);
    final live = ref.watch(livePostProvider(widget.postId)).valueOrNull?.poll;
    final poll = _optimistic ?? live ?? widget.poll;
    final mine = poll.voteOf(viewerId);
    final showResults = mine != null || viewerId == widget.authorId;

    final total = poll.total;
    final footer = [
      total == 1 ? '1 vote' : '$total votes',
      if (mine != null) 'Tap your answer to take it back',
      if (mine == null && viewerId != widget.authorId) 'Tap to vote',
    ].join(' · ');

    return Padding(
      padding: widget.margin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.question,
            style: TextStyle(
              color: palette.text,
              fontSize: 17,
              height: 1.3,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < poll.options.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _PollOption(
                label: poll.options[i],
                share: poll.shareOf(i),
                showResults: showResults,
                isMine: mine == i,
                isLeading: showResults &&
                    total > 0 &&
                    poll.countFor(i) ==
                        [
                          for (var j = 0; j < poll.options.length; j++)
                            poll.countFor(j),
                        ].reduce((a, b) => a > b ? a : b),
                onTap: viewerId == null ? null : () => _vote(viewerId, poll, i),
              ),
            ),
          Text(
            footer,
            style: TextStyle(color: palette.muted, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

class _PollOption extends StatelessWidget {
  const _PollOption({
    required this.label,
    required this.share,
    required this.showResults,
    required this.isMine,
    required this.isLeading,
    required this.onTap,
  });

  final String label;
  final double share;
  final bool showResults;
  final bool isMine;
  final bool isLeading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final percent = '${(share * 100).round()}%';
    final radius = BorderRadius.circular(14);

    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: isMine ? palette.brand : palette.stroke,
              width: isMine ? 1.5 : 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: Stack(
              children: [
                if (showResults)
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: AnimatedFractionallySizedBox(
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeOutCubic,
                        widthFactor: share.clamp(0, 1),
                        heightFactor: 1,
                        child: ColoredBox(
                          color: isLeading || isMine
                              ? palette.brandSoft
                              : palette.surfaceHigh,
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          style: TextStyle(
                            color: palette.text,
                            fontSize: 14.5,
                            fontWeight:
                                isMine ? FontWeight.w800 : FontWeight.w600,
                          ),
                        ),
                      ),
                      if (isMine) ...[
                        const SizedBox(width: 6),
                        Icon(
                          Icons.check_circle_rounded,
                          size: 18,
                          color: palette.brand,
                        ),
                      ],
                      if (showResults) ...[
                        const SizedBox(width: 8),
                        Text(
                          percent,
                          style: TextStyle(
                            color: palette.text,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Join me": what, when, where, who's in, and the button that makes it you.
///
/// Drawn as the post's media on a fixed green, like the milestone card, so it
/// reads as an invitation at a glance rather than one more paragraph.
class MeetupCard extends ConsumerStatefulWidget {
  const MeetupCard({
    required this.postId,
    required this.authorId,
    required this.meetup,
    this.margin = EdgeInsets.zero,
    super.key,
  });

  final String postId;
  final String authorId;

  /// The meetup as the feed loaded it. Stands in until the live copy arrives.
  final PostMeetup meetup;
  final EdgeInsetsGeometry margin;

  /// "You + Thabo and 2 others are in", "Nobody in yet — be the first", …
  /// Static so the wording can be tested without a card.
  static String whoLine({
    required int goingCount,
    required bool viewerGoing,
    required bool viewerHosting,
    required String? featuredName,
    required bool over,
  }) =>
      _whoLine(
        goingCount: goingCount,
        viewerGoing: viewerGoing,
        viewerHosting: viewerHosting,
        featuredName: featuredName,
        over: over,
      );

  @override
  ConsumerState<MeetupCard> createState() => _MeetupCardState();
}

class _MeetupCardState extends ConsumerState<MeetupCard> {
  PostMeetup? _optimistic;

  Future<void> _toggle(String userId, PostMeetup current) async {
    final going = !current.isGoing(userId);
    HapticFeedback.lightImpact();
    setState(() => _optimistic = current.withRsvp(userId, going: going));
    try {
      await ref
          .read(contentRepositoryProvider)
          .setMeetupRsvp(widget.postId, userId, going: going);
    } catch (error) {
      debugPrint('RSVP failed: $error');
      if (mounted) {
        showQuickToast(
          context,
          "Couldn't save that. Try again.",
          icon: Icons.error_outline_rounded,
          tone: ToastTone.danger,
        );
      }
    } finally {
      if (mounted) setState(() => _optimistic = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewerId = ref.watch(currentUserIdProvider);
    final live = ref.watch(livePostProvider(widget.postId)).valueOrNull?.meetup;
    final meetup = _optimistic ?? live ?? widget.meetup;
    final now = DateTime.now();
    final over = meetup.isOver(now);
    final isHost = viewerId == widget.authorId;
    final isGoing = meetup.isGoing(viewerId);

    final following = ref.watch(followingIdsProvider).valueOrNull ?? const {};
    final others = meetup.going.where((id) => id != viewerId).toList();
    final featuredId = others.isEmpty
        ? null
        : others.firstWhere(following.contains, orElse: () => others.first);
    final featuredName = featuredId == null
        ? null
        : ref.watch(displayNameProvider(featuredId)).valueOrNull;

    return Container(
      margin: widget.margin,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x38F7F7F7)),
        gradient: LinearGradient(
          colors: over
              ? const [Color(0xFF3A3F45), Color(0xFF111315)]
              : const [Color(0xFF14B87A), Color(0xFF05301F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            over ? 'HAPPENED' : 'JOIN ME',
            style: const TextStyle(
              color: AppColors.onMedia,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            meetup.title,
            style: const TextStyle(
              color: AppColors.onMedia,
              fontSize: 21,
              fontWeight: FontWeight.w900,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 10),
          _DetailRow(
            icon: Icons.schedule_rounded,
            text: PostMeetup.whenLabel(meetup.startsAt, now),
          ),
          if (meetup.place.isNotEmpty) ...[
            const SizedBox(height: 6),
            _DetailRow(icon: Icons.place_outlined, text: meetup.place),
          ],
          if (meetup.note.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              meetup.note,
              style: const TextStyle(
                color: Color(0xE6F7F7F7),
                fontSize: 14,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Text(
            MeetupCard.whoLine(
              goingCount: meetup.going.length,
              viewerGoing: isGoing,
              viewerHosting: isHost,
              featuredName: featuredName,
              over: over,
            ),
            style: const TextStyle(
              color: AppColors.onMedia,
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (!over && !isHost && viewerId != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: isGoing
                  ? OutlinedButton.icon(
                      onPressed: () => _toggle(viewerId, meetup),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.onMedia,
                        side: const BorderSide(color: Color(0x99F7F7F7)),
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text(
                        "You're in",
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    )
                  : FilledButton(
                      onPressed: () => _toggle(viewerId, meetup),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.onMedia,
                        foregroundColor: const Color(0xFF05301F),
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text(
                        "I'm in",
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

String _whoLine({
  required int goingCount,
  required bool viewerGoing,
  required bool viewerHosting,
  required String? featuredName,
  required bool over,
}) {
  if (over) {
    if (goingCount == 0) return 'Nobody joined this one';
    return goingCount == 1 ? '1 person joined' : '$goingCount people joined';
  }
  if (goingCount == 0) {
    return viewerHosting
        ? "You're hosting · Nobody's in yet"
        : 'Nobody in yet — be the first';
  }

  final others = goingCount - (viewerGoing ? 1 : 0);
  final parts = <String>[];
  if (viewerHosting) parts.add("You're hosting ·");
  if (viewerGoing) parts.add('You');
  if (others > 0) {
    final named = featuredName != null;
    final rest = others - (named ? 1 : 0);
    final crowd = [
      if (named) featuredName,
      if (rest > 0) '$rest ${rest == 1 ? 'other' : 'others'}',
    ].join(' and ');
    if (viewerGoing) {
      parts.add('+ $crowd');
    } else if (!named) {
      parts.add(others == 1 ? '1 person' : '$others people');
    } else {
      parts.add(crowd);
    }
  }
  final plural = viewerGoing || others > 1;
  return '${parts.join(' ')} ${plural ? 'are' : 'is'} in';
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xCCF7F7F7)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: AppColors.onMedia,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

/// "Answering: What's your go-to post-run meal?" — above a post written as
/// an answer to the day's question, and the way through to everyone else's.
class PromptAnswerLine extends StatelessWidget {
  const PromptAnswerLine({required this.prompt, super.key});

  final PostPrompt prompt;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return GestureDetector(
      onTap: () => openPromptAnswers(context, prompt),
      behavior: HitTestBehavior.opaque,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.forum_outlined, size: 14, color: palette.brand),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Answering: ',
                    style: TextStyle(
                      color: palette.muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  TextSpan(
                    text: prompt.text,
                    style: TextStyle(color: palette.muted),
                  ),
                ],
              ),
              style: const TextStyle(fontSize: 12.5, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens everyone's answers to [prompt].
void openPromptAnswers(BuildContext context, PostPrompt prompt) {
  context.push('/prompt/${prompt.id}', extra: prompt);
}
