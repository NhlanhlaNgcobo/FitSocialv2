import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/bottom_nav.dart';
import '../../../shared/widgets/dark_card.dart';
import '../../tracking/presentation/run_drafts_section.dart';
import '../application/create_flow_controller.dart';
import '../../music/presentation/music_island_action.dart';
import '../../../shared/widgets/liquid_glass.dart';

class CreateScreen extends ConsumerWidget {
  const CreateScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final flowState = ref.watch(createFlowControllerProvider);
    final flowController = ref.read(createFlowControllerProvider.notifier);
    final actions = [
      _CreateAction(
        title: 'Log a Workout',
        subtitle: 'Track your gym session',
        icon: Icons.fitness_center_rounded,
        accent: _kWorkoutAccent,
        destination: CreateCanvasDestination.workout,
        onTap: () {
          flowController.begin(CreateCanvasDestination.workout);
          context.push(CreateCanvasDestination.workout.route);
        },
      ),
      _CreateAction(
        title: 'Log a Run',
        subtitle: 'Track your run',
        icon: Icons.directions_run_rounded,
        accent: _kRunAccent,
        destination: CreateCanvasDestination.run,
        onTap: () {
          flowController.begin(CreateCanvasDestination.run);
          context.push(CreateCanvasDestination.run.route);
        },
      ),
      _CreateAction(
        title: 'Log a Meal',
        subtitle: 'Snap a photo of your meal',
        icon: Icons.restaurant_menu_rounded,
        accent: _kMealAccent,
        destination: CreateCanvasDestination.photo,
        onTap: () {
          flowController.begin(CreateCanvasDestination.photo);
          context.push(CreateCanvasDestination.photo.route);
        },
      ),
      _CreateAction(
        title: 'Share a Post',
        subtitle: 'Share an update',
        icon: Icons.edit_square,
        accent: _kPostAccent,
        destination: CreateCanvasDestination.post,
        onTap: () {
          flowController.begin(CreateCanvasDestination.post);
          context.push(CreateCanvasDestination.post.route);
        },
      ),
      // Last, and with no create-flow destination: entering a challenge is not
      // logging something, so it starts no draft and joins no resume state. It
      // sits here because this is where a user comes when they have decided to
      // do something rather than to read.
      _CreateAction(
        title: 'Enter a Challenge',
        subtitle: 'Seven tasks. Every day. 75 days.',
        icon: Icons.whatshot_rounded,
        accent: _kChallengeAccent,
        onTap: () => context.push('/challenges'),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('What are you up to?'),
        actions: const [MusicIslandAction()],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.md + FitSocialBottomNav.clearance(context),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pick a category and start logging.',
              style: TextStyle(color: palette.muted, fontSize: 14),
            ),
            const SizedBox(height: AppSpacing.lg),
            // Above the resume card: a run that is already finished and only
            // waiting on a connection is more urgent than a form somebody
            // stopped filling in. Renders nothing when there are none.
            const RunDraftsSection(),
            if (flowState.hasDraft) ...[
              _DraftResumeCard(
                destination: flowState.activeDestination,
                onResume: () {
                  // Both read from the pre-`begin` snapshot on purpose: the
                  // route depends on what the draft holds, not on the
                  // destination that is about to become active.
                  final destination = flowState.resumeDestination;
                  final route = flowState.resumeRoute;
                  flowController.begin(destination);
                  context.push(route);
                },
                onClear: flowController.clearDrafts,
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            // A single column of full-width rows: the titles are the thing you
            // scan here, and a list keeps them all left-aligned on one edge.
            for (final action in actions) ...[
              _ActionTile(
                action: action,
                isActive: action.destination != null &&
                    action.destination == flowState.activeDestination,
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            const _YouTubeTile(),
          ],
        ),
      ),
    );
  }
}

// One accent per action, and a fixed set in both themes: these identify the
// four things you can create, the way a brand colour does, rather than describing
// a surface. Green means "meal" whichever way the app is lit.
const Color _kWorkoutAccent = AppColors.orangeBright;
const Color _kRunAccent = Color(0xFF2ECBFF);
const Color _kMealAccent = Color(0xFF31C46C);
const Color _kPostAccent = Color(0xFFB06BFF);

