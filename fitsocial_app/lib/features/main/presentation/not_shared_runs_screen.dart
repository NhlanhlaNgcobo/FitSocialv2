import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/connectivity/backend_reachability.dart';
import '../../../shared/services/instagram_photo_picker.dart';
import '../../../shared/services/route_map_snapshot.dart';
import '../../../shared/services/run_card_exporter.dart';
import '../../../shared/widgets/app_photo.dart';
import '../../../shared/widgets/confirm_destructive_sheet.dart';
import '../../../shared/widgets/dark_card.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/quick_toast.dart';
import '../../../shared/widgets/route_sparkline.dart';
import '../../../shared/widgets/run_background_section.dart';
import '../../../shared/widgets/run_summary_card.dart'
    show localBackgroundImage;
import '../../../shared/widgets/save_run_card_row.dart';
import '../../../shared/widgets/share_to_feed_toggle.dart';
import '../application/activity_actions.dart';
import '../application/content_providers.dart';
import '../domain/activity_kind.dart';
import '../domain/app_models.dart';
import '../domain/unshared_run.dart';
import 'tag_people_sheet.dart';

/// Every run, hike and ride the runner saved without posting, newest first.
///
/// Opened from their profile. Each one reopens in [UnsharedRunEditorScreen]
/// with its card as they left it, ready to post.
class NotSharedRunsScreen extends ConsumerWidget {
  const NotSharedRunsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final runs = ref.watch(unsharedRunsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Not shared')),
      body: runs.when(
        loading: () => Center(
          child: CircularProgressIndicator(color: palette.brand),
        ),
        error: (_, __) => _Message(
          icon: Icons.cloud_off_rounded,
          title: "Couldn't load your runs",
          action: OutlinedButton(
            onPressed: () => ref.invalidate(unsharedRunsProvider),
            child: const Text('Retry'),
          ),
        ),
        data: (runs) {
          if (runs.isEmpty) {
            return const _Message(
              icon: Icons.lock_outline_rounded,
              title: 'Nothing here',
              body: 'Runs you save without posting land here, so you can '
                  'post them later.',
            );
          }
          return RefreshIndicator(
            color: palette.brand,
            onRefresh: () async => ref.invalidate(unsharedRunsProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: runs.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, index) {
                final run = runs[index];
                return DarkCard(
                  onTap: () => context.push(
                    '/not-shared/${run.id}',
                    extra: run,
                  ),
                  child: Row(
                    children: [
                      _Thumbnail(run: run),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(child: _RunSummaryLine(run: run)),
                      Icon(Icons.chevron_right_rounded, color: palette.muted),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// The card editor for one unshared run: the same photo, Move route and map
/// controls as the finish sheet, picked up where the runner left them, with
/// Post at the bottom.
class UnsharedRunEditorScreen extends ConsumerStatefulWidget {
  const UnsharedRunEditorScreen({
    required this.runId,
    this.initialRun,
    super.key,
  });

  final String runId;

  /// The run as the list already loaded it. Null after a restart or a deep
  /// link, when it is looked up in the list by [runId] instead.
  final UnsharedRun? initialRun;

  @override
  ConsumerState<UnsharedRunEditorScreen> createState() =>
      _UnsharedRunEditorScreenState();
}

class _UnsharedRunEditorScreenState
    extends ConsumerState<UnsharedRunEditorScreen> {
  UnsharedRun? _run;

  /// A photo picked here, not yet uploaded.
  String? _localPhoto;

  /// Whether the photo saved with the run is still behind the card. Cleared
  /// by Remove, and by picking a new one.
  bool _keepSavedPhoto = true;

  bool _showMap = false;
  RoutePlacement _placement = RoutePlacement.centred;
  List<TaggedUser> _tagged = const [];
  GoogleMapController? _map;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final run = widget.initialRun;
    if (run != null) _adopt(run);
  }

  void _adopt(UnsharedRun run) {
    _run = run;
    _showMap = run.showRouteMap;
    _placement = run.routePlacement;
  }

  String? get _savedPhoto => _keepSavedPhoto ? _run?.imageUrl : null;

  Future<void> _pick(ImageSource source) async {
    final path = await InstagramPhotoPicker.pickAndCrop(
      otherShapes: true,
      context: context,
      source: source,
    );
    if (path == null || !mounted) return;
    setState(() {
      _localPhoto = path;
      _keepSavedPhoto = false;
    });
  }

  Future<void> _pickTagged() async {
    final picked = await showTagPeopleSheet(context, selected: _tagged);
    if (picked == null || !mounted) return;
    setState(() => _tagged = picked);
  }

  Future<void> _post(UnsharedRun run) async {
    setState(() => _busy = true);
    var backgroundPath = _localPhoto;
    if (_showMap) {
      final map = _map;
      // The picture of the map is what the post carries, as it is from the
      // finish sheet. If it cannot be taken, the post still records the
      // choice and draws the map live.
      backgroundPath = map == null
          ? null
          : await captureRouteMap(
              context,
              map,
              distanceLabel: _distanceLabel(run),
              durationLabel: formatRunElapsed(run.elapsed),
              paceLabel: run.averagePace,
            );
      if (!mounted) return;
    }

    try {
      final result = await ref.read(activityActionsProvider).shareUnsharedRun(
            UnsharedRunShare(
              run: run,
              backgroundImagePath: backgroundPath,
              keepExistingImage: !_showMap && _savedPhoto != null,
              showRouteMap: _showMap,
              routePlacement: _placement,
              taggedUsers: _tagged,
            ),
          );
      if (!mounted) return;
      showQuickToast(context, result.message, tone: ToastTone.success);
      context.pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      showQuickToast(
        context,
        "Couldn't post this run. Try again.",
        icon: Icons.error_outline_rounded,
        tone: ToastTone.danger,
      );
    }
  }

  Future<void> _delete(UnsharedRun run) async {
    final confirmed = await confirmDestructiveAction(
      context,
      title: 'Delete this ${run.kind.descriptor.singular.toLowerCase()}?',
      message: '${_distanceLabel(run)} in ${formatRunElapsed(run.elapsed)} '
          'will be removed from your history. This cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(activityActionsProvider).deleteUnsharedRun(run);
      if (!mounted) return;
      showQuickToast(context, 'Deleted');
      context.pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      showQuickToast(
        context,
        "Couldn't delete this run. Try again.",
        icon: Icons.error_outline_rounded,
        tone: ToastTone.danger,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    var run = _run;
    if (run == null) {
      // Opened without the run in hand: find it in the list.
      final runs = ref.watch(unsharedRunsProvider);
      final found = runs.valueOrNull
          ?.where((candidate) => candidate.id == widget.runId)
          .firstOrNull;
      if (found != null) {
        _adopt(found);
        run = found;
      } else {
        return Scaffold(
          appBar: AppBar(),
          body: runs.isLoading
              ? Center(child: CircularProgressIndicator(color: palette.brand))
              : const _Message(
                  icon: Icons.search_off_rounded,
                  title: 'This run is no longer here',
                  body: 'It may already have been posted or deleted.',
                ),
        );
      }
    }

    final offline = ref.watch(isOfflineProvider);
    final distance = _distanceLabel(run);
    final duration = formatRunElapsed(run.elapsed);
    final localPhoto = _localPhoto;
    final savedPhoto = _savedPhoto;
    final photo = localPhoto != null
        ? localBackgroundImage(localPhoto)
        : savedPhoto != null
            ? appPhoto(savedPhoto)
            : null;
    final noun = run.kind.descriptor.singular;

    return Scaffold(
      appBar: AppBar(
        title: Text(noun),
        actions: [
          IconButton(
            tooltip: 'Delete',
            onPressed: _busy ? null : () => _delete(run!),
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            Text(
              _dateLabel(run.startedAt),
              style: TextStyle(color: palette.muted, fontSize: 13),
            ),
            const SizedBox(height: AppSpacing.md),
            RunBackgroundSection(
              imagePath: localPhoto,
              imageUrl: savedPhoto,
              route: run.routePoints,
              distanceLabel: distance,
              durationLabel: duration,
              paceLabel: run.averagePace,
              showMap: _showMap,
              onMapReady: (controller) => _map = controller,
              onPick: _busy ? null : _pick,
              onRemove: _busy
                  ? null
                  : () => setState(() {
                        _localPhoto = null;
                        _keepSavedPhoto = false;
                      }),
              routePlacement: _placement,
              onRoutePlacementChanged: _busy
                  ? null
                  : (placement) => setState(() => _placement = placement),
            ),
            if (!kIsWeb && !_showMap) ...[
              const SizedBox(height: AppSpacing.sm),
              SaveRunCardRow(
                card: RunCardExport(
                  route: run.routePoints,
                  distanceLabel: distance,
                  durationLabel: duration,
                  paceLabel: run.averagePace,
                  background: photo,
                  routePlacement: _placement,
                ),
              ),
            ],
            if (run.hasRoute) ...[
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
                  if (!value) _map = null;
                }),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            TagPeopleRow(
              tagged: _tagged,
              onTap: _busy ? null : _pickTagged,
            ),
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(
              icon: offline ? Icons.cloud_off_rounded : Icons.send_rounded,
              label: _busy
                  ? 'Posting…'
                  : offline
                      ? "You're offline"
                      : 'Post to feed',
              onPressed: _busy || offline ? null : () => _post(run!),
            ),
          ],
        ),
      ),
    );
  }
}

/// The photo if there is one, the shape of the run if not, and a glyph for a
/// treadmill run, which has neither.
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.run});

  final UnsharedRun run;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final url = run.imageUrl;

    return Container(
      width: 56,
      height: 56,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: palette.brandSoft,
        borderRadius: BorderRadius.circular(14),
        image: url == null
            ? null
            : DecorationImage(image: appPhoto(url), fit: BoxFit.cover),
      ),
      child: url != null
          ? null
          : RouteSparkline.canDraw(run.routePoints)
              ? Padding(
                  padding: const EdgeInsets.all(6),
                  child: RouteSparkline(route: run.routePoints),
                )
              : Icon(run.kind.descriptor.icon, color: palette.brand),
    );
  }
}

class _RunSummaryLine extends StatelessWidget {
  const _RunSummaryLine({required this.run});

  final UnsharedRun run;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          text: TextSpan(
            children: [
              TextSpan(
                text: _distanceLabel(run),
                style: TextStyle(
                  color: palette.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              TextSpan(
                text: ' · ${formatRunElapsed(run.elapsed)} · '
                    '${run.averagePace}',
                style: TextStyle(color: palette.muted, fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${run.kind.descriptor.singular} · ${_dateLabel(run.startedAt)}',
          style: TextStyle(color: palette.muted, fontSize: 12),
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final body = this.body;
    final action = this.action;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: palette.muted),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.text,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (body != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                body,
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.muted, fontSize: 14),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: AppSpacing.md),
              action,
            ],
          ],
        ),
      ),
    );
  }
}

String _distanceLabel(UnsharedRun run) =>
    '${run.distanceKm.toStringAsFixed(2)} km';

/// "38:16", or "1:02:05" past the hour.
String formatRunElapsed(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

/// "Today", "Yesterday", or "12 Oct" — when the run happened.
String _dateLabel(DateTime when) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(when.year, when.month, when.day);
  final days = today.difference(day).inDays;
  if (days == 0) return 'Today';
  if (days == 1) return 'Yesterday';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final label = '${when.day} ${months[when.month - 1]}';
  return when.year == now.year ? label : '$label ${when.year}';
}
