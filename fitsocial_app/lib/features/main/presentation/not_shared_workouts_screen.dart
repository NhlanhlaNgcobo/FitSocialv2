import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/connectivity/backend_reachability.dart';
import '../../../shared/services/instagram_photo_picker.dart';
import '../../../shared/services/workout_card_exporter.dart';
import '../../../shared/widgets/app_photo.dart';
import '../../../shared/widgets/confirm_destructive_sheet.dart';
import '../../../shared/widgets/dark_card.dart';
import '../../../shared/widgets/glass_well.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/quick_toast.dart';
import '../../../shared/widgets/run_summary_card.dart'
    show localBackgroundImage;
import '../../../shared/widgets/save_workout_card_row.dart';
import '../../../shared/widgets/workout_summary_card.dart';
import '../application/activity_actions.dart';
import '../application/content_providers.dart';
import '../application/workout_library_providers.dart';
import '../domain/app_models.dart';
import '../domain/unshared_workout.dart';
import 'tag_people_sheet.dart';

/// Every workout saved with "Only me", newest first.
///
/// Opened from the Workouts tab on the profile, as the runs saved without
/// posting are from the Runs tab. Each one opens in
/// [UnsharedWorkoutEditorScreen] to post or delete.
class NotSharedWorkoutsScreen extends ConsumerWidget {
  const NotSharedWorkoutsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final workouts = ref.watch(unsharedWorkoutsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Not shared')),
      body: workouts.when(
        loading: () => Center(
          child: CircularProgressIndicator(color: palette.brand),
        ),
        error: (_, __) => _Message(
          icon: Icons.cloud_off_rounded,
          title: "Couldn't load your workouts",
          action: OutlinedButton(
            onPressed: () => ref.invalidate(unsharedWorkoutsProvider),
            child: const Text('Retry'),
          ),
        ),
        data: (workouts) {
          if (workouts.isEmpty) {
            return const _Message(
              icon: Icons.lock_outline_rounded,
              title: 'Nothing here',
              body: 'Workouts you save with "Only me" land here, so you can '
                  'post them later.',
            );
          }
          return RefreshIndicator(
            color: palette.brand,
            onRefresh: () async => ref.invalidate(unsharedWorkoutsProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: workouts.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, index) {
                final workout = workouts[index];
                return DarkCard(
                  onTap: () => context.push(
                    '/not-shared-workouts/${workout.id}',
                    extra: workout,
                  ),
                  child: Row(
                    children: [
                      _Thumbnail(workout: workout),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(child: _SummaryLine(workout: workout)),
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

/// One private workout, as its card will look, with a photo, a caption and
/// tagged people to add before Post — or Delete.
class UnsharedWorkoutEditorScreen extends ConsumerStatefulWidget {
  const UnsharedWorkoutEditorScreen({
    required this.workoutId,
    this.initialWorkout,
    super.key,
  });

  final String workoutId;

  /// The workout as the list loaded it. Null after a restart or a deep link,
  /// when it is looked up in the list by [workoutId] instead.
  final UnsharedWorkout? initialWorkout;

  @override
  ConsumerState<UnsharedWorkoutEditorScreen> createState() =>
      _UnsharedWorkoutEditorScreenState();
}

class _UnsharedWorkoutEditorScreenState
    extends ConsumerState<UnsharedWorkoutEditorScreen> {
  UnsharedWorkout? _workout;
  final _caption = TextEditingController();

  /// A photo picked here, not yet uploaded.
  String? _localPhoto;

  /// Whether the photo saved with the workout is still behind the card.
  bool _keepSavedPhoto = true;

  List<TaggedUser> _tagged = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final workout = widget.initialWorkout;
    if (workout != null) _adopt(workout);
  }

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  void _adopt(UnsharedWorkout workout) {
    _workout = workout;
    _caption.text = workout.notes;
  }

  String? get _savedPhoto => _keepSavedPhoto ? _workout?.imageUrl : null;

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

  Future<void> _post(UnsharedWorkout workout) async {
    setState(() => _busy = true);
    try {
      final result =
          await ref.read(activityActionsProvider).shareUnsharedWorkout(
                UnsharedWorkoutShare(
                  workout: workout,
                  caption: _caption.text,
                  backgroundImagePath: _localPhoto,
                  keepExistingImage: _savedPhoto != null,
                  taggedUsers: _tagged,
                  customExercises:
                      ref.read(customExercisesProvider).valueOrNull ?? const [],
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
        "Couldn't post this workout. Try again.",
        icon: Icons.error_outline_rounded,
        tone: ToastTone.danger,
      );
    }
  }

  Future<void> _delete(UnsharedWorkout workout) async {
    final confirmed = await confirmDestructiveAction(
      context,
      title: 'Delete this workout?',
      message: '${workout.title} on ${_dateLabel(workout.loggedAt)} will be '
          'removed from your history. This cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(activityActionsProvider).deleteUnsharedWorkout(workout);
      if (!mounted) return;
      showQuickToast(context, 'Deleted');
      context.pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      showQuickToast(
        context,
        "Couldn't delete this workout. Try again.",
        icon: Icons.error_outline_rounded,
        tone: ToastTone.danger,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    var workout = _workout;
    if (workout == null) {
      // Opened without the workout in hand: find it in the list.
      final workouts = ref.watch(unsharedWorkoutsProvider);
      final found = workouts.valueOrNull
          ?.where((candidate) => candidate.id == widget.workoutId)
          .firstOrNull;
      if (found != null) {
        _adopt(found);
        workout = found;
      } else {
        return Scaffold(
          appBar: AppBar(),
          body: workouts.isLoading
              ? Center(child: CircularProgressIndicator(color: palette.brand))
              : const _Message(
                  icon: Icons.search_off_rounded,
                  title: 'This workout is no longer here',
                  body: 'It may already have been posted or deleted.',
                ),
        );
      }
    }

    final offline = ref.watch(isOfflineProvider);
    final localPhoto = _localPhoto;
    final savedPhoto = _savedPhoto;
    final photo = localPhoto != null
        ? localBackgroundImage(localPhoto)
        : savedPhoto != null
            ? appPhoto(savedPhoto)
            : null;
    final workoutData = workout.toDraft().workoutData;

    return Scaffold(
      appBar: AppBar(
        title: Text(workout.title),
        actions: [
          IconButton(
            tooltip: 'Delete',
            onPressed: _busy ? null : () => _delete(workout!),
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
              _dateLabel(workout.loggedAt),
              style: TextStyle(color: palette.muted, fontSize: 13),
            ),
            const SizedBox(height: AppSpacing.md),
            WorkoutSummaryCard(
              workoutData: workoutData,
              activity: 'Workout',
              backgroundImage: photo,
              margin: EdgeInsets.zero,
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _pick(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: Text(photo == null ? 'Add photo' : 'Change photo'),
                  ),
                ),
                if (photo != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                              _localPhoto = null;
                              _keepSavedPhoto = false;
                            }),
                    child: const Text('Remove'),
                  ),
                ] else if (!kIsWeb) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : () => _pick(ImageSource.camera),
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('Camera'),
                    ),
                  ),
                ],
              ],
            ),
            if (!kIsWeb) ...[
              const SizedBox(height: AppSpacing.sm),
              SaveWorkoutCardRow(
                card: WorkoutCardExport(
                  activity: 'Workout',
                  workoutData: workoutData,
                  background: photo,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            GlassWell(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _caption,
                enabled: !_busy,
                minLines: 2,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
                style: TextStyle(color: palette.text, fontSize: 15),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Say something about it',
                  hintStyle: TextStyle(color: palette.muted),
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
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
              onPressed: _busy || offline ? null : () => _post(workout!),
            ),
          ],
        ),
      ),
    );
  }
}

/// The photo if there is one, a dumbbell if not.
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.workout});

  final UnsharedWorkout workout;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final url = workout.imageUrl;
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
          : Icon(Icons.fitness_center_rounded, color: palette.brand),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.workout});

  final UnsharedWorkout workout;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final count = workout.exercises.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          workout.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: palette.text,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          [
            _dateLabel(workout.loggedAt),
            '${workout.durationMinutes} min',
            count == 1 ? '1 exercise' : '$count exercises',
          ].join(' · '),
          style: TextStyle(color: palette.muted, fontSize: 12.5),
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

/// "Today", "Yesterday", or "12 Oct" — when the workout happened.
String _dateLabel(DateTime when) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(when.year, when.month, when.day);
  final days = today.difference(day).inDays;
  if (days == 0) return 'Today';
  if (days == 1) return 'Yesterday';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final label = '${when.day} ${months[when.month - 1]}';
  return when.year == now.year ? label : '$label ${when.year}';
}