/// Challenges take the brand orange rather than a fifth hue. They are not a
/// category of thing to log — they are FitSocial asking something of you — and
/// the orange is how the app says so.
const Color _kChallengeAccent = AppColors.orangeBright;

/// YouTube red. Not an app accent — it identifies someone else's brand.
const Color _kYouTubeAccent = Color(0xFFFF0033);

class _ActionTile extends StatefulWidget {
  const _ActionTile({required this.action, required this.isActive});

  final _CreateAction action;
  final bool isActive;

  @override
  State<_ActionTile> createState() => _ActionTileState();
}

class _ActionTileState extends State<_ActionTile> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final action = widget.action;
    // The hue the design names, resolved for the page it lands on. Painted raw,
    // these four turn into pastel sweets on white.
    final accent = palette.accent(action.accent);

    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapCancel: () => _setPressed(false),
      onTapUp: (_) => _setPressed(false),
      onTap: action.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: LiquidGlass(
          borderRadius: BorderRadius.circular(20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: widget.isActive
                    ? accent.withValues(alpha: 0.75)
                    : palette.stroke,
                width: widget.isActive ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: palette.accentFill(action.accent),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(action.icon, color: accent, size: 24),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        action.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        action.subtitle,
                        style: TextStyle(
                          color: palette.muted,
                          fontSize: 13,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.isActive) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    'Active',
                    style: TextStyle(
                      color: accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                ],
                Icon(Icons.chevron_right_rounded, color: palette.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The FitSocial YouTube channel, shaded out until the channel is ready.
///
/// Deliberately not tappable rather than tappable-and-inert: a row that reacts
/// to a press and then does nothing reads as a bug. When the channel goes live
/// this becomes a `url_launcher` call to the channel URL and loses the dimming.
class _YouTubeTile extends StatelessWidget {
  const _YouTubeTile();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return LiquidGlass(
      // Outside the Opacity, not inside it: Opacity gives its subtree its
      // own layer, and a lens in there would sample that empty layer
      // rather than the page. Dimming the content is the intent anyway.
      borderRadius: BorderRadius.circular(20),
      child: Opacity(
        opacity: 0.55,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: palette.stroke),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  // Only the well is adjusted. The glyph keeps the exact YouTube
                  // red: it is their mark, not our accent, and deepening it for
                  // our page would misreport someone else's brand.
                  color: palette.accentFill(_kYouTubeAccent),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.smart_display_rounded,
                  color: _kYouTubeAccent,
                  size: 24,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'FitSocial on YouTube',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Workout videos and guides',
                      style: TextStyle(
                        color: palette.muted,
                        fontSize: 13,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: palette.surfaceHigh,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Coming soon',
                  style: TextStyle(
                    color: palette.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DraftResumeCard extends StatelessWidget {
  const _DraftResumeCard({
    required this.destination,
    required this.onResume,
    required this.onClear,
  });

  final CreateCanvasDestination? destination;
  final VoidCallback onResume;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return DarkCard(
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: palette.brandSoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.history_rounded,
              color: palette.brand,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  destination?.label ?? 'Draft in progress',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Resume where you left off or clear the canvas.',
                  style: TextStyle(color: palette.muted),
                ),
              ],
            ),
          ),
          TextButton(onPressed: onClear, child: const Text('Clear')),
          IconButton(
            onPressed: onResume,
            icon: const Icon(Icons.arrow_forward_rounded),
            color: palette.brand,
          ),
        ],
      ),
    );
  }
}

class _CreateAction {
  const _CreateAction({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.onTap,
    this.destination,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;

  /// The create-flow slot this tile drives, and null for a tile that starts no
  /// draft at all. Nullable rather than required so an action like entering a
  /// challenge can live in this list without pretending to be a log type.
  final CreateCanvasDestination? destination;
  final VoidCallback onTap;
}
