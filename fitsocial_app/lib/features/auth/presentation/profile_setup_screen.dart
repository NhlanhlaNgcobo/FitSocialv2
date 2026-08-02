import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/dark_card.dart';
import '../../../shared/widgets/fit_social_logo.dart';
import '../../../shared/widgets/primary_button.dart';
import '../application/app_session.dart';

class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  late final TextEditingController _displayNameController;
  late final TextEditingController _handleController;
  late final TextEditingController _bioController;
  late final TextEditingController _locationController;
  final ImagePicker _picker = ImagePicker();
  String? _imagePath;

  /// Preview of the freshly picked photo. On web image_picker returns a blob:
  /// URL and dart:io's File is a stub that throws when read, so the blob is
  /// fetched over the network instead.
  ImageProvider? get _pickedAvatar {
    final path = _imagePath;
    if (path == null) return null;
    if (kIsWeb) return NetworkImage(path);
    return FileImage(File(path));
  }

  @override
  void initState() {
    super.initState();
    _displayNameController = TextEditingController();
    _handleController = TextEditingController();
    _bioController = TextEditingController();
    _locationController = TextEditingController();
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _handleController.dispose();
    _bioController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(appSessionProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Set up profile')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          const FitSocialLogo(size: 36, animated: false),
          const SizedBox(height: AppSpacing.md),
          const Text(
            'A quick profile makes the feed and community features feel personal from day one.',
            style: TextStyle(color: AppColors.muted, fontSize: 15, height: 1.5),
          ),
          const SizedBox(height: AppSpacing.lg),
          DarkCard(
            child: Row(
              children: [
                GestureDetector(
                  onTap: () async {
                    final XFile? image = await _picker.pickImage(
                      source: ImageSource.gallery,
                      maxWidth: 800,
                      maxHeight: 800,
                      imageQuality: 85,
                    );
                    if (image != null && mounted) {
                      setState(() {
                        _imagePath = image.path;
                      });
                    }
                  },
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 34,
                        backgroundColor: AppColors.surfaceHigh,
                        backgroundImage: _pickedAvatar,
                        child: _imagePath == null
                            ? const Icon(Icons.person_rounded,
                                size: 36, color: AppColors.orangeBright)
                            : null,
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.orangeBright,
                          ),
                          child: const Icon(
                            Icons.camera_alt_rounded,
                            color: AppColors.white,
                            size: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Profile photo',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 17),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _imagePath != null
                            ? 'Photo selected — it will upload when you save.'
                            : 'Tap to choose a photo from your gallery.',
                        style: const TextStyle(color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const _InputLabel(label: 'Display Name'),
          const SizedBox(height: 8),
          TextField(controller: _displayNameController),
          const SizedBox(height: AppSpacing.md),
          const _InputLabel(label: 'Handle'),
          const SizedBox(height: 8),
          TextField(controller: _handleController),
          const SizedBox(height: AppSpacing.md),
          const _InputLabel(label: 'Bio'),
          const SizedBox(height: 8),
          TextField(controller: _bioController, maxLines: 3),
          const SizedBox(height: AppSpacing.md),
          const _InputLabel(label: 'Location'),
          const SizedBox(height: 8),
          TextField(controller: _locationController),
          const SizedBox(height: AppSpacing.lg),
          if (session.errorMessage != null) ...[
            _SetupErrorBanner(message: session.errorMessage!),
            const SizedBox(height: AppSpacing.md),
          ],
          PrimaryButton(
            label: session.isLoading ? 'Saving...' : 'Complete Setup',
            onPressed: session.isLoading
                ? null
                : () {
                    // Routing happens off the session's auth stage, which only
                    // advances on success — a failure leaves the user here with
                    // the error shown above.
                    ref.read(appSessionProvider).completeProfile(
                          displayName: _displayNameController.text,
                          handle: _handleController.text,
                          bio: _bioController.text,
                          location: _locationController.text,
                          avatarLocalPath: _imagePath,
                        );
                  },
          ),
        ],
      ),
    );
  }
}

/// Surfaces a failed profile save (e.g. a denied avatar upload) instead of
/// leaving the user on a screen that appears to do nothing.
class _SetupErrorBanner extends StatelessWidget {
  const _SetupErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.danger),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded,
              color: AppColors.danger, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AppColors.danger, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _InputLabel extends StatelessWidget {
  const _InputLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: AppColors.white,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}
