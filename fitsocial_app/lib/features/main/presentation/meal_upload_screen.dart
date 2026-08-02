import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/services/instagram_photo_picker.dart';
import '../../../shared/widgets/dark_card.dart';
import '../../../shared/widgets/primary_button.dart';
import '../application/create_flow_controller.dart';
import '../data/content_repository.dart';

class MealUploadScreen extends ConsumerStatefulWidget {
  const MealUploadScreen({super.key});

  @override
  ConsumerState<MealUploadScreen> createState() => _MealUploadScreenState();
}

class _MealUploadScreenState extends ConsumerState<MealUploadScreen> {
  final ImagePicker _picker = ImagePicker();
  String? _imagePath;
  bool _isAnalyzing = false;

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
      _isAnalyzing = true;
    });

    try {
      final repository = ref.read(contentRepositoryProvider);

      // Step 1: Upload to Firebase Storage
      final imageUrl = await repository.uploadMealImage(_imagePath!);

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
              MealDraftState(
                name: (analysisData['name'] ?? '').toString(),
                calories: (analysisData['calories'] ?? '').toString(),
                protein: (analysisData['protein'] ?? '').toString(),
                carbs: (analysisData['carbs'] ?? '').toString(),
                fat: (analysisData['fat'] ?? '').toString(),
                imageUrl: imageUrl,
              ),
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
          _isAnalyzing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Upload Meal'),
        backgroundColor: Colors.transparent,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_imagePath != null) ...[
                DarkCard(
                  padding: EdgeInsets.zero,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: kIsWeb
                        ? Image.network(
                            _imagePath!,
                            fit: BoxFit.cover,
                            height: 300,
                            width: double.infinity,
                          )
                        : Image.file(
                            File(_imagePath!),
                            fit: BoxFit.cover,
                            height: 300,
                            width: double.infinity,
                          ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                PrimaryButton(
                  label: _isAnalyzing ? 'Analyzing...' : 'Analyze Meal',
                  onPressed: _isAnalyzing ? null : _analyzeAndNavigate,
                ),
                if (_isAnalyzing)
                  const Padding(
                    padding: EdgeInsets.only(top: AppSpacing.md),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.orangeBright,
                          ),
                        ),
                        SizedBox(width: 12),
                        Text(
                          'Uploading & analyzing with AI...',
                          style: TextStyle(color: AppColors.muted, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: AppSpacing.md),
                TextButton(
                  onPressed: _isAnalyzing
                      ? null
                      : () {
                          setState(() {
                            _imagePath = null;
                          });
                        },
                  child: const Text(
                    'Retake or choose another',
                    style: TextStyle(color: AppColors.muted),
                  ),
                ),
              ] else ...[
                const Icon(
                  Icons.camera_alt_outlined,
                  size: 80,
                  color: AppColors.muted,
                ),
                const SizedBox(height: AppSpacing.lg),
                const Text(
                  'Capture or upload a photo of your meal.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted, fontSize: 16),
                ),
                const SizedBox(height: AppSpacing.xl),
                PrimaryButton(
                  label: 'Take Photo',
                  icon: Icons.camera_alt,
                  onPressed: () => _pickImage(ImageSource.camera),
                ),
                const SizedBox(height: AppSpacing.md),
                PrimaryButton(
                  label: 'Upload from Gallery',
                  icon: Icons.photo_library,
                  onPressed: () => _pickImage(ImageSource.gallery),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
