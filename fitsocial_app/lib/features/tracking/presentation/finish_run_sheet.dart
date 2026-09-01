import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/services/instagram_photo_picker.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/run_background_section.dart';
import '../../../shared/widgets/share_to_feed_toggle.dart';
import '../../main/domain/app_models.dart';
import '../../../shared/widgets/liquid_glass.dart';

/// What the runner decided on the way out of a tracked run.
class FinishRunChoice {
  const FinishRunChoice({required this.shareToFeed, this.backgroundImagePath});

  /// What the sheet falls back to when it is dismissed by the system back
  /// button rather than by its own Save.
  ///
  /// Dismissing must never cost the run: the clock has already been stopped by
  /// the time this sheet opens, so there is nothing to go back to. It saves and
  /// shares, which is exactly what Finish did before the sheet existed.
  static const dismissed = FinishRunChoice(shareToFeed: true);

  final bool shareToFeed;

  /// Local path of the photo to sit behind the run card, or null for the
  /// gradient.
  final String? backgroundImagePath;
}

/// The last step of a tracked run: see the card, optionally put a photo behind
/// it, and decide whether it goes to the feed.
///
/// The run is already over and already recorded when this opens, so the sheet
/// cannot be cancelled into losing it — every way out saves.
///
/// [saveToDrafts] only changes what the sheet *says*. Where the run actually
/// goes is the caller's decision, made before this opened and not revisited
/// while it is up.
Future<FinishRunChoice> showFinishRunSheet({
  required BuildContext context,
  required List<RoutePoint> route,
  required String distanceLabel,
  required String durationLabel,
  bool saveToDrafts = false,
}) async {
  final choice = await showModalBottomSheet<FinishRunChoice>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    builder: (context) => _FinishRunSheet(
      route: route,
      distanceLabel: distanceLabel,
      durationLabel: durationLabel,
      saveToDrafts: saveToDrafts,
    ),
  );
  return choice ?? FinishRunChoice.dismissed;
}

class _FinishRunSheet extends StatefulWidget {
  const _FinishRunSheet({
    required this.route,
    required this.distanceLabel,
    required this.durationLabel,
    required this.saveToDrafts,
  });

  final List<RoutePoint> route;
  final String distanceLabel;
  final String durationLabel;
  final bool saveToDrafts;

  @override
  State<_FinishRunSheet> createState() => _FinishRunSheetState();
}

class _FinishRunSheetState extends State<_FinishRunSheet> {
  String? _backgroundPath;
  bool _shareToFeed = true;

  Future<void> _pickBackground(ImageSource source) async {
    final path = await InstagramPhotoPicker.pickAndCrop(
      context: context,
      source: source,
    );
    if (path == null || !mounted) return;
    setState(() => _backgroundPath = path);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final media = MediaQuery.of(context);

    return LiquidGlass(
      // Over the screen it was opened from, so there is real content to bend.
      lens: true,
      // A sheet always has a page behind it, which makes it the
      // one surface guaranteed something worth bending.
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: Container(
        // Never taller than most of the screen: the card, the buttons and the
        // toggle all have to be reachable on a short phone, so the column
        // scrolls inside a bounded sheet rather than growing past the top.
        constraints: BoxConstraints(maxHeight: media.size.height * 0.9),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: AppSpacing.md),
                    decoration: BoxDecoration(
                      color: palette.stroke,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  'Nice run.',
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.saveToDrafts
                      ? "You're offline. This run is saved on your phone — "
                          'post it from Create when you\'re back.'
                      : 'This is the card that goes out. Put a photo behind it '
                          'if you like.',
                  style: TextStyle(
                    color: palette.muted,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                RunBackgroundSection(
                  imagePath: _backgroundPath,
                  route: widget.route,
                  distanceLabel: widget.distanceLabel,
                  durationLabel: widget.durationLabel,
                  onPick: _pickBackground,
                  onRemove: () => setState(() => _backgroundPath = null),
                ),
                const SizedBox(height: AppSpacing.lg),
                ShareToFeedToggle(
                  value: _shareToFeed,
                  // The choice still stands offline, it just takes effect
                  // later. Saying so keeps the toggle from promising something
                  // that will not happen for hours.
                  subtitle: widget.saveToDrafts
                      ? 'Post this run to your profile activity when you '
                          'publish it'
                      : 'Post this run to your profile activity',
                  onChanged: (value) => setState(() => _shareToFeed = value),
                ),
                const SizedBox(height: AppSpacing.lg),
                PrimaryButton(
                  icon: widget.saveToDrafts
                      ? Icons.cloud_off_rounded
                      : Icons.check_rounded,
                  // One label either way when it is going to drafts: sharing
                  // is not what this button does now, so offering "& Share"
                  // would be describing the wrong step.
                  label: widget.saveToDrafts
                      ? 'Save to Drafts'
                      : _shareToFeed
                          ? 'Save Run & Share'
                          : 'Save Run',
                  onPressed: () => Navigator.of(context).pop(
                    FinishRunChoice(
                      shareToFeed: _shareToFeed,
                      backgroundImagePath: _backgroundPath,
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
