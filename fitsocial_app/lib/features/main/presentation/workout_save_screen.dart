import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/config/feature_flags.dart';
import '../../../shared/input/typed_number.dart';
import '../../../shared/services/instagram_photo_picker.dart';
import '../../../shared/widgets/confirm_destructive_sheet.dart';
import '../../../shared/widgets/glass_well.dart';
import '../../../shared/widgets/keyboard_safe_bottom_bar.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/quick_toast.dart';
import '../../../shared/widgets/run_summary_card.dart'
    show localBackgroundImage;
import '../../auth/application/body_metrics_providers.dart';
import '../../auth/domain/body_metrics.dart';
import '../../workouts/domain/workout_energy.dart';
import '../application/active_workout_controller.dart';
import '../application/activity_actions.dart';
import '../application/content_providers.dart';
import '../application/routine_actions.dart';
import '../application/workout_library_providers.dart';
import '../data/content_repository.dart';
import '../domain/active_workout.dart';
import '../domain/app_models.dart';
import '../domain/routine.dart';
import '../domain/weekly_streak.dart';
import '../domain/workout_celebration.dart';
import '../domain/workout_math.dart';
import 'session_time_sheet.dart';
import 'tag_people_sheet.dart';
import 'workout_session_screen.dart' show formatElapsed;

/// What happens between Finish and the saved workout: name it, check when
/// and how long, add a photo and a few words, choose who sees it.
///
/// Finish used to save on the spot with no calories and no say in any of it.
/// This screen reads the session that is still open — nothing is ended until
/// Save goes through, so backing out of it lands back in the workout.
class WorkoutSaveScreen extends ConsumerStatefulWidget {
  const WorkoutSaveScreen({super.key});

  @override
  ConsumerState<WorkoutSaveScreen> createState() => _WorkoutSaveScreenState();
}

