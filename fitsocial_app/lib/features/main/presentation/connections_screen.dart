import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/avatar.dart';
import '../../../shared/widgets/follow_button.dart';
import '../../../shared/widgets/liquid_glass.dart';
import '../application/content_providers.dart';
import '../domain/app_models.dart';

/// The people behind the two numbers on your own profile.
///
/// Yours and only yours. There is no user id on the route and none on the
/// provider behind it: the list is read for whoever is signed in, so there is
/// no address that could name somebody else's followers. The profile stats bar
/// makes the same promise on the way in by only being tappable on your own
/// profile, and the security rules make it again on the server.
class ConnectionsScreen extends StatelessWidget {
  const ConnectionsScreen({required this.initialKind, super.key});

  final FollowListKind initialKind;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: FollowListKind.values.length,
      initialIndex: initialKind.index,
      child: Scaffold(
        appBar: AppBar(title: const Text('Your circle')),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              const SizedBox(height: AppSpacing.sm),
              const _KindSwitch(),
              const SizedBox(height: AppSpacing.md),
              Expanded(
                child: TabBarView(
                  children: [
                    for (final kind in FollowListKind.values)
                      _ConnectionsList(kind: kind),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Two segments, each half the width, above the lists.
///
/// Built off the tab controller's animation rather than its index, like the
/// profile's own section indicator: the highlight follows a swipe across
/// instead of snapping once the page settles.
class _KindSwitch extends StatelessWidget {
  const _KindSwitch();

  @override
  Widget build(BuildContext context) {
    final controller = DefaultTabController.of(context);
    final animation = controller.animation;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: AnimatedBuilder(
        // The controller stands in on the frame before its animation is
        // attached — it is a Listenable in its own right.
        animation: animation ?? controller,
        builder: (context, _) {
          final position = animation?.value ?? controller.index.toDouble();
          return Row(
            children: [
              for (var i = 0; i < FollowListKind.values.length; i++) ...[
                if (i > 0) const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _KindSegment(
                    kind: FollowListKind.values[i],
                    // 1 when this segment's page fills the screen, 0 once it
                    // is a full page away.
                    selection: (1 - (position - i).abs()).clamp(0.0, 1.0),
                    onTap: () => controller.animateTo(i),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _KindSegment extends ConsumerWidget {
  const _KindSegment({
    required this.kind,
    required this.selection,
    required this.onTap,
  });

  final FollowListKind kind;

  /// How selected this segment is, 0 to 1. A partial value is a swipe in
  /// progress rather than a state of its own.
  final double selection;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    // The list itself is the count: a stored counter that has drifted from the
    // edges would put a number on the tab that the rows below it contradict.
    // Nothing is shown until the list is in hand.
    final count = ref.watch(followListProvider(kind)).valueOrNull?.length;
    final label = count == null ? kind.label : '${kind.label}  $count';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Color.lerp(palette.surface, palette.brand, selection),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: Color.lerp(palette.stroke, palette.brand, selection)!,
          ),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            // Dark ink on the orange, page colour off it — the selected pill
            // is the same orange in both themes, so this cannot be themed.
            color: Color.lerp(palette.text, AppColors.onBrandInk, selection),
          ),
        ),
      ),
    );
  }
}

class _ConnectionsList extends ConsumerWidget {
  const _ConnectionsList({required this.kind});

  final FollowListKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final people = ref.watch(followListProvider(kind));

    return people.when(
      loading: () => Center(
        child: CircularProgressIndicator(color: palette.brand),
      ),
      error: (_, __) => _ConnectionsMessage(
        icon: Icons.cloud_off_rounded,
        title: "Couldn't load your ${kind.label.toLowerCase()}",
        message: 'Check your connection and try again.',
        onRetry: () => ref.invalidate(followListProvider(kind)),
      ),
      data: (people) {
        if (people.isEmpty) {
          return _ConnectionsMessage(
            icon: kind == FollowListKind.followers
                ? Icons.group_outlined
                : Icons.person_search_outlined,
            title: kind.emptyTitle,
            message: kind.emptyMessage,
          );
        }

        return RefreshIndicator(
          color: palette.brand,
          backgroundColor: palette.surface,
          onRefresh: () async => ref.invalidate(followListProvider(kind)),
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              AppSpacing.xl,
            ),
            itemCount: people.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) =>
                _ConnectionTile(user: people[index]),
          ),
        );
      },
    );
  }
}

/// One person, with the follow control on the trailing edge.
///
/// The row is the same pane Explore's search results use, so a person looks
/// the same wherever the app lists them. The button is what makes this more
/// than a directory: the following tab is where an unfollow is most often
/// made, and it belongs on the row rather than two screens away.
class _ConnectionTile extends StatelessWidget {
  const _ConnectionTile({required this.user});

  final UserSearchResult user;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.card),
      onTap: () => context.push('/user/${user.id}'),
      child: LiquidGlass(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: palette.stroke),
          ),
          child: Row(
            children: [
              Avatar(
                initials: user.initials,
                size: 48,
                imageUrl: user.avatarUrl,
                border: AvatarBorder.none,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      user.handle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: palette.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              // Draws nothing on your own row, which is the only way you can
              // appear in one of these lists.
              FollowButton(
                targetUserId: user.id,
                shape: FollowButtonShape.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A whole-page empty or error state, centred while there is room.
class _ConnectionsMessage extends StatelessWidget {
  const _ConnectionsMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: palette.muted, size: 42),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: palette.text,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: palette.muted, fontSize: 15),
                  ),
                  if (onRetry != null) ...[
                    const SizedBox(height: AppSpacing.lg),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: palette.text,
                        side: BorderSide(color: palette.stroke),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      onPressed: onRetry,
                      child: const Text('Retry'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
