import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/observability/app_analytics.dart';
import '../../../shared/identity/profile_identity.dart';
import '../../../shared/services/profile_photo_picker.dart';
import '../../auth/application/app_session.dart';
import '../../auth/application/username_availability_checker.dart';
import '../../auth/data/username_repository.dart';
import '../../auth/domain/username.dart';
import '../../auth/presentation/username_availability_hint.dart';
import '../application/onboarding_controller.dart';
import 'onboarding_chrome.dart';

/// The name the signed-in provider knows the user by, if any — Google's
/// profile name. Empty for email sign-up and in tests with no Firebase app.
final providerDisplayNameProvider = Provider<String>((ref) {
  ref.watch(appSessionProvider);
  try {
    return FirebaseAuth.instance.currentUser?.displayName?.trim() ?? '';
  } on FirebaseException {
    return '';
  }
});

/// Onboarding Step 4: "Claim your name." (spec §4.4). Replaces the old
/// `/profile-setup`.
///
/// The save here is the write that opens `/home`: the session moves to
/// authenticated only once the profile document exists. Everything the
/// earlier steps produced is already on the server by now — see
/// `OnboardingSync` — so home never renders without a goal.
class ClaimNameScreen extends ConsumerStatefulWidget {
  const ClaimNameScreen({super.key});

  /// "Neo M." offers "neom". Lowercased, stripped to the characters a
  /// username may hold, capped at the 20 the rules allow.
  static String suggestUsername(String displayName) {
    final slug =
        displayName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9._]'), '');
    return slug.length > 20 ? slug.substring(0, 20) : slug;
  }

  @override
  ConsumerState<ClaimNameScreen> createState() => _ClaimNameScreenState();
}

