import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/primary_button.dart';
import '../application/app_session.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  late final TextEditingController _displayNameController;
  late final TextEditingController _handleController;
  late final TextEditingController _bioController;
  late final TextEditingController _locationController;
  final ImagePicker _picker = ImagePicker();
  String? _imagePath;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(appSessionProvider).profile;
    _displayNameController =
        TextEditingController(text: profile?.displayName ?? '');
    _handleController = TextEditingController(text: profile?.handle ?? '');
    _bioController = TextEditingController(text: profile?.bio ?? '');
    _locationController = TextEditingController(text: profile?.location ?? '');
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _handleController.dispose();
    _bioController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  ImageProvider? get _avatarImage {
    if (_imagePath != null) {
      // On web image_picker hands back a blob: URL, and dart:io's File is a
      // stub that throws the moment it's read — NetworkImage fetches the blob
      // directly. On mobile the path is a real file.
      if (kIsWeb) return NetworkImage(_imagePath!);
      return FileImage(File(_imagePath!));
    }
    final url = ref.read(appSessionProvider).profile?.avatarUrl;
    if (url != null && url.isNotEmpty) return NetworkImage(url);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(appSessionProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Edit Profile')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Center(
            child: GestureDetector(
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
                    radius: 40,
                    backgroundColor: AppColors.surfaceHigh,
                    backgroundImage: _avatarImage,
                    child: _avatarImage == null
                        ? const Icon(Icons.person_rounded,
                            size: 40, color: AppColors.orangeBright)
                        : null,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.orangeBright,
                      ),
                      child: const Icon(
                        Icons.camera_alt_rounded,
                        color: AppColors.white,
                        size: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const _Label(label: 'Display Name'),
          const SizedBox(height: 8),
          TextField(controller: _displayNameController),
          const SizedBox(height: AppSpacing.md),
          const _Label(label: 'Handle'),
          const SizedBox(height: 8),
          TextField(controller: _handleController),
          const SizedBox(height: AppSpacing.md),
          const _Label(label: 'Bio'),
          const SizedBox(height: 8),
          TextField(controller: _bioController, maxLines: 3),
          const SizedBox(height: AppSpacing.md),
          const _Label(label: 'Location'),
          const SizedBox(height: 8),
          TextField(controller: _locationController),
          const SizedBox(height: AppSpacing.lg),
          if (session.errorMessage != null) ...[
            _ErrorBanner(message: session.errorMessage!),
            const SizedBox(height: AppSpacing.md),
          ],
          PrimaryButton(
            label: session.isLoading ? 'Saving...' : 'Save Changes',
            onPressed: session.isLoading
                ? null
                : () async {
                    final saved =
                        await ref.read(appSessionProvider).completeProfile(
                              displayName: _displayNameController.text,
                              handle: _handleController.text,
                              bio: _bioController.text,
                              location: _locationController.text,
                              avatarLocalPath: _imagePath,
                            );
                    // Stay on the screen when the save failed, so the error is
                    // visible and the user's edits aren't lost.
                    if (saved && context.mounted) {
                      context.pop();
                    }
                  },
          ),
        ],
      ),
    );
  }
}

/// Surfaces a failed save. Without this the error captured on the session is
/// discarded and a denied avatar upload looks like a successful save.
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

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

class _Label extends StatelessWidget {
  const _Label({required this.label});

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
