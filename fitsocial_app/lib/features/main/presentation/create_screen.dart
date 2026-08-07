import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/bottom_nav.dart';
import '../../../shared/widgets/dark_card.dart';
import '../application/create_flow_controller.dart';

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
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('What are you up to?')),
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
              'Pick a canvas and start logging.',
              style: TextStyle(color: palette.muted, fontSize: 14),
            ),
            const SizedBox(height: AppSpacing.lg),
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
            // Two columns keeps every tile inside the thumb arc, and a square-ish
            // ratio leaves the icon room to breathe above the label.
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: AppSpacing.md,
              crossAxisSpacing: AppSpacing.md,
              childAspectRatio: 0.95,
              children: [
                for (final action in actions)
                  _ActionTile(
                    action: action,
                    isActive: action.destination != null &&
                        action.destination == flowState.activeDestination,
                  ),
              ],
            ),
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
    final accent = action.accent;

    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapCancel: () => _setPressed(false),
      onTapUp: (_) => _setPressed(false),
      onTap: action.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accent.withValues(alpha: widget.isActive ? 0.28 : 0.16),
                palette.surface,
              ],
            ),
            border: Border.all(
              color: widget.isActive
                  ? accent.withValues(alpha: 0.75)
                  : accent.withValues(alpha: 0.22),
              width: widget.isActive ? 1.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: widget.isActive ? 0.22 : 0.10),
                blurRadius: 22,
                spreadRadius: -6,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: accent.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Icon(action.icon, color: accent, size: 24),
                  ),
                  const Spacer(),
                  if (widget.isActive)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.20),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Active',
                        style: TextStyle(
                          color: accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  else
                    Icon(
                      Icons.arrow_outward_rounded,
                      size: 18,
                      color: accent.withValues(alpha: 0.55),
                    ),
                ],
              ),
              const Spacer(),
              Text(
                action.title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                action.subtitle,
                style: TextStyle(
                  color: palette.muted,
                  fontSize: 12.5,
                  height: 1.25,
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
              color: AppColors.orangeBright.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.history_rounded,
              color: AppColors.orangeBright,
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
            color: AppColors.orangeBright,
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
    required this.destination,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final CreateCanvasDestination? destination;
  final VoidCallback onTap;
}
