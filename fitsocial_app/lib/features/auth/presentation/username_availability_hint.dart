import 'package:flutter/material.dart';

import '../../../app/theme/app_palette.dart';
import '../application/username_availability_checker.dart';
import '../domain/username.dart';

/// The one-line verdict under a username field: checking, free, or taken.
///
/// Rebuilds off the checker rather than the field, so it updates when the
/// answer arrives instead of when the next key is pressed.
class UsernameAvailabilityHint extends StatelessWidget {
  const UsernameAvailabilityHint({super.key, required this.checker});

  final UsernameAvailabilityChecker checker;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return AnimatedBuilder(
      animation: checker,
      builder: (context, _) {
        if (checker.isChecking) {
          return _HintLine(
            color: palette.muted,
            icon: null,
            text: 'Checking…',
          );
        }

        final result = checker.result;
        // Nothing typed yet, or the lookup failed. Either way there is no
        // honest thing to say, and a hint that appears only to say nothing is
        // worse than no hint.
        if (result == null) return const SizedBox(height: 20);

        final usable = result.canUse;
        return _HintLine(
          color: usable ? palette.success : palette.danger,
          icon: usable
              ? Icons.check_circle_rounded
              : Icons.error_outline_rounded,
          text: result.message ?? '',
        );
      },
    );
  }
}

class _HintLine extends StatelessWidget {
  const _HintLine({
    required this.color,
    required this.icon,
    required this.text,
  });

  final Color color;
  final IconData? icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    // Fixed height so the field below does not jump each time the verdict
    // changes length.
    return SizedBox(
      height: 20,
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// The banner shown when a username cannot be changed yet.
///
/// States the wait in the same breath as the reason. "You can change it again
/// in 9 days" alone reads as an arbitrary obstruction; naming impersonation as
/// the reason is what makes it read as protection.
class UsernameCooldownNotice extends StatelessWidget {
  const UsernameCooldownNotice({super.key, required this.remaining});

  final Duration remaining;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: palette.surfaceHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.stroke),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_clock_rounded, size: 16, color: palette.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'You can change your username again in '
              '${describeCooldownRemaining(remaining)}. '
              'Usernames are limited to one change every 14 days so nobody '
              'can pass themselves off as someone else and move on.',
              style: TextStyle(
                color: palette.muted,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
