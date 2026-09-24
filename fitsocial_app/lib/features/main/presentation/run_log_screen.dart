import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/input/typed_number.dart';
import '../../../shared/services/instagram_photo_picker.dart';
import '../../../shared/services/run_card_exporter.dart';
import '../../../shared/widgets/dark_card.dart';
import '../../../shared/widgets/form_section_header.dart';
import '../../../shared/widgets/glass_well.dart';
import '../../../shared/widgets/glass.dart';
import '../../../shared/widgets/health_pull_card.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/quick_toast.dart';
import '../../../shared/widgets/run_background_section.dart';
import '../../../shared/widgets/run_summary_card.dart';
import '../../../shared/widgets/save_run_card_row.dart';
import '../../../shared/widgets/share_to_feed_toggle.dart';
import '../../../shared/widgets/staggered_fade_in.dart';
import '../../tracking/application/run_draft_providers.dart';
import '../../tracking/application/tracking_providers.dart';
import '../../tracking/data/run_import_service.dart';
import '../../tracking/domain/run_draft.dart';
import '../../tracking/domain/run_pace.dart';
import '../application/activity_actions.dart';
import '../domain/activity_kind.dart';
import '../domain/app_models.dart';
import 'tag_people_sheet.dart';
import '../../music/presentation/music_island_action.dart';
import '../../../shared/widgets/liquid_glass.dart';

class RunLogScreen extends ConsumerStatefulWidget {
  const RunLogScreen({super.key});

  @override
  ConsumerState<RunLogScreen> createState() => _RunLogScreenState();
}

