import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/post_card.dart';
import '../application/content_providers.dart';
import '../domain/app_models.dart';
import 'comments_sheet.dart';
import 'daily_prompt_card.dart';

/// Everyone's answers to one day's question, newest first.
///
/// The question sits at the top so the answers read as a thread rather than a
/// run of unrelated posts, and the answer button stays at the bottom for
/// anybody who arrived here from somebody else's answer.
class PromptAnswersScreen extends ConsumerWidget {
  const PromptAnswersScreen({required this.prompt, super.key});

  final PostPrompt prompt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final answers = ref.watch(promptAnswersProvider(prompt.id));
    final viewerId = ref.watch(currentUserIdProvider);
    // Only today's question takes new answers; an old one is there to read.
    final isToday = ref.watch(todaysPromptProvider).id == prompt.id;
    final answered =
        answers.valueOrNull?.any((post) => post.authorId == viewerId) ?? false;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: Text(isToday ? "Today's question" : 'Answers')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(promptAnswersProvider(prompt.id).future),
        color: palette.brand,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            Text(
              prompt.text,
              style: TextStyle(
                color: palette.text,
                fontSize: 20,
                height: 1.3,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            ...answers.when(
              data: (posts) => posts.isEmpty
                  ? [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.xl,
                        ),
                        child: Text(
                          'No answers yet.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: palette.muted),
                        ),
                      ),
                    ]
                  : [
                      for (final post in posts) ...[
                        PostCard.of(
                          post,
                          onCommentTapped: () =>
                              showCommentsSheet(context, post.id),
                          onComposeTapped: () => showCommentsSheet(
                            context,
                            post.id,
                            compose: true,
                          ),
                          onDeleted: () =>
                              ref.invalidate(promptAnswersProvider(prompt.id)),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                      ],
                    ],
              loading: () => [
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: palette.brand,
                      strokeWidth: 2,
                    ),
                  ),
                ),
              ],
              error: (_, __) => [
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Text(
                    "Couldn't load the answers.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: palette.muted),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      floatingActionButton: isToday && !answered
          ? FloatingActionButton.extended(
              onPressed: () => answerPrompt(context, prompt),
              backgroundColor: palette.brand,
              icon: const Icon(Icons.edit_rounded),
              label: const Text(
                'Answer',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            )
          : null,
    );
  }
}