class _ClaimNameScreenState extends ConsumerState<ClaimNameScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _handleController;
  late final UsernameAvailabilityChecker _availability;
  String? _imagePath;

  /// Once the user types in the username field, the display name stops
  /// rewriting it. Suggesting is helpful; overwriting is not.
  bool _handleEdited = false;

  bool _attempted = false;

  @override
  void initState() {
    super.initState();
    final providerName = ref.read(providerDisplayNameProvider);
    _nameController = TextEditingController(text: providerName);
    _handleController = TextEditingController(
      text: ClaimNameScreen.suggestUsername(providerName),
    );
    _availability = UsernameAvailabilityChecker(
      ref.read(usernameRepositoryProvider),
    )..addListener(_rebuild);
    _nameController.addListener(_rebuild);
    _handleController.addListener(_rebuild);
    // A prefilled suggestion is as likely to be taken as a typed one.
    if (_handleController.text.isNotEmpty) {
      _availability.check(_handleController.text);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _handleController.dispose();
    _availability
      ..removeListener(_rebuild)
      ..dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  void _onNameChanged(String value) {
    if (_handleEdited) return;
    final suggestion = ClaimNameScreen.suggestUsername(value);
    if (suggestion == _handleController.text) return;
    _handleController.value = TextEditingValue(
      text: suggestion,
      selection: TextSelection.collapsed(offset: suggestion.length),
    );
    _availability.check(suggestion);
  }

  Future<void> _pickPhoto() async {
    final path = await ProfilePhotoPicker.pick(context: context);
    if (path != null && mounted) setState(() => _imagePath = path);
  }

  String? _validateName(String? value) {
    final name = value?.trim() ?? '';
    if (name.isEmpty) return 'Add a name people will recognise.';
    if (name.length < 2) return 'Use at least 2 characters.';
    return null;
  }

  String? _validateHandle(String? value) {
    final formatError = validateUsernameFormat(value);
    if (formatError != null) return formatError;
    final availability = _availability.result;
    if (availability != null && !availability.canUse) {
      return availability.message;
    }
    return null;
  }

  Future<void> _submit() async {
    final session = ref.read(appSessionProvider);
    if (session.isLoading) return;
    FocusScope.of(context).unfocus();
    setState(() => _attempted = true);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // Pressed inside the debounce: finish the lookup rather than drop the
    // press, then judge again on the real answer.
    if (_availability.isChecking) {
      await _availability.settle();
      if (!mounted) return;
      if (!(_formKey.currentState?.validate() ?? false)) return;
    }

    final saved = await session.completeProfile(
      displayName: _nameController.text,
      handle: _handleController.text,
      bio: '',
      location: '',
      avatarLocalPath: _imagePath,
    );
    // The router moves on by itself once the stage changes. The in-memory
    // answers go with it, so a later sign-out starts Step 1 fresh.
    if (saved && mounted) {
      // Firebase takes no booleans, so 0 or 1.
      ref.read(appAnalyticsProvider).log(
        AnalyticsEvent.onboardingIdentitySaved,
        {'had_photo': _imagePath == null ? 0 : 1},
      );
      ref.invalidate(onboardingControllerProvider);
    }
  }

  /// Back from here means leaving the account half-made. Confirmed first,
  /// because it signs out.
  Future<void> _back() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Go back?'),
        content: const Text(
          "You'll be signed out. Your answers are kept, so you can pick up "
          'where you left off.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Go back'),
          ),
        ],
      ),
    );
    if (leave != true || !mounted) return;
    final router = GoRouter.of(context);
    ref.read(appAnalyticsProvider).log(
      AnalyticsEvent.onboardingAbandoned,
      {'last_screen': 'name'},
    );
    await ref.read(appSessionProvider).abandonSignUp();
    router.go('/onboarding/plan');
  }

  ImageProvider? get _pickedAvatar {
    final path = _imagePath;
    if (path == null) return null;
    if (kIsWeb) return NetworkImage(path);
    return FileImage(File(path));
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(appSessionProvider);
    final error = _attempted ? session.errorMessage : null;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: AppColors.mediaBackdrop,
        body: OnboardingBackdrop(
          photo: OnboardingPhotos.gym,
          photoFraction: 0.32,
          child: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.md,
                      AppSpacing.lg,
                      AppSpacing.md,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        OnboardingHeader(step: 4, onBack: _back),
                        const SizedBox(height: AppSpacing.lg),
                        const OnboardingEyebrow('One last thing'),
                        const SizedBox(height: AppSpacing.xs),
                        const OnboardingHeadline('Claim your name.'),
                        const SizedBox(height: AppSpacing.xs),
                        const Text(
                          'This is how people find you on FitSocial.',
                          style: TextStyle(
                            color: AppColors.onMediaMuted,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        _ProfileCard(
                          formKey: _formKey,
                          avatar: _pickedAvatar,
                          initials: avatarInitials(_nameController.text),
                          onPickPhoto: session.isLoading ? null : _pickPhoto,
                          nameController: _nameController,
                          handleController: _handleController,
                          availability: _availability,
                          onNameChanged: _onNameChanged,
                          onHandleChanged: (value) {
                            _handleEdited = true;
                            _availability.check(value);
                          },
                          validateName: _validateName,
                          validateHandle: _validateHandle,
                        ),
                        if (error != null) ...[
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            error,
                            style: const TextStyle(
                              color: Color(0xFFFF8A80),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.sm,
                    AppSpacing.lg,
                    AppSpacing.md,
                  ),
                  child: OnboardingCta(
                    label: session.isLoading ? 'Saving…' : 'Start training',
                    onPressed: session.isLoading ? null : _submit,
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

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.formKey,
    required this.avatar,
    required this.initials,
    required this.onPickPhoto,
    required this.nameController,
    required this.handleController,
    required this.availability,
    required this.onNameChanged,
    required this.onHandleChanged,
    required this.validateName,
    required this.validateHandle,
  });

  final GlobalKey<FormState> formKey;
  final ImageProvider? avatar;
  final String initials;
  final VoidCallback? onPickPhoto;
  final TextEditingController nameController;
  final TextEditingController handleController;
  final UsernameAvailabilityChecker availability;
  final ValueChanged<String> onNameChanged;
  final ValueChanged<String> onHandleChanged;
  final FormFieldValidator<String> validateName;
  final FormFieldValidator<String> validateHandle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.card + 4),
        border: Border.all(color: AppColors.onMedia.withValues(alpha: 0.1)),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            onboardingSurface.withValues(alpha: 0.96),
            const Color(0xF20C0C0C),
          ],
        ),
      ),
      child: Form(
        key: formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: _AvatarPicker(
                avatar: avatar,
                initials: initials,
                onTap: onPickPhoto,
              ),
            ),
            const SizedBox(height: AppSpacing.sm + 2),
            const Center(
              child: Text(
                'Add one now, or later from your profile.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.onMediaMuted, fontSize: 14),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const _FieldLabel('Display name'),
            TextFormField(
              controller: nameController,
              onChanged: onNameChanged,
              validator: validateName,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              maxLength: 40,
              style: _fieldText,
              decoration: _decoration(),
            ),
            const SizedBox(height: AppSpacing.xs),
            const _FieldLabel('Username'),
            TextFormField(
              controller: handleController,
              onChanged: onHandleChanged,
              validator: validateHandle,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.done,
              maxLength: 20,
              style: _fieldText,
              decoration: _decoration(
                prefix: const Text('@', style: _fieldText),
                suffix: AnimatedBuilder(
                  animation: availability,
                  builder: (context, _) {
                    if (availability.isChecking) {
                      return const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.onMediaMuted,
                          ),
                        ),
                      );
                    }
                    final usable = availability.result?.canUse;
                    if (usable == null) return const SizedBox.shrink();
                    return Icon(
                      usable ? Icons.check_circle_rounded : Icons.error_rounded,
                      color: usable
                          ? const Color(0xFF34C759)
                          : const Color(0xFFFF8A80),
                      size: 26,
                    );
                  },
                ),
              ),
            ),
            UsernameAvailabilityHint(checker: availability),
          ],
        ),
      ),
    );
  }

  static const _fieldText = TextStyle(
    color: AppColors.onMedia,
    fontSize: 17,
    fontWeight: FontWeight.w700,
  );

  static InputDecoration _decoration({Widget? prefix, Widget? suffix}) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.field),
      borderSide: BorderSide(color: AppColors.onMedia.withValues(alpha: 0.14)),
    );
    return InputDecoration(
      filled: true,
      fillColor: const Color(0xFF0A0A0A),
      counterText: '',
      prefix: prefix,
      suffixIcon: suffix,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md + 2,
        vertical: AppSpacing.md + 2,
      ),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: const BorderSide(color: AppColors.orangeBright),
      ),
      errorStyle: const TextStyle(color: Color(0xFFFF8A80)),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(
        text,
        style: const TextStyle(color: AppColors.onMediaMuted, fontSize: 14),
      ),
    );
  }
}

/// Orange-ringed circle with a `+` badge. Optional: the profile is complete
/// without a photo.
class _AvatarPicker extends StatelessWidget {
  const _AvatarPicker({
    required this.avatar,
    required this.initials,
    required this.onTap,
  });

  final ImageProvider? avatar;
  final String initials;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: avatar == null ? 'Add a profile photo' : 'Change profile photo',
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 108,
          height: 108,
          child: Stack(
            children: [
              Container(
                width: 104,
                height: 104,
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.orangeBright,
                ),
                child: CircleAvatar(
                  backgroundColor: const Color(0xFF222222),
                  backgroundImage: avatar,
                  child: avatar == null
                      ? Text(
                          initials,
                          style: const TextStyle(
                            color: AppColors.onMedia,
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                          ),
                        )
                      : null,
                ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.orangeBright,
                    border: Border.all(color: onboardingSurface, width: 3),
                  ),
                  child: const Icon(
                    Icons.add_rounded,
                    color: onboardingCtaInk,
                    size: 22,
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
