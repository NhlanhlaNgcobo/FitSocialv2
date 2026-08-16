import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/services/instagram_photo_picker.dart';
import '../../../shared/widgets/background_picker.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/share_to_feed_toggle.dart';
import '../../../shared/widgets/staggered_fade_in.dart';
import '../../../shared/widgets/stepper_field.dart';
import '../application/activity_actions.dart';
import '../domain/app_models.dart';
import '../../music/presentation/music_island_action.dart';

class WorkoutLogScreen extends ConsumerStatefulWidget {
  const WorkoutLogScreen({super.key});

  @override
  ConsumerState<WorkoutLogScreen> createState() => _WorkoutLogScreenState();
}

class _WorkoutLogScreenState extends ConsumerState<WorkoutLogScreen>
    with SingleTickerProviderStateMixin {
  static const int _sectionCount = 7;

  late final AnimationController _entranceController;
  late final TextEditingController _titleController;
  late final TextEditingController _durationController;
  late final TextEditingController _caloriesController;
  late final TextEditingController _notesController;

  int _sets = 0;
  int _reps = 0;
  bool _shareToFeed = true;
  bool _isSaving = false;
  String? _errorMessage;

  /// The chosen backdrop, as a local path. Uploaded on save, not on pick — a
  /// user who backs out of the form should not have left a file behind.
  String? _backgroundPath;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
    _titleController = TextEditingController();
    _durationController = TextEditingController();
    _caloriesController = TextEditingController();
    _notesController = TextEditingController();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _titleController.dispose();
    _durationController.dispose();
    _caloriesController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  int get _durationMinutes =>
      int.tryParse(_durationController.text.trim()) ?? 0;

  int get _calories => int.tryParse(_caloriesController.text.trim()) ?? 0;

  int get _totalReps => _sets * _reps;

  bool get _hasSummary => _durationMinutes > 0 || _totalReps > 0;

  /// Picks and crops a backdrop. The cropper downscales and re-encodes, so what
  /// comes back is already feed-spec — the same path a post photo takes.
  Future<void> _pickBackground(ImageSource source) async {
    final path = await InstagramPhotoPicker.pickAndCrop(
      context: context,
      source: source,
    );
    // Null means they backed out of the picker or the cropper. Leave whatever
    // was already chosen rather than clearing it.
    if (path == null || !mounted) return;
    setState(() => _backgroundPath = path);
  }

  Future<void> _saveWorkout() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _errorMessage = 'Give your workout a name.');
      return;
    }
    if (_durationMinutes <= 0) {
      setState(() => _errorMessage = 'Add how long the session lasted.');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final exercises = <ExerciseEntry>[
        if (_sets > 0 || _reps > 0)
          ExerciseEntry(name: title, sets: _sets, reps: _reps),
      ];

      final result = await ref.read(activityActionsProvider).saveWorkout(
            WorkoutLogDraft(
              title: title,
              durationMinutes: _durationMinutes,
              calories: _calories,
              exercises: exercises,
              notes: _notesController.text.trim(),
              shareToFeed: _shareToFeed,
              backgroundImagePath: _backgroundPath,
            ),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
      context.go('/home');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    var sectionIndex = 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Log Workout'),
        actions: const [MusicIslandAction()],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.xl,
        ),
        children: [
          StaggeredFadeIn(
            controller: _entranceController,
            index: sectionIndex++,
            itemCount: _sectionCount,
            child: _TitleSection(
              controller: _titleController,
              onChanged: () => setState(() {}),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          StaggeredFadeIn(
            controller: _entranceController,
            index: sectionIndex++,
            itemCount: _sectionCount,
            child: _NumberWellSection(
              icon: Icons.timer_outlined,
              label: 'Duration',
              unit: 'min',
              controller: _durationController,
              onChanged: () => setState(() {}),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          StaggeredFadeIn(
            controller: _entranceController,
            index: sectionIndex++,
            itemCount: _sectionCount,
            child: _NumberWellSection(
              icon: Icons.local_fire_department_outlined,
              label: 'Calories',
              hint: 'Optional',
              unit: 'kcal',
              controller: _caloriesController,
              onChanged: () => setState(() {}),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          StaggeredFadeIn(
            controller: _entranceController,
            index: sectionIndex++,
            itemCount: _sectionCount,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionHeader(
                  icon: Icons.repeat_rounded,
                  label: 'Sets & reps',
                  hint: 'Optional',
                ),
                Row(
                  children: [
                    Expanded(
                      child: StepperField(
                        label: 'Sets',
                        value: _sets.toDouble(),
                        max: 30,
                        onChanged: (value) =>
                            setState(() => _sets = value.toInt()),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: StepperField(
                        label: 'Reps',
                        value: _reps.toDouble(),
                        max: 200,
                        onChanged: (value) =>
                            setState(() => _reps = value.toInt()),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          // Mirrors the estimated-pace card on the run screen: the numbers the
          // user just entered, added up, so saving isn't a leap of faith.
          _SummaryCard(
            visible: _hasSummary,
            minutes: _durationMinutes,
            sets: _sets,
            reps: _reps,
            totalReps: _totalReps,
          ),
          StaggeredFadeIn(
            controller: _entranceController,
            index: sectionIndex++,
            itemCount: _sectionCount,
            child: _BackgroundSection(
              imagePath: _backgroundPath,
              onPick: _isSaving ? null : _pickBackground,
              onRemove: _isSaving
                  ? null
                  : () => setState(() => _backgroundPath = null),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          StaggeredFadeIn(
            controller: _entranceController,
            index: sectionIndex++,
            itemCount: _sectionCount,
            child: _NotesSection(controller: _notesController),
          ),
          const SizedBox(height: AppSpacing.lg),
          StaggeredFadeIn(
            controller: _entranceController,
            index: sectionIndex++,
            itemCount: _sectionCount,
            child: ShareToFeedToggle(
              value: _shareToFeed,
              subtitle: 'Post this workout to your profile activity',
              onChanged: (value) => setState(() => _shareToFeed = value),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _ErrorBanner(message: _errorMessage),
          StaggeredFadeIn(
            controller: _entranceController,
            index: sectionIndex++,
            itemCount: _sectionCount,
            child: PrimaryButton(
              icon: _isSaving ? null : Icons.check_rounded,
              label: _isSaving
                  ? 'Saving...'
                  : (_shareToFeed ? 'Save Workout & Share' : 'Save Workout'),
              onPressed: _isSaving ? null : _saveWorkout,
            ),
          ),
        ],
      ),
    );
  }
}

/// Picks the photo that sits behind the workout card.
///
/// Shows the chosen image under the same darkening scrim the feed card applies,
/// so what the user approves here is what the post ends up looking like — a
/// bright photo that reads fine on its own can swallow the white metrics once
/// the card draws them on top.
class _BackgroundSection extends StatelessWidget {
  const _BackgroundSection({
    required this.imagePath,
    required this.onPick,
    required this.onRemove,
  });

  final String? imagePath;
  final ValueChanged<ImageSource>? onPick;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(
          icon: Icons.image_outlined,
          label: 'Background',
          hint: 'Optional',
        ),
        if (imagePath == null)
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: palette.stroke),
            ),
            child: Column(
              children: [
                Text(
                  'Add a photo behind this workout, or leave it for the '
                  'default gradient.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: palette.muted,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                BackgroundPickerRow(onPick: onPick, onRemove: onRemove),
              ],
            ),
          )
        else
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              children: [
                AspectRatio(
                  aspectRatio: 4 / 3,
                  child: _BackgroundPreview(path: imagePath!),
                ),
                // The scrim the card will draw over this photo.
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0x22050505), Color(0xC8050505)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: AppSpacing.sm,
                  right: AppSpacing.sm,
                  child: Material(
                    color: const Color(0x99050505),
                    shape: const CircleBorder(),
                    child: IconButton(
                      tooltip: 'Remove background',
                      onPressed: onRemove,
                      icon: const Icon(
                        Icons.close_rounded,
                        color: AppColors.onMedia,
                        size: 20,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: AppSpacing.md,
                  bottom: AppSpacing.md,
                  child: Text(
                    'This is how your card will look',
                    style: TextStyle(
                      color: AppColors.onMedia.withValues(alpha: 0.85),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The picked file, drawn from disk.
///
/// On web `image_picker` hands back a `blob:` URL rather than a real path, so
/// `File` cannot open it — [Image.network] is what reads a blob.
class _BackgroundPreview extends StatelessWidget {
  const _BackgroundPreview({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Image.network(path, fit: BoxFit.cover);
    }
    return Image.file(File(path), fit: BoxFit.cover);
  }
}

/// Icon disc + label that opens each block of the form.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.label,
    this.hint,
  });

  final IconData icon;
  final String label;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Padding(
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
            child: Icon(icon, size: 16, color: palette.brand),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              color: palette.text,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (hint != null) ...[
            const Spacer(),
            Text(
              hint!,
              style: TextStyle(color: palette.muted, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

/// The rounded well every input sits in — one border radius and one fill for
/// the whole form, so the fields read as a single surface instead of five.
BoxDecoration _wellDecoration(BuildContext context) {
  final palette = context.palette;
  return BoxDecoration(
    color: palette.surface,
    borderRadius: BorderRadius.circular(18),
    border: Border.all(color: palette.stroke),
  );
}

class _TitleSection extends StatelessWidget {
  const _TitleSection({
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(
          icon: Icons.fitness_center_rounded,
          label: 'Workout title',
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: _wellDecoration(context),
          child: TextField(
            controller: controller,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            style: TextStyle(
              color: palette.text,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: 'e.g. Upper Body Power',
              hintStyle: TextStyle(
                color: palette.muted,
                fontSize: 17,
                fontWeight: FontWeight.w500,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 18),
            ),
            onChanged: (_) => onChanged(),
          ),
        ),
      ],
    );
  }
}

/// A big centred number with a unit.
///
/// Duration and calories are the same control with different words, so they
/// share one — the alternative was two near-identical seventy-line widgets
/// that would drift apart the first time either was restyled.
class _NumberWellSection extends StatelessWidget {
  const _NumberWellSection({
    required this.icon,
    required this.label,
    required this.unit,
    required this.controller,
    required this.onChanged,
    this.hint,
  });

  final IconData icon;
  final String label;
  final String unit;
  final TextEditingController controller;

  final VoidCallback onChanged;

  /// Shown beside the label, e.g. "Optional".
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(icon: icon, label: label, hint: hint),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: _wellDecoration(context),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: palette.text,
                  ),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: '0',
                    hintStyle: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: palette.muted,
                    ),
                  ),
                  onChanged: (_) => onChanged(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  unit,
                  style: TextStyle(
                    color: palette.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NotesSection extends StatelessWidget {
  const _NotesSection({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(
          icon: Icons.edit_note_rounded,
          label: 'Notes',
          hint: 'Optional',
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
          decoration: _wellDecoration(context),
          child: TextField(
            controller: controller,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            style: TextStyle(color: palette.text, height: 1.4),
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: 'How did it feel?',
              hintStyle: TextStyle(color: palette.muted),
            ),
          ),
        ),
      ],
    );
  }
}

/// Live read-out of the session as entered. Slides in once there is anything
/// to show and collapses to nothing when there isn't, so an empty form stays
/// empty rather than showing a row of dashes.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.visible,
    required this.minutes,
    required this.sets,
    required this.reps,
    required this.totalReps,
  });

  final bool visible;
  final int minutes;
  final int sets;
  final int reps;
  final int totalReps;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return AnimatedSize(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 240),
        opacity: visible ? 1 : 0,
        child: visible
            ? Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: AppSpacing.lg),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: palette.brandSoft,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: palette.brandSoftStroke),
                ),
                child: Row(
                  children: [
                    _SummaryStat(
                      label: 'Duration',
                      value: minutes > 0 ? '$minutes min' : '--',
                    ),
                    const _SummaryDivider(),
                    _SummaryStat(
                      label: 'Sets × reps',
                      value: totalReps > 0 ? '$sets × $reps' : '--',
                    ),
                    const _SummaryDivider(),
                    _SummaryStat(
                      label: 'Total reps',
                      value: totalReps > 0 ? '$totalReps' : '--',
                    ),
                  ],
                ),
              )
            : const SizedBox(width: double.infinity),
      ),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  const _SummaryStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(color: context.palette.muted, fontSize: 11),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.palette.brandText,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryDivider extends StatelessWidget {
  const _SummaryDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 28,
      color: context.palette.brandSoftStroke,
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: message == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: palette.danger.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: palette.danger.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      size: 18,
                      color: palette.danger,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        message!,
                        style: TextStyle(color: palette.danger),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
