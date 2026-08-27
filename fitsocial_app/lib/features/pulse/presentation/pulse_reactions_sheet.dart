import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/reactions/fit_reaction.dart';
import '../../../shared/widgets/avatar.dart';
import '../application/pulse_providers.dart';
import '../domain/pulse_models.dart';
import '../../../shared/widgets/liquid_glass.dart';

/// Who reacted to a Pulse, and with what.
///
/// Facebook's breakdown, in its shape: a tab per reaction that anyone actually
/// gave, each carrying its own count, with "All" leading. Reactions nobody chose
/// are left out rather than shown at zero — the tabs are a summary, and a row
/// of empty ones says nothing.
///
/// Open to everyone who can see the Pulse, unlike the viewers list. A reaction
/// is something you chose to put your name to; watching is not.
class FitReactionsSheet extends ConsumerStatefulWidget {
  const FitReactionsSheet({required this.pulseId, super.key});

  final String pulseId;

  @override
  ConsumerState<FitReactionsSheet> createState() => _FitReactionsSheetState();
}

class _FitReactionsSheetState extends ConsumerState<FitReactionsSheet> {
  /// Null is the "All" tab.
  FitReaction? _filter;

  @override
  Widget build(BuildContext context) {
    final reactions = ref.watch(pulseReactionsProvider(widget.pulseId));

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return LiquidGlass(
          // Over the screen it was opened from, so there is real content to bend.
          lens: true,
          // A sheet always has a page behind it, which makes it the one surface
          // in the app guaranteed something worth bending.
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: reactions.when(
            data: (records) => _content(records, scrollController),
            loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.orangeBright),
            ),
            error: (_, __) => const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: Text("Couldn't load reactions."),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _content(
    List<FitReactionRecord> records,
    ScrollController scrollController,
  ) {
    final palette = context.palette;
    final summary = summarizeFitReactions(records);

    // A reaction that no longer has any takers can't stay selected, or the sheet
    // would sit on an empty list with no tab left to leave it by.
    final chosen = _filter;
    final filter =
        (chosen != null && summary.countOf(chosen) > 0) ? chosen : null;

    final visible = filter == null
        ? records
        : records.where((record) => record.reaction == filter).toList();

    return Column(
      children: [
        const SizedBox(height: AppSpacing.sm),
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: palette.stroke,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Text(
            reactionCountLabel(summary.total),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
        ),
        if (summary.total > 0)
          _ReactionTabs(
            summary: summary,
            selected: filter,
            onSelected: (value) => setState(() => _filter = value),
          ),
        Expanded(
          child: visible.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Text(
                      'No reactions yet. Be the first.',
                      style: TextStyle(color: palette.muted),
                    ),
                  ),
                )
              : ListView.builder(
                  controller: scrollController,
                  itemCount: visible.length,
                  itemBuilder: (context, index) =>
                      _ReactorRow(record: visible[index]),
                ),
        ),
      ],
    );
  }
}

class _ReactionTabs extends StatelessWidget {
  const _ReactionTabs({
    required this.summary,
    required this.selected,
    required this.onSelected,
  });

  final FitReactionSummary summary;
  final FitReaction? selected;
  final ValueChanged<FitReaction?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        children: [
          _Tab(
            label: 'All ${summary.total}',
            isSelected: selected == null,
            onTap: () => onSelected(null),
          ),
          for (final reaction in summary.ranked)
            _Tab(
              label: '${reaction.emoji} ${summary.countOf(reaction)}',
              isSelected: selected == reaction,
              accent: reaction.accent,
              onTap: () => onSelected(reaction),
            ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.accent,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final tint = accent ?? palette.brandText;

    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color:
                isSelected ? tint.withValues(alpha: 0.18) : palette.surfaceHigh,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? tint : Colors.transparent,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? tint : palette.muted,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

class _ReactorRow extends StatelessWidget {
  const _ReactorRow({required this.record});

  final FitReactionRecord record;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return ListTile(
      onTap: () => context.push('/user/${record.userId}'),
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          Avatar(
            initials: pulseInitials(record.name),
            imageUrl: record.avatarUrl,
            size: 40,
          ),
          // Badged onto the avatar, the way Facebook marks each row — it
          // keeps the list readable when the "All" tab mixes them.
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: record.reaction.accent.withValues(alpha: 0.9),
                border: Border.all(color: palette.surface, width: 1.5),
              ),
              child: Text(
                record.reaction.emoji,
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ),
        ],
      ),
      title: Text(
        record.name,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        record.reaction.label,
        style: TextStyle(color: palette.muted, fontSize: 12),
      ),
      trailing: Text(
        pulseAgeLabel(record.reactedAt, DateTime.now()),
        style: TextStyle(color: palette.muted, fontSize: 12),
      ),
    );
  }
}