class _RunLogScreenState extends ConsumerState<RunLogScreen>
    with SingleTickerProviderStateMixin {
  /// The stagger's denominator: how many sections this build actually emits.
  ///
  /// Has to match, or a section that isn't counted never finishes its fade.
  /// It was a const 7 when the screen always drew the same rows; the activity
  /// picker added one, and the treadmill card now comes and goes with the
  /// selected activity, so it is counted rather than assumed. The health
  /// card is another that comes and goes: there is no platform store on web.
  int get _sectionCount =>
      (_kind == ActivityKind.run ? 8 : 7) + (kIsWeb ? 0 : 1);

  late final AnimationController _entranceController;
  late final TextEditingController _distanceController;
  late final TextEditingController _durationController;

  /// Which activity every control on this screen is currently about: the GPS
  /// card it opens, the wording, and whether the manual form's third figure is
  /// a pace or a speed.
  ActivityKind _kind = ActivityKind.run;

  double _distanceKm = 0;

  /// Typed as minutes, held as a Duration so a fractional entry keeps its
  /// seconds all the way to the post.
  Duration _elapsed = Duration.zero;
  bool _shareToFeed = true;
  List<TaggedUser> _taggedUsers = const [];
  bool _isSaving = false;

  /// The health-store session the form was filled from, if it was. Carried
  /// through to the save so the outing keeps its real start time and cannot
  /// arrive a second time as an import.
  HealthRunPrefill? _healthPrefill;
  bool _isPullingHealth = false;

  /// Why the last pull produced nothing, shown under the card. Cleared by the
  /// next attempt.
  String? _healthNote;

  /// The chosen backdrop, as a local path. Uploaded on save, not on pick — a
  /// user who backs out of the form should not have left a file behind.
  String? _backgroundPath;
  // Set the first time Save is pressed with a blank field, so the wells only
  // turn red after the user has actually tried to submit.
  bool _showFieldErrors = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
    _distanceController = TextEditingController();
    _durationController = TextEditingController();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _distanceController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  bool get _hasDistance => _distanceKm > 0;
  bool get _hasDuration => _elapsed > Duration.zero;
  bool get _isComplete => _hasDistance && _hasDuration;

  /// The headline second figure: `m:ss /km` on foot, `x.x km/h` on a bike.
  ///
  /// Formatted by the shared helpers rather than here, so a manually entered
  /// ride and a recorded one cannot drift into two different shapes.
  String get _paceLabel {
    if (!_isComplete) return '--';
    return formatPaceOrSpeed(
      kind: _kind,
      distanceKm: _distanceKm,
      elapsed: _elapsed,
    );
  }

  /// What that figure is called: "Avg pace" or "Avg speed".
  String get _paceStatLabel =>
      _kind.descriptor.usesPace ? 'Avg pace' : 'Avg speed';

  String get _durationLabel {
    if (!_hasDuration) return '--';
    final hours = _elapsed.inHours;
    final mins = _elapsed.inMinutes % 60;
    if (hours == 0) return '$mins min';
    return mins == 0 ? '${hours}h' : '${hours}h ${mins}m';
  }

  /// The elapsed time as the *post* will carry it — a clock, not a phrase.
  ///
  /// Deliberately not [_durationLabel]: the card below is a preview of what
  /// gets shared, and a preview that reads "45 min" where the post will read
  /// "45:00" is a preview of something else.
  String get _clockLabel {
    final hours = _elapsed.inHours;
    final mins = (_elapsed.inMinutes % 60).toString().padLeft(2, '0');
    final secs = (_elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return hours == 0 ? '$mins:$secs' : '$hours:$mins:$secs';
  }

  static String _formatDistance(double value) {
    var text = value.toStringAsFixed(2);
    if (text.contains('.')) {
      text = text.replaceFirst(RegExp(r'0+$'), '');
      text = text.replaceFirst(RegExp(r'\.$'), '');
    }
    return text;
  }

  /// Minutes for the duration field, to the same two places: 50:25 is typed
  /// back as "50.42", which parses to the same second.
  static String _formatMinutes(Duration value) =>
      _formatDistance(value.inSeconds / 60);

  /// Reads the latest session out of the health store into the form.
  ///
  /// Access is *asked for* rather than checked. The dashboard's gate covers
  /// steps and heart rate but not exercise sessions, so "granted" there can
  /// still mean "declined" here, and the silent import can only find nothing.
  /// Health Connect returns at once when everything is already allowed, and a
  /// tap on a button that says what it wants is the one moment a permission
  /// dialog is not a surprise.
  Future<void> _pullFromHealth() async {
    if (_isPullingHealth || _isSaving) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _isPullingHealth = true;
      _healthNote = null;
    });
    try {
      final granted =
          await ref.read(healthServiceProvider).requestPermissions();
      if (!mounted) return;
      if (!granted) {
        setState(() => _healthNote = HealthPullCard.refusedNote);
        return;
      }
      final prefill = await ref.read(runImportServiceProvider).latest();
      if (!mounted) return;
      if (prefill == null) {
        setState(() => _healthNote = HealthPullCard.emptyNote);
        return;
      }
      _applyHealthPrefill(prefill);
    } catch (_) {
      if (!mounted) return;
      setState(() => _healthNote = HealthPullCard.failedNote);
    } finally {
      if (mounted) setState(() => _isPullingHealth = false);
    }
  }

  void _applyHealthPrefill(HealthRunPrefill prefill) {
    final km = prefill.distanceKm;
    setState(() {
      _healthPrefill = prefill;
      // The session decides the activity: a hike pulled into a form set to
      // "run" would be saved as a run, and the picker is right there to
      // override it.
      _kind = prefill.kind;
      _distanceKm = km ?? 0;
      _elapsed = prefill.elapsed;
      _distanceController.text = km == null ? '' : _formatDistance(km);
      _durationController.text = _formatMinutes(prefill.elapsed);
      _showFieldErrors = false;
      _errorMessage = null;
    });
    final source = prefill.record.sourceName;
    showQuickToast(
      context,
      km == null
          ? 'Time filled from $source. Add the distance.'
          : 'Filled from $source',
      tone: ToastTone.success,
    );
  }

  /// "Run · Today 07:12 · 10.01 km in 50:25".
  static String _describePrefill(HealthRunPrefill prefill) {
    final distance = prefill.distanceKm;
    final clock = HealthPullCard.clockLabel(prefill.elapsed);
    return [
      prefill.kind.descriptor.singular,
      HealthPullCard.whenLabel(prefill.record.startedAt),
      distance == null
          ? '$clock, no distance recorded'
          : '${_formatDistance(distance)} km in $clock',
    ].join(' · ');
  }

  /// A saved session came out of the health store: stamp the ledger so the
  /// background import never files it, and drop the draft if it already has.
  ///
  /// Housekeeping, so it must not fail the save: the run is already in
  /// Firestore, and its window blocks the import on its own even if this
  /// throws.
  Future<void> _retireImport(String externalId) async {
    try {
      await ref.read(runImportLedgerProvider).markHandled([externalId]);
      final controller = ref.read(runDraftsProvider.notifier);
      final drafts =
          ref.read(runDraftsProvider).valueOrNull ?? const <RunDraft>[];
      for (final draft in drafts) {
        if (draft.externalId == externalId) await controller.discard(draft);
      }
    } catch (error) {
      debugPrint('Could not retire imported run $externalId: $error');
    }
  }

  /// Picks and crops a backdrop. The cropper downscales and re-encodes, so what
  /// comes back is already feed-spec — the same path a post photo takes.
  Future<void> _pickBackground(ImageSource source) async {
    final path = await InstagramPhotoPicker.pickAndCrop(
      // A card's backdrop: 9:16 by default, and the card follows
      // whichever shape the photo is cropped to.
      otherShapes: true,
      context: context,
      source: source,
    );
    // Null means they backed out of the picker or the cropper. Leave whatever
    // was already chosen rather than clearing it.
    if (path == null || !mounted) return;
    setState(() => _backgroundPath = path);
  }

  /// Null is a dismissal and leaves the selection alone; an empty list is a
  /// deliberate "nobody".
  Future<void> _pickTaggedPeople() async {
    final picked = await showTagPeopleSheet(context, selected: _taggedUsers);
    if (picked == null || !mounted) return;
    setState(() => _taggedUsers = picked);
  }

  Future<void> _saveRun() async {
    if (!_isComplete) {
      setState(() {
        _showFieldErrors = true;
        _errorMessage = 'Add a distance and a time before saving.';
      });
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final result = await ref.read(activityActionsProvider).saveRun(
            RunLogDraft(
              distanceKm: _distanceKm,
              elapsed: _elapsed,
              averagePace: _paceLabel,
              shareToFeed: _shareToFeed,
              activityKind: _kind,
              backgroundImagePath: _backgroundPath,
              // Only ever set by a health pull. A run typed from memory has
              // no start worth recording beyond "now".
              startedAt: _healthPrefill?.record.startedAt,
              heartRate: _healthPrefill?.heartRate,
              taggedUsers: _shareToFeed ? _taggedUsers : const [],
            ),
          );
      if (!mounted) return;
      if (_healthPrefill case final prefill?) {
        await _retireImport(prefill.record.externalId);
        if (!mounted) return;
      }
      showQuickToast(context, result.message, tone: ToastTone.success);
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
    final palette = context.palette;
    var sectionIndex = 0;

    return Scaffold(
      appBar: AppBar(
        title: Text('Log ${_kind.descriptor.singular}'),
        actions: const [MusicIslandAction()],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          // Clears the gesture pill / three-button nav so the Save button
          // isn't sitting under it at the end of the scroll.
          AppSpacing.xl + MediaQuery.of(context).viewPadding.bottom,
        ),
        children: [
          StaggeredFadeIn(
            controller: _entranceController,
            index: sectionIndex++,
            itemCount: _sectionCount,
            child: _ActivityPicker(
              selected: _kind,
              onChanged: (kind) => setState(() => _kind = kind),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          StaggeredFadeIn(
            controller: _entranceController,
            index: sectionIndex++,
            itemCount: _sectionCount,
            child: _GpsHeroCard(
              kind: _kind,
              onTap: () => context.push('/live-run', extra: _kind),
            ),
          ),
          // A treadmill is a way of running indoors and nothing else: there is
          // no indoor hike, and a stationary bike is a different machine with
          // different numbers. Shown for runs only rather than offered and
          // then behaving oddly.
          if (_kind == ActivityKind.run) ...[
            const SizedBox(height: AppSpacing.sm + 4),
            StaggeredFadeIn(
              controller: _entranceController,
              index: sectionIndex++,
              itemCount: _sectionCount,
              child: _TreadmillCard(
                onTap: () => context.push('/treadmill-run'),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          StaggeredFadeIn(
            controller: _entranceController,
            index: sectionIndex++,
            itemCount: _sectionCount,
            child: const _LabelledDivider(label: 'or log it manually'),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (!kIsWeb) ...[
            StaggeredFadeIn(
              controller: _entranceController,
              index: sectionIndex++,
              itemCount: _sectionCount,
              child: HealthPullCard(
                busy: _isPullingHealth,
                filled: _healthPrefill != null,
                title: _healthPrefill == null
                    ? HealthPullCard.idleTitle
                    : 'Filled from ${_healthPrefill!.record.sourceName}',
                subtitle: _healthPrefill == null
                    ? 'Pull your latest session from Samsung Health or '
                        'your watch'
                    : _describePrefill(_healthPrefill!),
                note: _healthNote,
                onTap: _isSaving ? null : _pullFromHealth,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          StaggeredFadeIn(
            controller: _entranceController,
            index: sectionIndex++,
            itemCount: _sectionCount,
            child: LiquidGlass(
              // Painted by the lens rather than by a fill of its own: a pane
              // over the app backdrop, like every other card.
              borderRadius: BorderRadius.circular(AppRadius.card),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(color: palette.stroke),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _MetricField(
                      icon: Icons.straighten_rounded,
                      label: 'Distance',
                      controller: _distanceController,
                      suffix: 'km',
                      hint: '0.00',
                      decimal: true,
                      invalid: _showFieldErrors && !_hasDistance,
                      onChanged: (value) {
                        setState(() {
                          _distanceKm = parseTypedDouble(value) ?? 0;
                        });
                      },
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _MetricField(
                      icon: Icons.timer_outlined,
                      label: 'Duration',
                      controller: _durationController,
                      suffix: 'min',
                      hint: '0',
                      // Minutes, but not whole ones: "50,5" is a real time.
                      decimal: true,
                      invalid: _showFieldErrors && !_hasDuration,
                      onChanged: (value) {
                        setState(() {
                          _elapsed = parseTypedMinutes(value);
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            // Height alone, no fade over it: a pane of glass inside an
            // opacity buffer has no backdrop left to bend, so it would hollow
            // out for the whole reveal and then snap.
            child: _isComplete
                ? Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.md),
                    child: _RunSummary(
                      distance: '${_formatDistance(_distanceKm)} km',
                      duration: _durationLabel,
                      pace: _paceLabel,
                      paceLabel: _paceStatLabel,
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
          const SizedBox(height: AppSpacing.lg),
          StaggeredFadeIn(
            controller: _entranceController,
            index: sectionIndex++,
            itemCount: _sectionCount,
            // Inside the same stagger step as the section it belongs to, so
            // the entrance sequence keeps its count.
            child: Column(
              children: [
                RunBackgroundSection(
                  imagePath: _backgroundPath,
                  // A logged run has no trace, so a blank card is just numbers
                  // on a gradient: offer the photo, preview only once picked.
                  previewWithoutImage: false,
                  distanceLabel: _hasDistance
                      ? '${_formatDistance(_distanceKm)} km'
                      : null,
                  durationLabel: _hasDuration ? _clockLabel : null,
                  paceLabel: _isComplete ? _paceLabel : null,
                  onPick: _isSaving ? null : _pickBackground,
                  onRemove: _isSaving
                      ? null
                      : () => setState(() => _backgroundPath = null),
                ),
                // The card only exists on screen once there is a photo, so
                // the export follows it.
                if (!kIsWeb && _backgroundPath != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  SaveRunCardRow(
                    card: RunCardExport(
                      // A logged run has no trace — the numbers and the photo
                      // carry the card, exactly as they do on screen.
                      distanceLabel: _hasDistance
                          ? '${_formatDistance(_distanceKm)} km'
                          : null,
                      durationLabel: _hasDuration ? _clockLabel : null,
                      paceLabel: _isComplete ? _paceLabel : null,
                      background: localBackgroundImage(_backgroundPath!),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          StaggeredFadeIn(
            controller: _entranceController,
            index: sectionIndex++,
            itemCount: _sectionCount,
            child: ShareToFeedToggle(
              value: _shareToFeed,
              subtitle: 'Post this run to your profile activity',
              onChanged: (value) {
                setState(() {
                  _shareToFeed = value;
                });
              },
            ),
          ),
          if (_shareToFeed) ...[
            const SizedBox(height: AppSpacing.md),
            TagPeopleRow(
              tagged: _taggedUsers,
              onTap: _isSaving ? null : _pickTaggedPeople,
            ),
          ],
          if (_errorMessage != null) ...[
            const SizedBox(height: AppSpacing.md),
            _ErrorBanner(message: _errorMessage!),
          ],
          const SizedBox(height: AppSpacing.lg),
          StaggeredFadeIn(
            controller: _entranceController,
            index: sectionIndex++,
            itemCount: _sectionCount,
            child: PrimaryButton(
              icon: _isSaving ? null : Icons.check_rounded,
              label: _isSaving
                  ? 'Saving...'
                  : (_shareToFeed ? 'Save Run & Share' : 'Save Run'),
              onPressed: _isSaving ? null : _saveRun,
            ),
          ),
        ],
      ),
    );
  }
}

/// Run, hike or ride — the choice that everything below it answers to.
///
/// Three segments on one pane rather than three tiles on the Create page. The
/// activities differ in their numbers, not in what you do to start one, so
/// putting the choice here keeps the Create page at five rows and lets the
/// selection recolour the card you are about to tap.
class _ActivityPicker extends StatelessWidget {
  const _ActivityPicker({required this.selected, required this.onChanged});

  final ActivityKind selected;
  final ValueChanged<ActivityKind> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return LiquidGlass(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: palette.stroke),
        ),
        child: Row(
          children: [
            for (final kind in ActivityDescriptor.gpsKinds)
              Expanded(
                child: _ActivitySegment(
                  kind: kind,
                  isSelected: kind == selected,
                  onTap: () => onChanged(kind),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ActivitySegment extends StatelessWidget {
  const _ActivitySegment({
    required this.kind,
    required this.isSelected,
    required this.onTap,
  });

  final ActivityKind kind;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final descriptor = kind.descriptor;
    // Through the palette rather than raw: the fixed hues are set for the dark
    // theme and glare on the cream one if painted straight.
    final accent = palette.accent(descriptor.accent);

    return Semantics(
      selected: isSelected,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm + 2),
          decoration: BoxDecoration(
            color: isSelected
                ? palette.accentFill(descriptor.accent)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                descriptor.icon,
                size: 18,
                color: isSelected ? accent : palette.muted,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  descriptor.singular,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isSelected ? accent : palette.muted,
                    fontSize: 13.5,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The primary way into a session: a solid gradient card that reads as the
/// recommended path before the manual form does.
///
/// Takes its hue from the selected activity, so tapping a segment above
/// visibly changes the thing you are about to start rather than only changing
/// a word.
class _GpsHeroCard extends StatelessWidget {
  const _GpsHeroCard({required this.kind, required this.onTap});

  final ActivityKind kind;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final descriptor = kind.descriptor;
    // Every kind takes its own accent — a run is blue, same as its segment and
    // its feed cards — darkened one step for the far end of the gradient.
    final accent = palette.accent(descriptor.accent);
    final gradientStart = accent;
    final gradientEnd = Color.lerp(accent, const Color(0xFF1A120B), 0.32)!;
    final subtitle = descriptor.usesPace
        ? 'Real-time distance, pace and route map'
        : 'Real-time distance, speed and route map';

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: [
          BoxShadow(
            color: gradientStart.withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.card),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [gradientStart, gradientEnd],
            ),
          ),
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg - 4),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      // On the accent fill, so the white is fixed in both
                      // themes — same rule as AppColors.onBrand.
                      color: AppColors.onBrand.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      descriptor.icon,
                      color: AppColors.onBrand,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Track live with GPS',
                          style: TextStyle(
                            color: AppColors.onBrand,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            color: AppColors.onBrand,
                            fontSize: 12.5,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    color: AppColors.onBrand,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The indoor way in, sitting directly under the GPS card.
///
/// Deliberately the quieter of the two: it is the same live tracking, minus the
/// one signal a treadmill can't give — so it reads as the alternative to the
/// accent card above rather than a second recommendation competing with it.
class _TreadmillCard extends StatelessWidget {
  const _TreadmillCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return LiquidGlass(
      // Material stays for the ink splash and gives up its colour:
      // an opaque fill in there would sit between the glass and
      // everything it is meant to bend.
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.card),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: palette.stroke),
            ),
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: palette.brandSoft,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.timer_outlined,
                    color: palette.brand,
                    size: 22,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Treadmill run',
                        style: TextStyle(
                          color: palette.text,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Press start and the timer runs — no GPS needed',
                        style: TextStyle(
                          color: palette.muted,
                          fontSize: 12.5,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Icon(
                  Icons.arrow_forward_rounded,
                  color: palette.muted,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LabelledDivider extends StatelessWidget {
  const _LabelledDivider({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final rule = Expanded(child: Container(height: 1, color: palette.stroke));

    return Row(
      children: [
        rule,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label.toUpperCase(),
            style: TextStyle(
              color: palette.muted,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
        ),
        rule,
      ],
    );
  }
}

/// A big centred numeric well with its unit pinned to the right.
class _MetricField extends StatelessWidget {
  const _MetricField({
    required this.icon,
    required this.label,
    required this.controller,
    required this.suffix,
    required this.hint,
    required this.decimal,
    required this.invalid,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final TextEditingController controller;
  final String suffix;
  final String hint;
  final bool decimal;
  final bool invalid;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FormSectionHeader(icon: icon, label: label),
        // The same well the workout form uses, so a number typed on one screen
        // sits in the same material as a number typed on the other.
        GlassWell(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          borderColor: invalid ? palette.danger : null,
          child: Row(
            children: [
              // Balances the unit on the right so the number stays optically
              // centred in the well.
              SizedBox(width: _suffixWidth(suffix)),
              Expanded(
                child: TextField(
                  controller: controller,
                  onChanged: onChanged,
                  keyboardType: decimal
                      ? const TextInputType.numberWithOptions(decimal: true)
                      : TextInputType.number,
                  textAlign: TextAlign.center,
                  cursorColor: palette.brand,
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 18),
                    border: InputBorder.none,
                    hintText: hint,
                    hintStyle: TextStyle(
                      color: palette.muted.withValues(alpha: 0.5),
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: _suffixWidth(suffix),
                child: Text(
                  suffix,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: palette.muted,
                    fontSize: 15,
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

  static double _suffixWidth(String suffix) => suffix.length * 9.0 + 6;
}

/// The read-out that slides in once both fields are filled: what the run will
/// look like on the feed.
class _RunSummary extends StatelessWidget {
  const _RunSummary({
    required this.distance,
    required this.duration,
    required this.pace,
    required this.paceLabel,
  });

  final String distance;
  final String duration;
  final String pace;

  /// "Avg pace" or "Avg speed" — a ride's headline figure is neither measured
  /// nor named the way a run's is.
  final String paceLabel;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return DarkCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      // The brand wash goes under the lens and arrives bent, rather than
      // sitting on top as the one flat surface on the page.
      backdrop: GlassBloom(colors: [palette.brand]),
      child: Row(
        children: [
          Expanded(child: _SummaryStat(label: 'Distance', value: distance)),
          _SummaryRule(color: palette.stroke),
          Expanded(child: _SummaryStat(label: 'Time', value: duration)),
          _SummaryRule(color: palette.stroke),
          Expanded(child: _SummaryStat(label: paceLabel, value: pace)),
        ],
      ),
    );
  }
}

class _SummaryRule extends StatelessWidget {
  const _SummaryRule({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 32, color: color);
  }
}

class _SummaryStat extends StatelessWidget {
  const _SummaryStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Column(
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: palette.brandText,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: palette.muted,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.danger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.field),
        border: Border.all(color: palette.danger.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, size: 18, color: palette.danger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: palette.danger,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
