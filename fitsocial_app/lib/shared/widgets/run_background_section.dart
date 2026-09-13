import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/theme/app_spacing.dart';
import '../../features/main/domain/app_models.dart';
import 'background_picker.dart';
import 'form_section_header.dart';
import 'run_summary_card.dart';

/// Chooses the photo behind a run, previewing the actual card the whole time.
///
/// The preview is the real [RunSummaryCard], not an approximation of one: what
/// the user is deciding is whether their numbers survive on that photo, and a
/// bright sky under the corner the time sits in is the only way to find that
/// out. Whether it is drawn before a photo is picked is the caller's call:
/// a tracked run previews its gradient fallback so that fallback is a choice
/// rather than a surprise, while a manually logged run has nothing but numbers
/// to show on a blank card and only previews once there is a photo.
///
/// Shared by the manual run form and the sheet that closes a tracked run.
class RunBackgroundSection extends StatelessWidget {
  const RunBackgroundSection({
    required this.imagePath,
    required this.onPick,
    required this.onRemove,
    this.route = const [],
    this.previewWithoutImage = true,
    this.distanceLabel,
    this.durationLabel,
    this.paceLabel,
    super.key,
  });

  /// Local path of the chosen photo, or null for the gradient.
  final String? imagePath;

  final ValueChanged<ImageSource>? onPick;
  final VoidCallback? onRemove;

  /// The trace, when this run has one. A manually entered run has no line and
  /// previews as photo, numbers and wordmark alone.
  final List<RoutePoint> route;

  /// Whether the card is previewed on its gradient fallback before a photo is
  /// chosen. False hides the card until there is a photo, leaving only the
  /// pick buttons under the header.
  final bool previewWithoutImage;

  final String? distanceLabel;
  final String? durationLabel;
  final String? paceLabel;

  @override
  Widget build(BuildContext context) {
    final path = imagePath;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FormSectionHeader(
          icon: Icons.image_outlined,
          label: 'Background',
          hint: 'Optional',
        ),
        if (path != null || previewWithoutImage) ...[
          RunSummaryCard(
            route: route,
            distanceLabel: distanceLabel,
            durationLabel: durationLabel,
            paceLabel: paceLabel,
            background: path == null ? null : localBackgroundImage(path),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        BackgroundPickerRow(
          hasImage: path != null,
          onPick: onPick,
          onRemove: onRemove,
        ),
      ],
    );
  }
}
