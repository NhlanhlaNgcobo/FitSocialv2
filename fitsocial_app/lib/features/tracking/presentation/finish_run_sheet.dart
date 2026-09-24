import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/services/instagram_photo_picker.dart';
import '../../../shared/services/route_map_snapshot.dart';
import '../../../shared/services/run_card_exporter.dart';
import '../../../shared/widgets/confirm_destructive_sheet.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/route_sparkline.dart';
import '../../../shared/widgets/run_background_section.dart';
import '../../../shared/widgets/run_summary_card.dart';
import '../../../shared/widgets/save_run_card_row.dart';
import '../../../shared/widgets/share_to_feed_toggle.dart';
import '../../main/domain/app_models.dart';
import '../../main/presentation/tag_people_sheet.dart';
import '../../../shared/widgets/liquid_glass.dart';

/// What the runner decided on the way out of a tracked run.
class FinishRunChoice {
  const FinishRunChoice({
    required this.shareToFeed,
    this.backgroundImagePath,
    this.discard = false,
    this.showRouteMap = false,
    this.taggedUsers = const [],
  });

  /// What the sheet falls back to when it is dismissed by the system back
  /// button rather than by its own Save.
  ///
  /// Dismissing must never cost the run: the clock has already been stopped by
  /// the time this sheet opens, so there is nothing to go back to. It saves and
  /// shares, which is exactly what Finish did before the sheet existed — and
  /// without the map, which only ever goes out when the runner asked for it.
  static const dismissed = FinishRunChoice(shareToFeed: true);

  /// The runner asked for the run to be thrown away. Only ever produced by the
  /// sheet's own Discard button after a confirmation — never by dismissal.
  static const discarded = FinishRunChoice(shareToFeed: false, discard: true);

  final bool shareToFeed;

  /// True when nothing should be saved: not to the feed, not to drafts.
  final bool discard;

  /// Whether the post shows the route on the real map. Off unless the runner
  /// switched it on.
  final bool showRouteMap;

  /// Local path of the photo to sit behind the run card, or null for the
  /// gradient. With [showRouteMap] this is the picture of the map instead.
  final String? backgroundImagePath;

  /// The people tagged in the shared post. Always empty for a run going to
  /// drafts: tagging needs to search accounts, which needs a connection.
  final List<TaggedUser> taggedUsers;
}

/// The last step of a tracked run: see the card, optionally put a photo behind
/// it, and decide whether it goes to the feed.
///
/// The run is already over and already recorded when this opens, so the sheet
/// cannot be *accidentally* cancelled into losing it: dismissing saves. The
/// only way to lose the run is the Discard button at the bottom, which asks
/// first and answers [FinishRunChoice.discarded].
///
/// [saveToDrafts] only changes what the sheet *says*. Where the run actually
/// goes is the caller's decision, made before this opened and not revisited
/// while it is up.
Future<FinishRunChoice> showFinishRunSheet({
  required BuildContext context,
  required List<RoutePoint> route,
  required String distanceLabel,
  required String durationLabel,
  String? paceLabel,
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
      paceLabel: paceLabel,
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
    required this.paceLabel,
    required this.saveToDrafts,
  });

  final List<RoutePoint> route;
  final String distanceLabel;
  final String durationLabel;
  final String? paceLabel;
  final bool saveToDrafts;

  @override
  State<_FinishRunSheet> createState() => _FinishRunSheetState();
}

class _FinishRunSheetState extends State<_FinishRunSheet> {
  String? _backgroundPath;
  bool _shareToFeed = true;
  List<TaggedUser> _taggedUsers = const [];

  /// Off to start with: the map names where the run began, so it is shown
  /// only when the runner decides to show it.
  bool _showMap = false;

  /// Offline, the map has no tiles to draw and a draft has nowhere to keep
  /// the choice, so the switch is only offered to a run that posts now.
  bool get _canShowMap =>
      !widget.saveToDrafts && RouteSparkline.canDraw(widget.route);

  /// The preview's live map, while it is showing.
  GoogleMapController? _map;

  /// True while the map is being captured, so Save cannot be pressed twice.
  bool _saving = false;

