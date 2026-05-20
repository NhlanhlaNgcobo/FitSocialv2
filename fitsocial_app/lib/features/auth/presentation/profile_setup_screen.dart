import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  @override
  void initState() {
    super.initState();
    _displayNameController = TextEditingController(text: 'Neo M.');
    _handleController = TextEditingController(text: '@neomotion');
    _bioController = TextEditingController(text: 'Running, lifting, and good food.');
    _locationController = TextEditingController(text: 'Johannesburg, SA');
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
          const DarkCard(
            child: Row(
              children: [
                CircleAvatar(
                  radius: 34,
                  backgroundColor: AppColors.surfaceHigh,
                  child: Icon(Icons.person_rounded, size: 36, color: AppColors.orangeBright),
                ),
                SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Profile photo',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'We can wire uploads to Firebase Storage next.',
                        style: TextStyle(color: AppColors.muted),
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
          PrimaryButton(
            label: session.isLoading ? 'Saving...' : 'Complete Setup',
            onPressed: session.isLoading
                ? null
                : () {
                    ref.read(appSessionProvider).completeProfile(
                          displayName: _displayNameController.text,
                          handle: _handleController.text,
                          bio: _bioController.text,
                          location: _locationController.text,
                        );
                  },
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
