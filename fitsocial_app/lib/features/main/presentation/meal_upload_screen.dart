import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/services/instagram_photo_picker.dart';
import '../../../shared/widgets/fit_social_pulse_mark.dart';
import '../../../shared/widgets/primary_button.dart';
import '../application/create_flow_controller.dart';
import '../data/content_repository.dart';

/// Where a meal analysis has got to. Drives the overlay's caption, so what the
/// user is told is what is actually happening rather than one blanket message.
enum _AnalysisStage {
  idle,
  uploading,
  analyzing;

  String get caption => switch (this) {
        _AnalysisStage.idle => '',
        _AnalysisStage.uploading => 'Uploading your photo',
        _AnalysisStage.analyzing => 'Reading your meal',
      };
}

class MealUploadScreen extends ConsumerStatefulWidget {
  const MealUploadScreen({super.key});

  @override
  ConsumerState<MealUploadScreen> createState() => _MealUploadScreenState();
}

class _MealUploadScreenState extends ConsumerState<MealUploadScreen> {
  final ImagePicker _picker = ImagePicker();
  String? _imagePath;
  _AnalysisStage _stage = _AnalysisStage.idle;

  bool get _isBusy => _stage != _AnalysisStage.idle;

  @override
  void initState() {
    super.initState();
    // Android can kill this activity while the system picker is open
    // (low-RAM devices). When that happens the picked image is delivered
    // on the NEXT launch via getLostData — recover it here so the photo
    // the user chose isn't silently dropped.
    _recoverLostImage();
  }

