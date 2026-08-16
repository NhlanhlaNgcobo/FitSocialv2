import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_palette.dart';
import '../../app/theme/app_spacing.dart';
import '../../core/connectivity/backend_reachability.dart';

/// A slim strip along the top of the app while the backend is unreachable.
///
/// Says what still works rather than only what doesn't. Everything the user
/// logs offline is written to the local cache and syncs on its own, so the
/// honest message is "carry on", not "something is broken".
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOffline = ref.watch(isOfflineProvider);
    final palette = context.palette;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      // Slides down from behind the status bar rather than fading in place —
      // a bar that appears mid-screen reads as content, not as chrome.
      transitionBuilder: (child, animation) => SizeTransition(
        sizeFactor: animation,
        alignment: Alignment.topCenter,
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: !isOffline
          ? const SizedBox.shrink()
          : Material(
              color: palette.surfaceHigh,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.cloud_off_rounded,
                        size: 16,
                        color: palette.muted,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          "You're offline — anything you log will sync later.",
                          style: TextStyle(
                            color: palette.muted,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
