import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/theme/app_palette.dart';
import '../../app/theme/app_spacing.dart';

/// The controls that choose the photo behind a workout or a run card.
///
/// Only the buttons: what the chosen photo looks like is the caller's business,
/// because the two screens preview it differently — a workout shows the photo
/// under the scrim its card will apply, and a run shows the finished run card
/// itself, line and numbers and all.
class BackgroundPickerRow extends StatelessWidget {
  const BackgroundPickerRow({
    required this.onPick,
    required this.onRemove,
    this.hasImage = false,
    super.key,
  });

  /// Given the source the user chose. Null while a save is in flight, which
  /// disables the buttons.
  final ValueChanged<ImageSource>? onPick;

  /// Clears the current choice. Only reachable once [hasImage] is true.
  final VoidCallback? onRemove;

  final bool hasImage;

  @override
  Widget build(BuildContext context) {
    final pick = onPick;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _BackgroundAction(
                icon: Icons.photo_library_rounded,
                label: hasImage ? 'Replace' : 'Gallery',
                onTap: pick == null ? null : () => pick(ImageSource.gallery),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _BackgroundAction(
                icon: Icons.photo_camera_rounded,
                label: 'Camera',
                onTap: pick == null ? null : () => pick(ImageSource.camera),
              ),
            ),
          ],
        ),
        // Only offered once there is something to take away, so the row doesn't
        // carry a permanently dead third button.
        if (hasImage) ...[
          const SizedBox(height: AppSpacing.xs),
          TextButton.icon(
            onPressed: onRemove,
            style: TextButton.styleFrom(
              foregroundColor: context.palette.muted,
            ),
            icon: const Icon(Icons.close_rounded, size: 16),
            label: const Text('Remove photo'),
          ),
        ],
      ],
    );
  }
}

class _BackgroundAction extends StatelessWidget {
  const _BackgroundAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Material(
      color: palette.surfaceHigh,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: context.palette.brand),
              const SizedBox(width: AppSpacing.sm),
              Text(
                label,
                style: TextStyle(
                  color: palette.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