  Future<void> _recoverLostImage() async {
    try {
      final LostDataResponse response = await _picker.retrieveLostData();
      if (response.isEmpty) return;
      final file = response.file;
      if (file != null && mounted) {
        setState(() => _imagePath = file.path);
      }
    } catch (_) {
      // Lost-data recovery is best-effort only.
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final path = await _pickDownscaled(source);
      if (path != null && mounted) {
        setState(() {
          _imagePath = path;
        });
      }
    } on PlatformException catch (e) {
      if (e.code == 'already_active') {
        // A previous pick never completed (interrupted flow). Flush the
        // stuck session and retry once instead of failing outright.
        try {
          await _picker.retrieveLostData();
          final path = await _pickDownscaled(source);
          if (path != null && mounted) {
            setState(() => _imagePath = path);
          }
          return;
        } catch (_) {}
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.code == 'already_active'
                  ? 'The photo picker is busy — please try again.'
                  : 'Could not open the ${source == ImageSource.camera ? 'camera' : 'gallery'}: ${e.message ?? e.code}',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking image: $e')),
        );
      }
    }
  }

  /// Picks a photo and hands the user the crop screen, which also downscales to
  /// 1080px and encodes JPEG at quality 80 (Instagram's feed spec). Keeps
  /// uploads a few hundred KB — full-resolution phone photos can exceed the
  /// 10 MB Storage rules cap and make the AI analysis slow and costly.
  ///
  /// Returns the cropped file's path, or null if the user backed out.
  Future<String?> _pickDownscaled(ImageSource source) {
    return InstagramPhotoPicker.pickAndCrop(
      context: context,
      source: source,
    );
  }

  Future<void> _analyzeAndNavigate() async {
    if (_imagePath == null) return;

    setState(() {
      _stage = _AnalysisStage.uploading;
    });

    try {
      final repository = ref.read(contentRepositoryProvider);

      // Step 1: Upload to Firebase Storage
      final imageUrl = await repository.uploadMealImage(_imagePath!);
      if (!mounted) return;
      setState(() {
        _stage = _AnalysisStage.analyzing;
      });

      // Step 2: Call the Cloud Function to analyze the meal
      Map<String, dynamic> analysisData;
      try {
        analysisData = await repository.analyzeMealImage(imageUrl);
      } catch (analysisError) {
        // If analysis fails, still continue with just the image URL so the
        // user can fill in the fields manually.
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'AI analysis failed. You can fill in the details manually.',
              ),
            ),
          );
          ref.read(createFlowControllerProvider.notifier).updateMeal(
                MealDraftState(imageUrl: imageUrl),
              );
          context.push('/meal-review');
        }
        return;
      }

      // Step 3: Push the AI results into the meal draft the review screen
      // reads from, then navigate. (Passing via `extra` alone was ignored by
      // the review screen, so the analysis was being dropped.)
      if (mounted) {
        ref.read(createFlowControllerProvider.notifier).updateMeal(
              MealDraftState.fromAnalysis(analysisData, imageUrl: imageUrl),
            );
        context.push('/meal-review');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _stage = _AnalysisStage.idle;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final hasPhoto = _imagePath != null;

    // The scrim has to cover the app bar and the action bar as well as the
    // page, so the Scaffold sits inside the Stack rather than hosting it.
    return Stack(
      children: [
        Scaffold(
          backgroundColor: palette.background,
          appBar: AppBar(
            title: const Text('Upload Meal'),
            backgroundColor: Colors.transparent,
          ),
          body: hasPhoto ? _buildPhotoState(context) : _buildEmptyState(context),
          bottomNavigationBar: _buildActions(context, hasPhoto: hasPhoto),
        ),
        if (_isBusy) _AnalyzingOverlay(stage: _stage),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final palette = context.palette;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 128,
              height: 128,
              decoration: BoxDecoration(
                color: AppColors.orangeBright.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(36),
                border: Border.all(
                  color: AppColors.orangeBright.withValues(alpha: 0.28),
                ),
              ),
              child: const Icon(
                Icons.photo_camera_rounded,
                size: 48,
                color: AppColors.orangeBright,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const Text(
              'Snap your meal',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'FitSocial reads the plate — or the packet label — and fills in '
              'the calories and macros for you.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.muted,
                fontSize: 14,
                height: 1.45,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                _TipChip('Good light'),
                _TipChip('Whole plate in frame'),
                _TipChip('Labels work too'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoState(BuildContext context) {
    final palette = context.palette;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Stack(
              children: [
                // A fixed 4:5 frame — the crop step's default and most-used
                // ratio — rather than a box sized to the photo. It holds its
                // height while the file decodes, so the page doesn't jump, and
                // `contain` means a square or landscape crop is letterboxed on
                // the media backdrop instead of being cut into.
                AspectRatio(
                  aspectRatio: 4 / 5,
                  child: ColoredBox(
                    color: AppColors.mediaBackdrop,
                    child: kIsWeb
                        ? Image.network(_imagePath!, fit: BoxFit.contain)
                        : Image.file(File(_imagePath!), fit: BoxFit.contain),
                  ),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: _GlassButton(
                    icon: Icons.refresh_rounded,
                    label: 'Change photo',
                    onTap: _isBusy
                        ? null
                        : () => setState(() => _imagePath = null),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.auto_awesome_rounded,
                size: 16,
                color: palette.brandText,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'The analysis is a starting point — every number is yours to '
                  'edit on the next screen.',
                  style: TextStyle(
                    color: palette.muted,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Pinned under the page, inside a [SafeArea] so the buttons clear the
  /// gesture pill or the three-button nav instead of sitting under them.
  Widget _buildActions(BuildContext context, {required bool hasPhoto}) {
    final palette = context.palette;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.background,
        border: Border(top: BorderSide(color: palette.stroke)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: hasPhoto
              ? PrimaryButton(
                  label: 'Analyze Meal',
                  icon: Icons.auto_awesome_rounded,
                  onPressed: _isBusy ? null : _analyzeAndNavigate,
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PrimaryButton(
                      label: 'Take Photo',
                      icon: Icons.photo_camera_rounded,
                      onPressed: () => _pickImage(ImageSource.camera),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    SizedBox(
                      height: 52,
                      child: OutlinedButton.icon(
                        onPressed: () => _pickImage(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library_rounded, size: 18),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: palette.text,
                          side: BorderSide(color: palette.stroke),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        label: const Text(
                          'Upload from Gallery',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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

/// The scan curtain: the whole screen goes quiet behind a shade of the theme's
/// own background — cream on the light theme, near-black on the dark one — and
/// the pulsing F holds the centre until the analysis returns.
class _AnalyzingOverlay extends StatelessWidget {
  const _AnalyzingOverlay({required this.stage});

  final _AnalysisStage stage;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Positioned.fill(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
        builder: (context, t, child) => Opacity(opacity: t, child: child),
        // Absorbs everything: the page underneath must not be touchable while
        // its photo is being uploaded.
        child: AbsorbPointer(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              color: palette.background.withValues(alpha: 0.86),
              child: Material(
                type: MaterialType.transparency,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const FitSocialPulseMark(width: 148),
                      const SizedBox(height: AppSpacing.xl),
                      // Swapped rather than rewritten, so the caption changing
                      // reads as progress instead of a flicker.
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 240),
                        child: Text(
                          stage.caption,
                          key: ValueKey(stage),
                          style: TextStyle(
                            color: palette.text,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Hang tight — this takes a few seconds.',
                        style: TextStyle(
                          color: palette.muted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TipChip extends StatelessWidget {
  const _TipChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.stroke),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_rounded, size: 13, color: palette.brandText),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: palette.muted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// A control that sits on a photo, so its colours are fixed rather than
/// theme-dependent — the backdrop is the user's own image either way.
class _GlassButton extends StatelessWidget {
  const _GlassButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0x66000000),
      shape: const StadiumBorder(
        side: BorderSide(color: Color(0x33FFFFFF)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: AppColors.onMedia),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.onMedia,
                  fontSize: 12,
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
