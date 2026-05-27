import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(appSessionProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Edit Profile')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
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
          PrimaryButton(
            label: session.isLoading ? 'Saving...' : 'Save Changes',
            onPressed: session.isLoading
                ? null
                : () async {
                    await ref.read(appSessionProvider).completeProfile(
                          displayName: _displayNameController.text,
                          handle: _handleController.text,
                          bio: _bioController.text,
                          location: _locationController.text,
                        );
                    if (context.mounted) {
                      context.pop();
                    }
                  },
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
