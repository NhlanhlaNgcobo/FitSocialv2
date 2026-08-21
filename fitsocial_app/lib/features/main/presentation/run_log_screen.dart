import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/services/instagram_photo_picker.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/quick_toast.dart';
import '../../../shared/widgets/run_background_section.dart';
import '../../../shared/widgets/share_to_feed_toggle.dart';
import '../../../shared/widgets/staggered_fade_in.dart';
import '../application/activity_actions.dart';
import '../domain/app_models.dart';
import '../../music/presentation/music_island_action.dart';
import '../../../shared/widgets/liquid_glass.dart';

class RunLogScreen extends ConsumerStatefulWidget {
  const RunLogScreen({super.key});

  @override
  ConsumerState<RunLogScreen> createState() => _RunLogScreenState();
}

class _RunLogScreenState extends ConsumerState<RunLogScreen>
    with SingleTickerProviderStateMixin {
  static const int _sectionCount = 7;

  late final AnimationController _entranceController;
  late final TextEditingController _distanceController;
  late final TextEditingController _durationController;

  double _distanceKm = 0;
  int _durationMinutes = 0;
  bool _shareToFeed = true;
  bool _isSaving = false;

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
  bool get _hasDuration => _durationMinutes > 0;
  bool get _isComplete => _hasDistance && _hasDuration;

  /// `m:ss /km`, the same shape this screen has always saved.
  String get _paceLabel {
    if (!_isComplete) return '--';
    final pace = _durationMinutes / _distanceKm;
    final mins = pace.floor();
    final secs = ((pace - mins) * 60).round().toString().padLeft(2, '0');
    return '$mins:$secs /km';
  }

  String get _durationLabel {
    if (!_hasDuration) return '--';
    final hours = _durationMinutes ~/ 60;
    final mins = _durationMinutes % 60;
    if (hours == 0) return '$mins min';
    return mins == 0 ? '${hours}h' : '${hours}h ${mins}m';
  }

  /// The elapsed time as the *post* will carry it — a clock, not a phrase.
  ///
  /// Deliberately not [_durationLabel]: the card below is a preview of what
  /// gets shared, and a preview that reads "45 min" where the post will read
  /// "45:00" is a preview of something else.
  String get _clockLabel {
    final hours = _durationMinutes ~/ 60;
    final mins = (_durationMinutes % 60).toString().padLeft(2, '0');
    return hours == 0 ? '$mins:00' : '$hours:$mins:00';
  }

  static String _formatDistance(double value) {
    var text = value.toStringAsFixed(2);
    if (text.contains('.')) {
      text = text.replaceFirst(RegExp(r'0+$'), '');
      text = text.replaceFirst(RegExp(r'\.$'), '');
    }
    return text;
  }

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
              elapsed: Duration(minutes: _durationMinutes),
              averagePace: _paceLabel,
              shareToFeed: _shareToFeed,
              backgroundImagePath: _backgroundPath,
            ),
          );
      if (!mounted) return;
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
        title: const Text('Log Run'),
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
            child: _GpsHeroCard(onTap: () => context.push('/live-run')),
          ),
          const SizedBox(height: AppSpacing.sm + 4),
          StaggeredFadeIn(
            controller: _entranceController,
            index: sectionIndex++,
            itemCount: _sectionCount,
            child: _TreadmillCard(
              onTap: () => context.push('/treadmill-run'),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          StaggeredFadeIn(
            controller: _entranceController,
            index: sectionIndex++,
            itemCount: _sectionCount,
            child: const _LabelledDivider(label: 'or log it manually'),
          ),
          const SizedBox(height: AppSpacing.lg),
          StaggeredFadeIn(
            controller: _entranceController,
            index: sectionIndex++,
            itemCount: _sectionCount,
            child: LiquidGlass(
              // Painted by the lens rather than by a fill of its own: a pane
              // over the app backdrop, like every other card.
              borderRadius: BorderRadius.circular(24),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
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
                          _distanceKm = double.tryParse(value.trim()) ?? 0;
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
                      decimal: false,
                      invalid: _showFieldErrors && !_hasDuration,
                      onChanged: (value) {
                        setState(() {
                          _durationMinutes = int.tryParse(value.trim()) ?? 0;
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
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 240),
              opacity: _isComplete ? 1 : 0,
              child: _isComplete
                  ? Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.md),
                      child: _RunSummary(
                        distance: '${_formatDistance(_distanceKm)} km',
                        duration: _durationLabel,
                        pace: _paceLabel,
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          StaggeredFadeIn(
            controller: _entranceController,
            index: sectionIndex++,
            itemCount: _sectionCount,
            child: RunBackgroundSection(
              imagePath: _backgroundPath,
              distanceLabel:
                  _hasDistance ? '${_formatDistance(_distanceKm)} km' : null,
              durationLabel: _hasDuration ? _clockLabel : null,
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

/// The primary way into a run: a solid brand-orange card that reads as the
/// recommended path before the manual form does.
class _GpsHeroCard extends StatelessWidget {
  const _GpsHeroCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: palette.brand.withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [palette.brand, AppColors.orange],
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
                      // On the orange fill, so the white is fixed in both
                      // themes — same rule as AppColors.onBrand.
                      color: AppColors.onBrand.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.gps_fixed_rounded,
                      color: AppColors.onBrand,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Track live with GPS',
                          style: TextStyle(
                            color: AppColors.onBrand,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Real-time distance, pace and route map',
                          style: TextStyle(
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
/// orange card above rather than a second recommendation competing with it.
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
      borderRadius: BorderRadius.circular(20),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
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
        Row(
          children: [
            Icon(icon, size: 16, color: palette.muted),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: palette.text,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        LiquidGlass(
          // Painted by the lens rather than by a fill of its own: a pane
          // over the app backdrop, like every other card.
          borderRadius: BorderRadius.circular(18),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: invalid ? palette.danger : palette.stroke,
                width: invalid ? 1.4 : 1,
              ),
            ),
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
  });

  final String distance;
  final String duration;
  final String pace;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: palette.brandSoft,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.brandSoftStroke),
      ),
      child: Row(
        children: [
          Expanded(child: _SummaryStat(label: 'Distance', value: distance)),
          _SummaryRule(color: palette.stroke),
          Expanded(child: _SummaryStat(label: 'Time', value: duration)),
          _SummaryRule(color: palette.stroke),
          Expanded(child: _SummaryStat(label: 'Avg pace', value: pace)),
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
        borderRadius: BorderRadius.circular(16),
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
