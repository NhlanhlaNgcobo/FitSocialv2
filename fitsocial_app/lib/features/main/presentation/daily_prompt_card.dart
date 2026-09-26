import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/liquid_glass.dart';
import '../../../shared/widgets/social_post_cards.dart';
import '../application/content_providers.dart';
import '../domain/app_models.dart';

/// Today's question, above the feed.
///
/// The point is a reason to post that isn't a workout. Somebody with nothing
/// logged today can still answer "What's your go-to post-run meal?", and the
/// answers are a thread everybody has something to add to.
///
/// Once the viewer has answered, the button stops asking and starts pointing at
/// everyone else's answers — which is where the conversation is by then.
class DailyPromptCard extends ConsumerWidget {
  const DailyPromptCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final prompt = ref.watch(todaysPromptProvider);
    final viewerId = ref.watch(currentUserIdProvider);
    final answers =
        ref.watch(promptAnswersProvider(prompt.id)).valueOrNull ?? const [];
    final answered = answers.any((post) => post.authorId == viewerId);

    return LiquidGlass(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: palette.stroke),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.forum_rounded, size: 16, color: palette.brand),
                const SizedBox(width: 6),
                Text(
                  "TODAY'S QUESTION",
                  style: TextStyle(
                    color: palette.brandText,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              prompt.text,
              style: TextStyle(
                color: palette.text,
                fontSize: 17,
                height: 1.3,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: answers.isEmpty
                        ? null
                        : () => openPromptAnswers(context, prompt),
                    behavior: HitTestBehavior.opaque,
                    child: Text(
                      DailyPromptCard.answersLabel(
                        answers.length,
                        answered: answered,
                      ),
                      style: TextStyle(
                        color: palette.muted,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                answered
                    ? OutlinedButton(
                        onPressed: () => openPromptAnswers(context, prompt),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: palette.text,
                          side: BorderSide(color: palette.stroke),
                          shape: const StadiumBorder(),
                        ),
                        child: const Text('See answers'),
                      )
                    : FilledButton(
                        onPressed: () => answerPrompt(context, prompt),
                        style: FilledButton.styleFrom(
                          backgroundColor: palette.brand,
                          shape: const StadiumBorder(),
                        ),
                        child: const Text(
                          'Answer',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// "Be the first to answer", "You and 4 others answered", "12 answers".
  static String answersLabel(int count, {required bool answered}) {
    if (count == 0) return 'Be the first to answer';
    if (answered) {
      final others = count - 1;
      if (others == 0) return 'You answered';
      return 'You and $others ${others == 1 ? 'other' : 'others'} answered';
    }
    return count == 1 ? '1 answer' : '$count answers';
  }
}

/// Opens the post composer as an answer to [prompt].
void answerPrompt(BuildContext context, PostPrompt prompt) {
  context.push('/compose-post', extra: prompt);
}
