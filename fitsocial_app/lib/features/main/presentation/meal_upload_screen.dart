import '../../../shared/widgets/quick_toast.dart';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show Uint8List;
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
import '../../music/presentation/music_island_action.dart';
import '../../../shared/widgets/liquid_glass.dart';

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
  /// The photo, held in memory from the moment it is picked. The upload sends
  /// these bytes rather than re-reading a file the OS may have cleared while
  /// the user was on this screen.
  Uint8List? _imageBytes;
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
      if (file != null) await _holdPhoto(file.path);
    } catch (_) {
      // Lost-data recovery is best-effort only.
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final path = await _pickDownscaled(source);
      if (path != null) await _holdPhoto(path);
    } on PlatformException catch (e) {
      if (e.code == 'already_active') {
        // A previous pick never completed (interrupted flow). Flush the
        // stuck session and retry once instead of failing outright.
        try {
          await _picker.retrieveLostData();
          final path = await _pickDownscaled(source);
          if (path != null) await _holdPhoto(path);
          return;
        } catch (_) {}
      }
      if (mounted) {
        showQuickToast(
          context,
          e.code == 'already_active'
              ? 'The photo picker is busy — try again.'
              : "Couldn't open the "
                  '${source == ImageSource.camera ? 'camera' : 'gallery'}.',
          icon: Icons.error_outline_rounded,
          tone: ToastTone.danger,
        );
      }
    } catch (e) {
      if (mounted) {
        debugPrint('Picking an image failed: $e');
        showQuickToast(
          context,
          "Couldn't open your photos. Try again.",
          icon: Icons.error_outline_rounded,
          tone: ToastTone.danger,
        );
      }
    }
  }

  /// Picks a photo and hands the user the crop screen, which also downscales to
  /// 1080px and encodes JPEG at quality 80 (Instagram's feed spec). Keeps
  /// uploads a few hundred KB — full-resolution phone photos can exceed the
  /// 10 MB Storage rules cap and make the AI analysis slow and costly.
  ///
  /// Reads the picked photo into memory straight away, while the file is
  /// guaranteed to exist, and shows it. Uses XFile so web's blob: URLs work.
  Future<void> _holdPhoto(String path) async {
    final Uint8List bytes;
    try {
      bytes = await XFile(path).readAsBytes();
    } catch (_) {
      if (mounted) {
        showQuickToast(
          context,
          "Couldn't load that photo. Please try again.",
          tone: ToastTone.danger,
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() => _imageBytes = bytes);
  }

  /// Returns the cropped file's path, or null if the user backed out.
  Future<String?> _pickDownscaled(ImageSource source) {
    return InstagramPhotoPicker.pickAndCrop(
      context: context,
      source: source,
    );
  }

  Future<void> _analyzeAndNavigate() async {
    final bytes = _imageBytes;
    if (bytes == null) return;

    setState(() {
      _stage = _AnalysisStage.uploading;
    });

    try {
      final repository = ref.read(contentRepositoryProvider);

      // Step 1: Upload to Firebase Storage
      final imageUrl = await repository.uploadMealImageBytes(bytes);
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
          showQuickToast(
            context,
            'Analysis failed — fill the details in yourself.',
            icon: Icons.info_outline_rounded,
            visibleFor: const Duration(milliseconds: 2600),
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
        debugPrint('Meal upload failed: $e');
        showQuickToast(
          context,
          "Couldn't upload that photo. Try again.",
          icon: Icons.error_outline_rounded,
          tone: ToastTone.danger,
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
    final hasPhoto = _imageBytes != null;

    // The scrim has to cover the app bar and the action bar as well as the
    // page, so the Scaffold sits inside the Stack rather than hosting it.
    return Stack(
      children: [
        Scaffold(
          // Transparent so this page sits on the app's one backdrop, the
          // same ground every other screen looks through.
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: const Text('Upload Meal'),
            backgroundColor: Colors.transparent,
            actions: const [MusicIslandAction()],
          ),
          body:
              hasPhoto ? _buildPhotoState(context) : _buildEmptyState(context),
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
                color: palette.brandSoft,
                borderRadius: BorderRadius.circular(36),
                border: Border.all(color: palette.brandSoftStroke),
              ),
              child: Icon(
                Icons.photo_camera_rounded,
                size: 48,
                color: palette.brand,
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
            borderRadius: BorderRadius.circular(AppRadius.card),
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
                    child: Image.memory(_imageBytes!, fit: BoxFit.contain),
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
                        : () => setState(() => _imageBytes = null),
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

    return LiquidGlass(
      // Painted by the lens rather than by a fill of its own: a pane
      // over the app backdrop, like every other card.
      borderRadius: BorderRadius.circular(0),
      child: DecoratedBox(
        decoration: BoxDecoration(
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
                          icon:
                              const Icon(Icons.photo_library_rounded, size: 18),
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
        // The blur ramps in; nothing fades over it.
        //
        // Fading the whole overlay meant the BackdropFilter spent its entrance
        // inside an opacity buffer, where there is no backdrop to read -- so
        // the frost drew nothing for 260ms and then snapped on at the end.
        // Ramping sigma and the fill together is the effect that was wanted
        // anyway: the page behind actually goes out of focus.
        builder: (context, t, child) => AbsorbPointer(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 14 * t, sigmaY: 14 * t),
            child: Container(
              color: palette.background.withValues(alpha: 0.86 * t),
              // Inside the filter, so the content can still fade without
              // taking the backdrop away from it.
              child: Opacity(
                opacity: t,
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
