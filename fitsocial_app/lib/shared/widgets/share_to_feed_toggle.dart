import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';

/// An animated card-style toggle used to control whether a logged
/// activity is shared to the user's feed.
class ShareToFeedToggle extends StatelessWidget {
  const ShareToFeedToggle({
    required this.value,
    required this.onChanged,
    this.subtitle = 'Post this to your profile activity',
    super.key,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: value
              ? AppColors.orangeBright.withValues(alpha: 0.12)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: value ? AppColors.orangeBright : AppColors.stroke,
            width: value ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOut,
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: value
                    ? AppColors.orangeBright.withValues(alpha: 0.2)
                    : AppColors.surfaceHigh,
                shape: BoxShape.circle,
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (child, animation) =>
                    ScaleTransition(scale: animation, child: child),
                child: Icon(
                  value ? Icons.public_rounded : Icons.lock_outline_rounded,
                  key: ValueKey(value),
                  color: value ? AppColors.orangeBright : AppColors.muted,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Share to Feed',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            Switch(
              value: value,
              activeThumbColor: AppColors.orangeBright,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}