class _WorkoutSaveScreenState extends ConsumerState<WorkoutSaveScreen> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _calories = TextEditingController();

  /// The moment Finish was tapped: the end of the session, held still so the
  /// duration does not keep growing while the form is filled in.
  final DateTime _endedAt = DateTime.now();

  DateTime? _startedAt;
  Duration? _duration;
  String? _photoPath;
  List<TaggedUser> _tagged = const [];
  bool _shareToFeed = true;

  /// For a session from a routine whose plan changed: update it or not.
  /// Null until the user has said, which Save waits for.
  bool? _updateRoutine;

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final workout = ref.read(activeWorkoutProvider);
    if (workout != null) {
      _title.text = workout.title;
      _startedAt = workout.startedAt;
      _duration = workout.elapsed(_endedAt);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _calories.dispose();
    super.dispose();
  }

  int? _estimate(ActiveWorkout workout) => estimateWorkoutCalories(
        exercises: workout.entries,
        durationMinutes: ((_duration ?? Duration.zero).inSeconds / 60).round(),
        bodyweightKg: workout.bodyweightKg,
      );

  Future<void> _pickPhoto(ImageSource source) async {
    final path = await InstagramPhotoPicker.pickAndCrop(
      context: context,
      source: source,
      otherShapes: true,
    );
    if (path == null || !mounted) return;
    setState(() => _photoPath = path);
  }

  Future<void> _discard() async {
    final sure = await confirmDestructiveAction(
      context,
      title: 'Discard this workout?',
      message: 'Every set you logged in it is thrown away.',
      confirmLabel: 'Discard workout',
    );
    if (!sure || !mounted) return;
    ref.read(activeWorkoutProvider.notifier).discard();
    context.go('/home');
  }

  Future<void> _save(ActiveWorkout workout, Routine? changedRoutine) async {
    if (changedRoutine != null && _updateRoutine == null) {
      setState(
          () => _error = 'Choose whether to update ${changedRoutine.name}.');
      return;
    }
    ref.read(activeWorkoutProvider.notifier).setTitle(_title.text.trim());

    setState(() {
      _saving = true;
      _error = null;
    });

    // Everything that needs the history read before the save adds to it.
    final history = ref.read(workoutHistoryProvider).valueOrNull ?? const [];
    final items = ref.read(workoutHistoryItemsProvider).valueOrNull ?? const [];
    final prs = finishRecords(
      history,
      workout,
      live: ref.read(sessionRecordsProvider),
    );
    final typed = parseTypedInt(_calories.text);

    try {
      final draft = workout.copyWith(title: _title.text.trim()).toDraft(
            endedAt: _endedAt,
            shareToFeed: _shareToFeed,
            notes: _description.text.trim(),
            customExercises:
                ref.read(customExercisesProvider).valueOrNull ?? const [],
            startedAt: _startedAt,
            duration: _duration,
            calories: typed,
            caloriesEstimated: typed == null ? null : false,
            backgroundImagePath: _photoPath,
            taggedUsers: _tagged,
            prs: prs,
          );
      final result = await ref.read(activityActionsProvider).saveWorkout(draft);
      // Ended only once the save went through: a failure leaves the session
      // open, to try again.
      ref.read(activeWorkoutProvider.notifier).complete();

      if (changedRoutine != null && _updateRoutine == true) {
        // After the workout, never instead of it.
        try {
          await ref
              .read(routineActionsProvider)
              .save(routineUpdatedFromSession(changedRoutine, workout));
        } catch (error) {
          debugPrint('Could not update the routine: $error');
          if (mounted) {
            showQuickToast(
              context,
              'Saved, but ${changedRoutine.name} could not be updated.',
              tone: ToastTone.danger,
            );
          }
        }
      }

      // "Workout #N": the profile counter, which already holds this one in
      // the local cache, or the history that loaded plus this one.
      int? count;
      try {
        count = await ref
            .read(contentRepositoryProvider)
            .getMyWorkoutsCount()
            .timeout(const Duration(seconds: 3));
      } catch (_) {
        count = null;
      }
      final number =
          count != null && count > items.length ? count : items.length + 1;

      if (!mounted) return;
      context.go(
        '/workout-saved',
        extra: WorkoutCelebration(
          title: draft.title,
          loggedAt: draft.loggedAt ?? _endedAt,
          workoutNumber: number,
          weeklyStreak: weeklyStreak(
            [...items.map((i) => i.loggedAt), draft.loggedAt ?? _endedAt],
            DateTime.now(),
          ),
          prs: prs,
          workoutData: draft.workoutData,
          backgroundPath: _photoPath,
          postId: result.createdPost?.id,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save the workout. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final workout = ref.watch(activeWorkoutProvider);
    // Loaded now, so the records and the workout number are ready by Save.
    ref.watch(workoutHistoryProvider);
    ref.watch(workoutHistoryItemsProvider);
    ref.watch(sessionRecordsProvider);

    if (workout == null) {
      // Saved and gone, or never there: nothing to fill in.
      return Scaffold(
        appBar: AppBar(title: const Text('Save workout')),
        body: Center(
          child: TextButton(
            onPressed: () => context.go('/home'),
            child: const Text('Back home'),
          ),
        ),
      );
    }

    final changedRoutine = _changedRoutine(workout);
    final imperial = ref.watch(bodyMetricsProvider).valueOrNull?.units ==
        MeasurementUnits.imperial;
    final volume = workout.volumeKg;
    final volumeText = imperial
        ? '${(volume / 0.45359237).round()} lb'
        : '${volume.round()} kg';
    final estimate = _estimate(workout);

    return Scaffold(
      appBar: AppBar(title: const Text('Save workout')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.xl,
        ),
        children: [
          GlassWell(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _title,
              textCapitalization: TextCapitalization.words,
              style: TextStyle(
                color: palette.text,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: 'Workout name',
                hintStyle: TextStyle(color: palette.muted),
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          GlassWell(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              children: [
                _Stat(
                  label: 'Duration',
                  value: formatElapsed(_duration ?? Duration.zero),
                ),
                _Stat(label: 'Volume', value: volumeText),
                _Stat(label: 'Sets', value: '${workout.doneSetCount}'),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const _Label('WHEN'),
          Row(
            children: [
              Expanded(
                child: _Tap(
                  icon: Icons.event_rounded,
                  text: _startLabel(_startedAt ?? workout.startedAt),
                  onTap: _saving
                      ? null
                      : () async {
                          final at = await pickStartTime(
                            context,
                            initial: _startedAt ?? workout.startedAt,
                          );
                          if (at != null && mounted) {
                            setState(() => _startedAt = at);
                          }
                        },
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _Tap(
                  icon: Icons.timelapse_rounded,
                  text: formatElapsed(_duration ?? Duration.zero),
                  onTap: _saving
                      ? null
                      : () async {
                          final length = await showDurationPrompt(
                            context,
                            initial: _duration ?? Duration.zero,
                          );
                          if (length != null && mounted) {
                            setState(() => _duration = length);
                          }
                        },
                ),
              ),
            ],
          ),
          if (changedRoutine != null) ...[
            const SizedBox(height: AppSpacing.md),
            _RoutineChangedCard(
              name: changedRoutine.name,
              choice: _updateRoutine,
              onChoose: (update) => setState(() {
                _updateRoutine = update;
                _error = null;
              }),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          const _Label('PHOTO'),
          _PhotoPicker(
            path: _photoPath,
            onPick: _saving ? null : _pickPhoto,
            onRemove: _saving ? null : () => setState(() => _photoPath = null),
          ),
          const SizedBox(height: AppSpacing.md),
          const _Label('DESCRIPTION'),
          GlassWell(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _description,
              minLines: 2,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              style: TextStyle(color: palette.text, fontSize: 15),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: 'How did it go? @mention a training partner',
                hintStyle: TextStyle(color: palette.muted),
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          if (_shareToFeed) ...[
            const SizedBox(height: AppSpacing.sm),
            TagPeopleRow(
              tagged: _tagged,
              onTap: _saving
                  ? null
                  : () async {
                      final picked =
                          await showTagPeopleSheet(context, selected: _tagged);
                      if (picked != null && mounted) {
                        setState(() => _tagged = picked);
                      }
                    },
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          const _Label('WHO CAN SEE THIS'),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: true,
                icon: Icon(Icons.group_rounded),
                label: Text('Followers'),
              ),
              ButtonSegment(
                value: false,
                icon: Icon(Icons.lock_rounded),
                label: Text('Only me'),
              ),
            ],
            selected: {_shareToFeed},
            onSelectionChanged: _saving
                ? null
                : (value) => setState(() => _shareToFeed = value.first),
          ),
          const SizedBox(height: AppSpacing.md),
          const _Label('CALORIES'),
          GlassWell(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _calories,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (_) => setState(() {}),
                    style: TextStyle(
                      color: palette.text,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: estimate == null ? '0' : '$estimate',
                      hintStyle: TextStyle(color: palette.muted),
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                Text('kcal', style: TextStyle(color: palette.muted)),
              ],
            ),
          ),
          if (estimate != null && _calories.text.isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 4),
              child: Text(
                'Estimate · type to change',
                style: TextStyle(color: palette.muted, fontSize: 11.5),
              ),
            ),
          const SizedBox(height: AppSpacing.lg),
          Center(
            child: TextButton(
              onPressed: _saving ? null : _discard,
              style: TextButton.styleFrom(foregroundColor: palette.danger),
              child: const Text('Discard workout'),
            ),
          ),
        ],
      ),
      bottomNavigationBar: KeyboardSafeBottomBar(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _error!,
                    style: TextStyle(color: palette.danger, fontSize: 13),
                  ),
                ),
              PrimaryButton(
                icon: Icons.check_rounded,
                label: _saving ? 'Saving…' : 'Save workout',
                onPressed:
                    _saving ? null : () => _save(workout, changedRoutine),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The routine this session changed, when it came from one and routines
  /// are on. Read from the loaded list; a routine deleted since has nothing
  /// to update, so it asks nothing.
  Routine? _changedRoutine(ActiveWorkout workout) {
    if (!ref.watch(featureEnabledProvider(FeatureFlag.routines)) ||
        !workout.changedFromRoutine) {
      return null;
    }
    final routines = ref.watch(routinesProvider).valueOrNull ?? const [];
    return routines.where((r) => r.id == workout.routineId).firstOrNull;
  }

  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _startLabel(DateTime at) {
    final minute = at.minute.toString().padLeft(2, '0');
    return '${_days[at.weekday - 1]} ${at.day} ${_months[at.month - 1]} · '
        '${at.hour}:$minute';
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 8),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: context.palette.muted,
          ),
        ),
      );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Expanded(
      child: Column(
        children: [
          FittedBox(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: palette.text,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              color: palette.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _Tap extends StatelessWidget {
  const _Tap({required this.icon, required this.text, required this.onTap});

  final IconData icon;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final radius = BorderRadius.circular(AppRadius.field);
    return Material(
      color: palette.surfaceHigh,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 18, color: palette.muted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Icon(Icons.edit_rounded, size: 16, color: palette.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// "You changed Push Day · Keep original / Update routine", inline, as a
/// choice the user makes before Save rather than a sheet in its way.
class _RoutineChangedCard extends StatelessWidget {
  const _RoutineChangedCard({
    required this.name,
    required this.choice,
    required this.onChoose,
  });

  final String name;
  final bool? choice;
  final ValueChanged<bool> onChoose;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: palette.brandSoft,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: palette.brandSoftStroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'You changed $name',
            style: TextStyle(
              color: palette.text,
              fontSize: 15.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Exercises or sets were added, removed or reordered. The weights '
            'and reps it plans stay either way.',
            style: TextStyle(color: palette.muted, fontSize: 13, height: 1.35),
          ),
          const SizedBox(height: 10),
          SegmentedButton<bool>(
            emptySelectionAllowed: true,
            segments: const [
              ButtonSegment(value: false, label: Text('Keep original')),
              ButtonSegment(value: true, label: Text('Update routine')),
            ],
            selected: {if (choice != null) choice!},
            onSelectionChanged: (value) {
              if (value.isNotEmpty) onChoose(value.first);
            },
          ),
        ],
      ),
    );
  }
}

class _PhotoPicker extends StatelessWidget {
  const _PhotoPicker({
    required this.path,
    required this.onPick,
    required this.onRemove,
  });

  final String? path;
  final ValueChanged<ImageSource>? onPick;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final chosen = path;
    if (chosen != null) {
      return Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.nested),
            child: Image(
              image: localBackgroundImage(chosen),
              width: 72,
              height: 72,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  Container(width: 72, height: 72, color: palette.surfaceHigh),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'Shown behind the workout card',
              style: TextStyle(color: palette.muted, fontSize: 13),
            ),
          ),
          TextButton(onPressed: onRemove, child: const Text('Remove')),
        ],
      );
    }
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed:
                onPick == null ? null : () => onPick!(ImageSource.gallery),
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Gallery'),
          ),
        ),
        if (!kIsWeb) ...[
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: OutlinedButton.icon(
              onPressed:
                  onPick == null ? null : () => onPick!(ImageSource.camera),
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Camera'),
            ),
          ),
        ],
      ],
    );
  }
}
