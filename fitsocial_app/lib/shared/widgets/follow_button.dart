import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_palette.dart';
import '../../features/main/application/content_providers.dart';

/// How a [FollowButton] is shaped.
enum FollowButtonShape {
  /// Full-width with a soft corner radius, for lists and sheets.
  block,

  /// Pill, sized to its label, for the profile header.
  pill,
}

/// Follow / Unfollow toggle for another user. Hides itself on the signed-in
/// user's own profile, since you can't follow yourself.
class FollowButton extends ConsumerStatefulWidget {
  const FollowButton({
    required this.targetUserId,
    this.shape = FollowButtonShape.block,
    super.key,
  });

  final String targetUserId;
  final FollowButtonShape shape;

  @override
  ConsumerState<FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends ConsumerState<FollowButton> {
  bool _isPending = false;

  Future<void> _toggle(bool isFollowing) async {
    setState(() => _isPending = true);
    try {
      await ref
          .read(followActionsProvider)
          .toggle(widget.targetUserId, isFollowing: isFollowing);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isFollowing
                ? "Couldn't unfollow: $error"
                : "Couldn't follow: $error",
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isPending = false);
    }
  }

  bool get _isPill => widget.shape == FollowButtonShape.pill;

  @override
  Widget build(BuildContext context) {
    final currentUserId = ref.watch(currentUserIdProvider);
    if (currentUserId == null || currentUserId == widget.targetUserId) {
      return const SizedBox.shrink();
    }

    final isFollowing =
        ref.watch(isFollowingProvider(widget.targetUserId)).valueOrNull ??
            false;

    final palette = context.palette;
    final radius = BorderRadius.circular(_isPill ? 999 : 16);
    final padding = _isPill
        ? const EdgeInsets.symmetric(horizontal: 40, vertical: 12)
        : EdgeInsets.zero;

    final child = _isPending
        // Follow is an orange fill, Following is an outline on the app's own
        // surface — so the spinner cannot use one colour for both.
        ? _ButtonSpinner(
            color: isFollowing ? palette.text : AppColors.onBrand,
          )
        : Text(
            isFollowing ? 'Following' : 'Follow',
            style: const TextStyle(fontWeight: FontWeight.w700),
          );

    final button = isFollowing
        ? OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: palette.text,
              // Following reads as the settled state, so it steps back to a
              // grey outline rather than competing with the orange.
              backgroundColor: _isPill ? palette.surfaceHigh : null,
              side: BorderSide(color: palette.stroke),
              padding: padding,
              shape: RoundedRectangleBorder(borderRadius: radius),
            ),
            onPressed: _isPending ? null : () => _toggle(true),
            child: child,
          )
        : FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor:
                  _isPill ? AppColors.orangeBright : AppColors.orange,
              foregroundColor: AppColors.onBrand,
              padding: padding,
              shape: RoundedRectangleBorder(borderRadius: radius),
            ),
            onPressed: _isPending ? null : () => _toggle(false),
            child: child,
          );

    if (_isPill) return button;
    return SizedBox(width: double.infinity, height: 48, child: button);
  }
}

class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(strokeWidth: 2, color: color),
    );
  }
}
