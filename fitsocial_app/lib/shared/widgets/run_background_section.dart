import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/theme/app_palette.dart';
import '../../app/theme/app_spacing.dart';
import '../../features/main/domain/app_models.dart';
import 'app_photo.dart';
import 'picture_ratio.dart';
import 'background_picker.dart';
import 'form_section_header.dart';
import 'route_sparkline.dart';
import 'run_summary_card.dart';
import 'save_run_card_row.dart' show CardActionButton;
import 'video_loop_trim_screen.dart';
import '../services/video_loop_maker.dart' show videoLoopBeside;

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
/// With a route and an [onRoutePlacementChanged], the runner can also move the
/// line off whatever it is covering: "Move route" turns the preview into an
/// editor — drag to move, pinch to resize — until they tap Done.
///
/// Shared by the manual run form and the sheet that closes a tracked run.
class RunBackgroundSection extends StatefulWidget {
  const RunBackgroundSection({
    required this.imagePath,
    required this.onPick,
    this.imageUrl,
    required this.onRemove,
    this.route = const [],
    this.previewWithoutImage = true,
    this.distanceLabel,
    this.durationLabel,
    this.paceLabel,
    this.showMap = false,
    this.onMapReady,
    this.routePlacement = RoutePlacement.centred,
    this.onRoutePlacementChanged,
    this.onVideoPicked,
    super.key,
  });

  /// Local path of the chosen photo, or null for the gradient. For a video
  /// loop this is its first frame, with the clip beside it on disk.
  final String? imagePath;

  /// Given the first frame of a newly made video loop, to keep as
  /// [imagePath]. Null leaves the Video button off.
  final ValueChanged<String>? onVideoPicked;

  /// An already-uploaded photo, shown when there is no [imagePath] — a saved
  /// run reopened in the editor.
  final String? imageUrl;

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

  /// Whether the preview draws the route on the real map. While it does, the
  /// map is the backdrop and there is no photo to pick.
  final bool showMap;

  /// The preview map's controller, for capturing it on the way out.
  final ValueChanged<GoogleMapController>? onMapReady;

  /// Where the line sits on the photo. Owned by the caller, because it goes
  /// out with the run as well as into the saved card.
  final RoutePlacement routePlacement;

  /// Null hides the Move route control — a run with no line, or a caller with
  /// nowhere to keep the answer.
  final ValueChanged<RoutePlacement>? onRoutePlacementChanged;

  @override
  State<RunBackgroundSection> createState() => _RunBackgroundSectionState();
}

class _RunBackgroundSectionState extends State<RunBackgroundSection> {
  /// Whether the preview is currently taking drags and pinches. Off by
  /// default, so the sheet around it scrolls the way a sheet should.
  bool _adjusting = false;

  @override
  void didUpdateWidget(covariant RunBackgroundSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The map took over the backdrop, or the line went away: there is nothing
    // left to move, so stop listening for it.
    if (_adjusting && !_canAdjust) _adjusting = false;
  }

  bool get _canAdjust =>
      widget.onRoutePlacementChanged != null &&
      !widget.showMap &&
      RouteSparkline.canDraw(widget.route);

  @override
  Widget build(BuildContext context) {
    final path = widget.imagePath;
    final url = widget.imageUrl;
    final photo = path != null
        ? localBackgroundImage(path)
        : url != null
            ? appPhoto(url)
            : null;
    final route = widget.route;
    final previewWithoutImage = widget.previewWithoutImage;
    final distanceLabel = widget.distanceLabel;
    final durationLabel = widget.durationLabel;
    final paceLabel = widget.paceLabel;
    final showMap = widget.showMap;
    final onMapReady = widget.onMapReady;
    final onPick = widget.onPick;
    final onRemove = widget.onRemove;
    final canAdjust = _canAdjust;
    final adjusting = _adjusting && canAdjust;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FormSectionHeader(
          icon: Icons.image_outlined,
          label: 'Background',
          hint: 'Optional',
        ),
        if (photo != null || previewWithoutImage) ...[
          RunSummaryCard(
            route: route,
            distanceLabel: distanceLabel,
            durationLabel: durationLabel,
            paceLabel: paceLabel,
            // With the map on, the preview is the live map, which is what gets
            // captured; a photo picked earlier waits for the map to go off.
            background: showMap ? null : photo,
            backgroundVideo: showMap ? null : videoLoopBeside(path),
            showMap: showMap,
            onMapReady: onMapReady,
            // Portrait, because this map is what gets captured, and the
            // posted picture is always 9:16.
            aspectRatio: showMap ? kPictureAspectRatio : null,
            routePlacement: widget.routePlacement,
            onRoutePlacementChanged:
                adjusting ? widget.onRoutePlacementChanged : null,
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        if (canAdjust && (photo != null || previewWithoutImage)) ...[
          _MoveRouteControls(
            adjusting: adjusting,
            moved: !widget.routePlacement.isCentred,
            onStart: () => setState(() => _adjusting = true),
            onDone: () => setState(() => _adjusting = false),
            onReset: () =>
                widget.onRoutePlacementChanged?.call(RoutePlacement.centred),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        // Hidden while adjusting: one job at a time, and a photo swapped
        // mid-drag would move the ground under the line.
        if (!showMap && !adjusting) ...[
          BackgroundPickerRow(
            hasImage: photo != null,
            onPick: onPick,
            onRemove: onRemove,
            onPickVideo: widget.onVideoPicked == null
                ? null
                : () async {
                    final poster = await pickVideoLoop(
                      context,
                      source: ImageSource.gallery,
                    );
                    if (poster != null) widget.onVideoPicked?.call(poster);
                  },
          ),
        ],
      ],
    );
  }
}

/// "Move route", or, while moving it, a hint and Reset / Done.
class _MoveRouteControls extends StatelessWidget {
  const _MoveRouteControls({
    required this.adjusting,
    required this.moved,
    required this.onStart,
    required this.onDone,
    required this.onReset,
  });

  final bool adjusting;

  /// Whether the line is anywhere but its default, which is all Reset is for.
  final bool moved;
  final VoidCallback onStart;
  final VoidCallback onDone;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    if (!adjusting) {
      return CardActionButton(
        icon: Icons.open_with_rounded,
        label: moved ? 'Adjust route' : 'Move route',
        working: false,
        onTap: onStart,
      );
    }

    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Drag to move the route · pinch to resize',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: palette.muted,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: CardActionButton(
                icon: Icons.center_focus_strong_rounded,
                label: 'Reset',
                working: false,
                onTap: moved ? onReset : null,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: CardActionButton(
                icon: Icons.check_rounded,
                label: 'Done',
                working: false,
                onTap: onDone,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
