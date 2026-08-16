import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/theme/app_palette.dart';
import '../../app/theme/app_spacing.dart';
import '../../features/main/domain/app_models.dart';
import 'background_picker.dart';
import 'run_summary_card.dart';

/// Chooses the photo behind a run, previewing the actual card the whole time.
///
/// The preview is the real [RunSummaryCard], not an approximation of one: what
/// the user is deciding is whether their numbers survive on that photo, and a
/// bright sky under the corner the time sits in is the only way to find that
/// out. It is drawn before a photo is picked too, so the gradient the card
/// falls back to is a choice rather than a surprise.
///
/// Shared by the manual run form and the sheet that closes a tracked run.
class RunBackgroundSection extends StatelessWidget {
  const RunBackgroundSection({
    required this.imagePath,
    required this.onPick,
    required this.onRemove,
    this.route = const [],
    this.distanceLabel,
    this.durationLabel,
    super.key,
  });

  /// Local path of the chosen photo, or null for the gradient.
  final String? imagePath;

  final ValueChanged<ImageSource>? onPick;
  final VoidCallback? onRemove;

  /// The trace, when this run has one. A manually entered run has no line and
  /// previews as photo, numbers and wordmark alone.
  final List<RoutePoint> route;

  final String? distanceLabel;
  final String? durationLabel;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final path = imagePath;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: palette.brandSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.image_outlined,
                  size: 16,
                  color: palette.brand,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Background',
                style: TextStyle(
                  color: palette.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                'Optional',
                style: TextStyle(color: palette.muted, fontSize: 12),
              ),
            ],
          ),
        ),
        RunSummaryCard(
          route: route,
          distanceLabel: distanceLabel,
          durationLabel: durationLabel,
          background: path == null ? null : localBackgroundImage(path),
        ),
        const SizedBox(height: AppSpacing.sm),
        BackgroundPickerRow(
          hasImage: path != null,
          onPick: onPick,
          onRemove: onRemove,
        ),
      ],
    );
  }
}
