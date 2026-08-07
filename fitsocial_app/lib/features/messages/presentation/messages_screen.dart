import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';

/// Direct messages.
///
/// The inbox is here and reachable; the conversation store behind it is not
/// built yet, so there is nothing to list. This deliberately shows an empty
/// state rather than mock threads — a fake inbox is worse than an honest one,
/// because every tap on it dead-ends.
class MessagesScreen extends ConsumerWidget {
  const MessagesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    return Scaffold(
      appBar: AppBar(title: const Text('Messages')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: palette.surfaceHigh,
                ),
                child: const Icon(
                  Icons.mail_outline_rounded,
                  size: 48,
                  color: AppColors.orangeBright,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'No messages yet',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: palette.text,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Direct messages are on the way. Until then, find people in '
                'Explore and follow what they post.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: palette.muted,
                  fontSize: 15,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: palette.text,
                  side: BorderSide(color: palette.stroke),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                onPressed: () => context.go('/explore'),
                icon: const Icon(Icons.person_search_outlined),
                label: const Text('Find people'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