  Future<void> _save() async {
    String? backgroundPath = _backgroundPath;
    if (_showMap) {
      final map = _map;
      setState(() => _saving = true);
      // The picture of the map is what the post carries. If it cannot be
      // taken, the post still records the choice and draws the map live.
      backgroundPath = map == null
          ? null
          : await captureRouteMap(
              context,
              map,
              distanceLabel: widget.distanceLabel,
              durationLabel: widget.durationLabel,
              paceLabel: widget.paceLabel,
            );
      if (!mounted) return;
    }

    Navigator.of(context).pop(
      FinishRunChoice(
        shareToFeed: _shareToFeed,
        backgroundImagePath: backgroundPath,
        showRouteMap: _showMap,
        taggedUsers: _shareToFeed ? _taggedUsers : const [],
      ),
    );
  }

  Future<void> _pickTaggedPeople() async {
    final picked = await showTagPeopleSheet(context, selected: _taggedUsers);
    if (picked == null || !mounted) return;
    setState(() => _taggedUsers = picked);
  }

  Future<void> _pickBackground(ImageSource source) async {
    final path = await InstagramPhotoPicker.pickAndCrop(
      // A card's backdrop: 9:16 by default, and the card follows
      // whichever shape the photo is cropped to.
      otherShapes: true,
      context: context,
      source: source,
    );
    if (path == null || !mounted) return;
    setState(() => _backgroundPath = path);
  }

  /// Throws the run away, after asking. The confirmation names the distance so
  /// the runner sees what they are about to lose, not just a generic "sure?".
  Future<void> _discard() async {
    final confirmed = await confirmDestructiveAction(
      context,
      title: 'Discard this run?',
      message: '${widget.distanceLabel} in ${widget.durationLabel} will not '
          'be saved. This cannot be undone.',
      confirmLabel: 'Discard',
    );
    if (!confirmed || !mounted) return;
    Navigator.of(context).pop(FinishRunChoice.discarded);
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
                  paceLabel: widget.paceLabel,
                  showMap: _showMap,
                  onMapReady: (controller) => _map = controller,
                  onPick: _pickBackground,
                  onRemove: () => setState(() => _backgroundPath = null),
                ),
                // Close to the preview rather than a full gap away: this acts
                // on the card above it, not on the decision below it.
                if (!kIsWeb && !_showMap) ...[
                  const SizedBox(height: AppSpacing.sm),
                  SaveRunCardRow(
                    card: RunCardExport(
                      route: widget.route,
                      distanceLabel: widget.distanceLabel,
                      durationLabel: widget.durationLabel,
                      paceLabel: widget.paceLabel,
                      background: _backgroundPath == null
                          ? null
                          : localBackgroundImage(_backgroundPath!),
                    ),
                  ),
                ],
                if (_canShowMap) ...[
                  const SizedBox(height: AppSpacing.lg),
                  ShareToFeedToggle(
                    value: _showMap,
                    title: 'Show map',
                    subtitle: _showMap
                        ? 'Anyone who sees this run sees where it was'
                        : 'Only the shape of your route is shared',
                    onIcon: Icons.map_outlined,
                    offIcon: Icons.route_rounded,
                    onChanged: (value) => setState(() {
                      _showMap = value;
                      // The map goes with the switch; a new one reports in.
                      if (!value) _map = null;
                    }),
                  ),
                ],
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
                if (_shareToFeed && !widget.saveToDrafts) ...[
                  const SizedBox(height: AppSpacing.md),
                  TagPeopleRow(
                    tagged: _taggedUsers,
                    onTap: _saving ? null : _pickTaggedPeople,
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                PrimaryButton(
                  icon: widget.saveToDrafts
                      ? Icons.cloud_off_rounded
                      : Icons.check_rounded,
                  // One label either way when it is going to drafts: sharing
                  // is not what this button does now, so offering "& Share"
                  // would be describing the wrong step.
                  label: _saving
                      ? 'Saving…'
                      : widget.saveToDrafts
                          ? 'Save to Drafts'
                          : _shareToFeed
                              ? 'Save Run & Share'
                              : 'Save Run',
                  onPressed: _saving ? null : _save,
                ),
                // Under the primary action and in the muted colour, so it is
                // there for the runner who wants it without competing with
                // Save for the runner who does not.
                const SizedBox(height: AppSpacing.xs),
                Center(
                  child: TextButton.icon(
                    onPressed: _discard,
                    style: TextButton.styleFrom(
                      foregroundColor: palette.muted,
                    ),
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('Discard run'),
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
