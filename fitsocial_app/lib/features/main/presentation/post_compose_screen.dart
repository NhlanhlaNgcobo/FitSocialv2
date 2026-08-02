import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/services/instagram_photo_picker.dart';
import '../../../shared/widgets/primary_button.dart';
import '../application/activity_actions.dart';
import '../application/create_flow_controller.dart';
import '../data/content_repository.dart';
import '../domain/app_models.dart';

class PostComposeScreen extends ConsumerStatefulWidget {
  const PostComposeScreen({super.key});

  @override
  ConsumerState<PostComposeScreen> createState() => _PostComposeScreenState();
}

class _PostComposeScreenState extends ConsumerState<PostComposeScreen> {
  late final TextEditingController _captionController;
  String? _imagePath;
  double? _imageAspectRatio;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final draft = ref.read(createFlowControllerProvider).postDraft;
    _captionController = TextEditingController(text: draft.caption);
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  /// Picks a photo, then hands the user the crop screen so they choose the
  /// framing. The cropper also downscales to 1080px and encodes JPEG at
  /// quality 80, so what comes back is already Instagram-spec.
  Future<void> _pickImage(ImageSource source) async {
    final path = await InstagramPhotoPicker.pickAndCrop(
      context: context,
      source: source,
    );
    // Null means the user backed out of the picker or the cropper — leave any
    // previously chosen photo alone rather than clearing it.
    if (path == null) return;

    // Record the shape the user chose so the feed renders it faithfully
    // instead of forcing every photo into one aspect ratio.
    final ratio = await _readAspectRatio(path);
    if (!mounted) return;
    setState(() {
      _imagePath = path;
      _imageAspectRatio = ratio;
    });
  }

  /// Decodes just enough of the file to read its dimensions. Uses XFile so it
  /// works on web, where the path is a blob: URL rather than a real file.
  Future<double?> _readAspectRatio(String path) async {
    try {
      final bytes = await XFile(path).readAsBytes();
      final image = await decodeImageFromList(bytes);
      if (image.height == 0) return null;
      return image.width / image.height;
    } catch (_) {
      // A missing ratio only costs us the fallback shape, so never let this
      // failure block the post.
      return null;
    }
  }

  Future<void> _sharePost() async {
    final caption = _captionController.text.trim();
    if (caption.isEmpty) {
      setState(() {
        _errorMessage = 'Write a caption before sharing.';
      });
      return;
    }

    ref.read(createFlowControllerProvider.notifier).updatePost(
          PostComposerDraftState(caption: _captionController.text),
        );
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      String? imageUrl;
      if (_imagePath != null) {
        imageUrl = await ref
            .read(contentRepositoryProvider)
            .uploadPostImage(_imagePath!);
      }

      final result = await ref.read(activityActionsProvider).sharePost(
            PostDraft(
              caption: caption,
              imageUrl: imageUrl,
              imageAspectRatio: _imageAspectRatio,
            ),
          );
      if (!mounted) return;
      ref.read(createFlowControllerProvider.notifier).completePost(
            result.message,
          );
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
    return Scaffold(
      appBar: AppBar(title: const Text('Share Post')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          GestureDetector(
            onTap: _isSaving ? null : () => _pickImage(ImageSource.gallery),
            child: Container(
              height: 200,
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.stroke),
              ),
              child: _imagePath != null
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          // image_picker hands back a blob: URL on web, where
                          // dart:io's File throws when read.
                          child: kIsWeb
                              ? Image.network(
                                  _imagePath!,
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                )
                              : Image.file(
                                  File(_imagePath!),
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                ),
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: GestureDetector(
                            onTap: _isSaving
                                ? null
                                : () => setState(() => _imagePath = null),
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black54,
                              ),
                              child: const Icon(
                                Icons.close_rounded,
                                color: AppColors.white,
                                size: 18,
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.photo_library_outlined,
                              color: AppColors.orangeBright, size: 42),
                          SizedBox(height: 12),
                          Text('Add photo or workout snapshot'),
                        ],
                      ),
                    ),
            ),
          ),
          if (_imagePath == null) ...[
            const SizedBox(height: AppSpacing.sm),
            Center(
              child: TextButton.icon(
                onPressed:
                    _isSaving ? null : () => _pickImage(ImageSource.camera),
                icon: const Icon(Icons.camera_alt_outlined, size: 18),
                label: const Text('Take Photo'),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          const Text(
            'Caption',
            style:
                TextStyle(color: AppColors.white, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          TextField(
            maxLines: 5,
            controller: _captionController,
            decoration: const InputDecoration(hintText: 'Write a caption'),
            onChanged: (value) {
              ref
                  .read(createFlowControllerProvider.notifier)
                  .updatePost(PostComposerDraftState(caption: value));
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          if (_errorMessage != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.stroke),
              ),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: AppColors.orangeBright),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          PrimaryButton(
            label: _isSaving ? 'Uploading...' : 'Share Post',
            onPressed: _isSaving ? null : _sharePost,
          ),
          if (_isSaving && _imagePath != null)
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
                    'Uploading image...',
                    style: TextStyle(color: AppColors.muted, fontSize: 14),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
