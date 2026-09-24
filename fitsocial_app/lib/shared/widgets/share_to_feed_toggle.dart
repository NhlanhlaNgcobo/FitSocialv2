import 'package:flutter/material.dart';

import '../../app/theme/app_palette.dart';
import '../../app/theme/app_spacing.dart';

/// An animated card-style toggle used to control whether a logged
/// activity is shared to the user's feed — and, dressed with its own title and
/// icons, any other on/off choice about what a post reveals.
class ShareToFeedToggle extends StatelessWidget {
  const ShareToFeedToggle({
    required this.value,
    required this.onChanged,
    this.title = 'Share to Feed',
    this.subtitle = 'Post this to your profile activity',
    this.onIcon = Icons.public_rounded,
    this.offIcon = Icons.lock_outline_rounded,
    super.key,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String title;
  final String subtitle;
  final IconData onIcon;
  final IconData offIcon;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: value ? palette.brandSoft : palette.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: value ? palette.brand : palette.stroke,
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
                    ? palette.accentFill(palette.brand)
                    : palette.surfaceHigh,
                shape: BoxShape.circle,
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (child, animation) =>
                    ScaleTransition(scale: animation, child: child),
                child: Icon(
                  value ? onIcon : offIcon,
                  key: ValueKey(value),
                  color: value ? palette.brand : palette.muted,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(color: palette.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            Switch(
              value: value,
              activeThumbColor: palette.brand,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}
