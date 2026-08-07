import 'package:flutter/material.dart';

import '../../app/theme/app_palette.dart';
import '../../app/theme/app_spacing.dart';

/// A profile's bio, centred, with the author's own line breaks left intact.
///
/// Renders nothing when there is neither a bio nor a location, so the caller
/// doesn't leave a gap where an empty profile's text would have been.
class ProfileBio extends StatelessWidget {
  const ProfileBio({required this.bio, this.location = '', super.key});

  final String bio;
  final String location;

  bool get isEmpty => bio.isEmpty && location.isEmpty;

  @override
  Widget build(BuildContext context) {
    if (isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        children: [
          if (bio.isNotEmpty)
            Text(
              bio,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                height: 1.45,
              ),
            ),
          if (location.isNotEmpty) ...[
            if (bio.isNotEmpty) const SizedBox(height: AppSpacing.sm),
            Text(
              location,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.palette.muted, fontSize: 14),
            ),
          ],
        ],
      ),
    );
  }
}
