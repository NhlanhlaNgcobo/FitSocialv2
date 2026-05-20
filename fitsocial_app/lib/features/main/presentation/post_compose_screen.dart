import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/primary_button.dart';
import '../application/activity_actions.dart';
import '../domain/app_models.dart';

class PostComposeScreen extends ConsumerStatefulWidget {
  const PostComposeScreen({super.key});

  @override
  ConsumerState<PostComposeScreen> createState() => _PostComposeScreenState();
}

class _PostComposeScreenState extends ConsumerState<PostComposeScreen> {
  late final TextEditingController _captionController;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _captionController = TextEditingController(
      text: 'Strong session this morning. Staying consistent.',
    );
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _sharePost() async {
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final result = await ref.read(activityActionsProvider).sharePost(
            PostDraft(caption: _captionController.text),
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
    return Scaffold(
      appBar: AppBar(title: const Text('Share Post')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Container(
            height: 200,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.stroke),
            ),
            child: const Center(
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
            label: _isSaving ? 'Sharing...' : 'Share Post',
            onPressed: _isSaving ? null : _sharePost,
          ),
        ],
      ),
    );
  }
}
