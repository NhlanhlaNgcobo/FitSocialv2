import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/identity/profile_identity.dart';
import '../../../shared/services/profile_photo_picker.dart';
import '../../../shared/widgets/avatar.dart' show avatarDiscGradient;
import '../../../shared/widgets/fit_social_logo.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/staggered_fade_in.dart';
import '../application/app_session.dart';
import '../application/username_availability_checker.dart';
import '../data/user_profile_repository.dart';
import '../data/username_repository.dart';
import '../domain/body_metrics.dart';
import '../domain/username.dart';
import 'body_metrics_fields.dart';
import 'username_availability_hint.dart';
import '../../../shared/widgets/liquid_glass.dart';

/// The first screen with the user's own name on it, so it is built as a
/// preview of the profile rather than as a form: the photo, name and handle
/// they type assemble a profile header live, above the fields that feed it.
class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen>
    with SingleTickerProviderStateMixin {
  static const int _sectionCount = 5;

  /// Height and weight as they currently stand in the body section. Saved
  /// separately from the profile — these go to the owner-only part of the
  /// account, not the public profile document.
  BodyMetrics _body = const BodyMetrics();
  static const int _bioLimit = 160;

  /// The pieces the progress meter counts. Only the first three are required
  /// to save — the last two are what turn a filled form into a profile worth
  /// following, which is the whole reason they are counted at all.
  static const int _profileParts = 5;

  final _formKey = GlobalKey<FormState>();
  late final AnimationController _entranceController;
  late final TextEditingController _displayNameController;
  late final TextEditingController _handleController;
  late final TextEditingController _bioController;
  late final TextEditingController _locationController;
  String? _imagePath;

  /// Stops the handle from being rewritten from the display name once the user
  /// has made it their own. Suggesting is helpful; overwriting is not.
  bool _handleEdited = false;

  /// Tells the user their handle is taken while they are still typing it,
  /// rather than after they have filled in the rest of the form and pressed
  /// the button.
  late final UsernameAvailabilityChecker _availability;

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
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
    _displayNameController = TextEditingController();
    _handleController = TextEditingController();
    _bioController = TextEditingController();
    _locationController = TextEditingController();
    _availability = UsernameAvailabilityChecker(
      ref.read(usernameRepositoryProvider),
    )..addListener(_onFieldChanged);

    // The header preview and the progress meter both read straight off the
    // controllers, so every keystroke has to rebuild the screen.
    for (final controller in [
      _displayNameController,
      _handleController,
      _bioController,
      _locationController,
    ]) {
      controller.addListener(_onFieldChanged);
    }
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _displayNameController.dispose();
    _handleController.dispose();
    _bioController.dispose();
    _locationController.dispose();
    _availability
      ..removeListener(_onFieldChanged)
      ..dispose();
    super.dispose();
  }

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  /// Mirrors the display name into the handle until the user edits it. Typing
  /// "Bear Mdlalose" offers "bearmdlalose" rather than leaving a second name
  /// to invent.
  void _onDisplayNameChanged(String value) {
    if (_handleEdited) return;
    final suggestion = _suggestHandle(value);
    if (suggestion == _handleController.text) return;
    _handleController.value = TextEditingValue(
      text: suggestion,
      selection: TextSelection.collapsed(offset: suggestion.length),
    );
    // A suggested handle is as likely to be taken as a typed one, and the user
    // never touched the field to trigger a check of their own.
    _availability.check(suggestion);
  }

  static String _suggestHandle(String displayName) {
    final slug =
        displayName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9._]'), '');
    return slug.length > 20 ? slug.substring(0, 20) : slug;
  }

  String get _previewName {
    final name = _displayNameController.text.trim();
    return name.isEmpty ? 'Your name' : name;
  }

  String get _previewHandle {
    final handle = _handleController.text.trim();
    return handle.isEmpty ? 'yourhandle' : handle;
  }

  /// How much of a profile there is so far, out of [_profileParts].
  int get _filledParts {
    var filled = 0;
    if (_imagePath != null) filled++;
    if (_displayNameController.text.trim().length >= 2) filled++;
    if (_handleController.text.trim().length >= 3) filled++;
    if (_bioController.text.trim().isNotEmpty) filled++;
    if (_locationController.text.trim().isNotEmpty) filled++;
    return filled;
  }

  Future<void> _pickPhoto() async {
    final path = await ProfilePhotoPicker.pick(context: context);
    if (path != null && mounted) {
      setState(() => _imagePath = path);
    }
  }

  String? _validateDisplayName(String? value) {
    final name = value?.trim() ?? '';
    if (name.isEmpty) return 'Add a name people will recognise.';
    if (name.length < 2) return 'Use at least 2 characters.';
    return null;
  }

  String? _validateHandle(String? value) {
    final formatError = validateUsernameFormat(value);
    if (formatError != null) return formatError;

    // A name someone else holds is not a format problem, so the shape rules
    // above pass it. Failing validation here is what stops the form
    // submitting on a handle the live check has already refused.
    final availability = _availability.result;
    if (availability != null && !availability.canUse) {
      return availability.message;
    }
    return null;
  }

  Future<void> _submit(AppSession session) async {
    if (session.isLoading) return;
    FocusScope.of(context).unfocus();
    // Caught here rather than by the session, so the message lands on the
    // field that is wrong instead of in a banner above the button.
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // Someone who types a handle and presses the button straight away is
    // still inside the debounce. Finishing that lookup rather than dropping
    // the press is the difference between a button that waits and a button
    // that appears broken.
    if (_availability.isChecking) {
      await _availability.settle();
      if (!mounted) return;
      // Re-run now that there is a verdict — this is what catches a handle
      // whose owner was only discovered after the press.
      if (!(_formKey.currentState?.validate() ?? false)) return;
    }

    // Body metrics go first, and only when there is something to write. They
    // live outside the profile document, so this is a separate write either
    // way — and doing it before the profile keeps it from racing the
    // navigation that follows a successful completion.
    if (!_body.isEmpty) {
      try {
        await ref.read(userProfileRepositoryProvider).saveBodyMetrics(_body);
      } catch (error) {
        // Height and weight are optional here. Losing them must not cost the
        // user their account setup — they can enter them again from the
        // profile, and the alternative is being stuck on this screen.
        debugPrint('Profile setup: body metrics not saved: $error');
      }
      if (!mounted) return;
    }

    // Routing happens off the session's auth stage, which only advances on
    // success — a failure leaves the user here with the error shown above.
    session.completeProfile(
      displayName: _displayNameController.text,
      handle: _handleController.text,
      bio: _bioController.text,
      location: _locationController.text,
      avatarLocalPath: _imagePath,
    );
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final palette = context.palette;
    final shouldSignOut = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => LiquidGlass(
        // A dialog interrupts a page, so there is always something
        // behind it -- which makes it glass like everything else.
        borderRadius: BorderRadius.circular(22),
        child: AlertDialog(
          title: const Text(
            'Sign out?',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19),
          ),
          content: Text(
            "Your account stays put — you'll just need to log in again to "
            'finish setting up your profile.',
            style: TextStyle(color: palette.muted, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              style: TextButton.styleFrom(foregroundColor: palette.muted),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: TextButton.styleFrom(foregroundColor: palette.danger),
              child: const Text(
                'Sign out',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );

    if (shouldSignOut != true || !mounted) return;
    // The router redirects to /welcome off the session stage, so there is no
    // manual navigation to do here.
    await ref.read(appSessionProvider).signOut();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final session = ref.watch(appSessionProvider);
    var sectionIndex = 0;

    return Scaffold(
      // The header photo runs under the status bar; nothing above it needs a
      // bar of its own, so the sign-out action sits on the photo instead.
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
                _SetupHeader(
                  avatar: _pickedAvatar,
                  initials: avatarInitials(_displayNameController.text),
                  hasPhoto: _imagePath != null,
                  onPickPhoto: _pickPhoto,
                  onSignOut:
                      session.isLoading ? null : () => _confirmSignOut(context),
                ),
                const SizedBox(height: AppSpacing.md),
                _IdentityPreview(
                  name: _previewName,
                  hasName: _displayNameController.text.trim().isNotEmpty,
                  handle: _previewHandle,
                  photoHint: _imagePath != null
                      ? 'Photo ready — it uploads when you save.'
                      : 'Tap the circle to add a profile photo.',
                ),
                const SizedBox(height: AppSpacing.lg),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  child: Form(
                    key: _formKey,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        StaggeredFadeIn(
                          controller: _entranceController,
                          index: sectionIndex++,
                          itemCount: _sectionCount,
                          child: _ProfileProgress(
                            filled: _filledParts,
                            total: _profileParts,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        StaggeredFadeIn(
                          controller: _entranceController,
                          index: sectionIndex++,
                          itemCount: _sectionCount,
                          child: _SectionCard(
                            icon: Icons.badge_outlined,
                            title: 'Who you are',
                            subtitle: 'Shown on every post and comment.',
                            children: [
                              const _FieldLabel(
                                icon: Icons.person_outline_rounded,
                                label: 'Display name',
                                trailing: _RequiredTag(),
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _displayNameController,
                                textInputAction: TextInputAction.next,
                                textCapitalization: TextCapitalization.words,
                                maxLength: 30,
                                validator: _validateDisplayName,
                                onChanged: _onDisplayNameChanged,
                                decoration: _fieldDecoration(
                                  palette,
                                  hint: 'e.g. Bear Mdlalose',
                                ),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              const _FieldLabel(
                                icon: Icons.alternate_email_rounded,
                                label: 'Username',
                                trailing: _RequiredTag(),
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _handleController,
                                textInputAction: TextInputAction.next,
                                autocorrect: false,
                                maxLength: 20,
                                // Lowercased and filtered as it is typed, so
                                // what the user sees is exactly what gets
                                // saved — no silent cleanup on submit.
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'[A-Za-z0-9._]'),
                                  ),
                                  TextInputFormatter.withFunction(
                                    (_, newValue) => newValue.copyWith(
                                      text: newValue.text.toLowerCase(),
                                    ),
                                  ),
                                ],
                                validator: _validateHandle,
                                onChanged: (value) {
                                  _handleEdited = true;
                                  _availability.check(value);
                                },
                                decoration: _fieldDecoration(
                                  palette,
                                  hint: 'yourhandle',
                                  prefix: '@',
                                ),
                              ),
                              UsernameAvailabilityHint(checker: _availability),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        StaggeredFadeIn(
                          controller: _entranceController,
                          index: sectionIndex++,
                          itemCount: _sectionCount,
                          child: _SectionCard(
                            icon: Icons.auto_awesome_outlined,
                            title: 'The extras',
                            subtitle: 'Optional, but they get you followed.',
                            children: [
                              _FieldLabel(
                                icon: Icons.notes_rounded,
                                label: 'Bio',
                                trailing: _CounterTag(
                                  count: _bioController.text.length,
                                  limit: _bioLimit,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _bioController,
                                maxLines: 3,
                                maxLength: _bioLimit,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                decoration: _fieldDecoration(
                                  palette,
                                  hint: 'Marathon in training. 5am club.',
                                ),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              const _FieldLabel(
                                icon: Icons.place_outlined,
                                label: 'Location',
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _locationController,
                                textInputAction: TextInputAction.done,
                                textCapitalization: TextCapitalization.words,
                                maxLength: 40,
                                onFieldSubmitted: (_) => _submit(session),
                                decoration: _fieldDecoration(
                                  palette,
                                  hint: 'Durban, South Africa',
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        StaggeredFadeIn(
                          controller: _entranceController,
                          index: sectionIndex++,
                          itemCount: _sectionCount,
                          child: _SectionCard(
                            icon: Icons.monitor_heart_outlined,
                            title: 'Your body',
                            subtitle: 'Private to you. Powers your BMI.',
                            children: [
                              BodyMetricsFields(
                                initial: _body,
                                // The scale and the healthy-weight line belong
                                // on the calculator. Here it is one more
                                // section in a form, so it gets one line.
                                showReadout: false,
                                onChanged: (metrics) => _body = metrics,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        StaggeredFadeIn(
                          controller: _entranceController,
                          index: sectionIndex++,
                          itemCount: _sectionCount,
                          child: Row(
                            children: [
                              Icon(
                                Icons.lock_outline_rounded,
                                size: 15,
                                color: palette.muted,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Your name, bio and location are public on '
                                  'your profile. Your height and weight are '
                                  'not. You can change any of it any time.',
                                  style: TextStyle(
                                    color: palette.muted,
                                    fontSize: 12.5,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          _SubmitBar(
            errorMessage: session.errorMessage,
            isLoading: session.isLoading,
            onSubmit: () => _submit(session),
          ),
        ],
      ),
    );
  }

  /// Fields sit *inside* cards here, and the theme fills them with the card's
  /// own colour — so they take the raised fill instead and read as wells.
  InputDecoration _fieldDecoration(
    AppPalette palette, {
    required String hint,
    String? prefix,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: palette.muted.withValues(alpha: 0.7)),
      filled: true,
      fillColor: palette.surfaceHigh,
      // Our own counters live in the labels; the built-in one adds a line of
      // grey under every field whether it is near the limit or not.
      counterText: '',
      prefixIcon: prefix == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(left: 18, right: 4),
              child: Text(
                prefix,
                style: TextStyle(
                  color: palette.brandText,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ),
      prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
    );
  }
}

/// The photo header: brand imagery fading into the page, with the avatar
/// straddling the seam the way a finished profile shows it.
class _SetupHeader extends StatelessWidget {
  const _SetupHeader({
    required this.avatar,
    required this.initials,
    required this.hasPhoto,
    required this.onPickPhoto,
    required this.onSignOut,
  });

  final ImageProvider? avatar;
  final String initials;
  final bool hasPhoto;
  final VoidCallback onPickPhoto;
  final VoidCallback? onSignOut;

  /// How far the avatar hangs below the photo.
  static const double _overhang = 62;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final topPadding = MediaQuery.paddingOf(context).top;
    final photoHeight = topPadding + 236;

    return SizedBox(
      height: photoHeight + _overhang,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          SizedBox(
            height: photoHeight,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Brand gradient rather than a photo from the brand sheet.
                // `BrandImageTile` crops one cell out of a 6-up sheet by
                // over-sizing it, which only lands on a single cell while the
                // panel stays near-square — in a full-width header strip it
                // straddles two of them and shows the seam.
                //
                // The plate is fixed dark in both themes, like the rest of the
                // app's immersive chrome, which is what lets the copy on it
                // stay `AppColors.onMedia`.
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF241305), AppColors.mediaBackdrop],
                    ),
                  ),
                ),
                // Two blooms of brand light: one off the top-right corner, and
                // one under the avatar so the ring's own glow lands in warmth
                // rather than on flat black.
                Positioned(
                  top: -90,
                  right: -70,
                  width: 280,
                  height: 280,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          AppColors.orangeBright.withValues(alpha: 0.42),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: -60,
                  height: 190,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        colors: [
                          AppColors.orangeBright.withValues(alpha: 0.34),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                // The plate dissolves into the page rather than ending on a
                // hard edge — the same trick the feed hero uses.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 88,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          palette.background,
                          palette.background.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
                // Anchored top *and* bottom rather than laid out from the top
                // down. The copy is white-on-photo, so it has to stay inside
                // the scrimmed part of the image — one line more than expected
                // and a top-anchored block would slide into the fade, where on
                // the cream theme it turns white-on-white, and into the avatar.
                Positioned(
                  top: topPadding + 6,
                  left: AppSpacing.lg,
                  right: AppSpacing.lg,
                  bottom: _overhang + 34,
                  child: LayoutBuilder(
                    builder: (context, constraints) => FittedBox(
                      fit: BoxFit.scaleDown,
                      child: SizedBox(
                        width: constraints.maxWidth,
                        child: const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Sits on the athlete photo and its dark scrim,
                            // which are the same in both themes — so nothing
                            // here takes the palette.
                            FitSocialLogo(
                              size: 26,
                              animated: false,
                              color: AppColors.onMedia,
                            ),
                            SizedBox(height: 18),
                            Text(
                              'Set up your profile',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: AppColors.onMedia,
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.4,
                              ),
                            ),
                            SizedBox(height: 5),
                            Text(
                              'A face and a name make the feed feel like '
                              'yours from day one.',
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppColors.onMediaMuted,
                                fontSize: 14.5,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: topPadding + 4,
                  right: AppSpacing.sm,
                  child: TextButton(
                    onPressed: onSignOut,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.onMedia,
                      disabledForegroundColor: AppColors.onMediaMuted,
                      backgroundColor: const Color(0x4D050505),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: const StadiumBorder(),
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: const Text('Sign out'),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: photoHeight - _overhang,
            child: _AvatarPicker(
              avatar: avatar,
              initials: initials,
              hasPhoto: hasPhoto,
              onTap: onPickPhoto,
            ),
          ),
        ],
      ),
    );
  }
}

/// The tappable profile photo. Empty, it is a lit ring around a monogram of
/// whatever name has been typed so far — the placeholder fills in as the form
/// does, so the circle never sits there looking broken.
class _AvatarPicker extends StatelessWidget {
  const _AvatarPicker({
    required this.avatar,
    required this.initials,
    required this.hasPhoto,
    required this.onTap,
  });

  final ImageProvider? avatar;
  final String initials;
  final bool hasPhoto;
  final VoidCallback onTap;

  static const double _size = 124;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Semantics(
      button: true,
      label: hasPhoto ? 'Change profile photo' : 'Add a profile photo',
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: _size,
          height: _size,
          child: Stack(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOut,
                width: _size,
                height: _size,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.orangeBright
                          .withValues(alpha: hasPhoto ? 1 : 0.6),
                      AppColors.orange.withValues(alpha: hasPhoto ? 1 : 0.3),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.orangeBright
                          .withValues(alpha: hasPhoto ? 0.34 : 0.16),
                      blurRadius: 26,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                // A ring of page colour between the gradient and the photo, so
                // the brand ring reads as a ring instead of a rim on the image.
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: palette.background,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: avatarDiscGradient(palette),
                      image: avatar == null
                          ? null
                          : DecorationImage(
                              image: avatar!,
                              fit: BoxFit.cover,
                            ),
                    ),
                    alignment: Alignment.center,
                    child: avatar != null ? null : _placeholder(palette),
                  ),
                ),
              ),
              Positioned(
                right: 2,
                bottom: 6,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.orangeBright,
                    border: Border.all(color: palette.background, width: 3),
                  ),
                  child: Icon(
                    hasPhoto ? Icons.edit_rounded : Icons.add_a_photo_rounded,
                    color: AppColors.onBrand,
                    size: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholder(AppPalette palette) {
    final monogram = initials.trim();
    if (monogram.isEmpty) {
      return Icon(
        Icons.person_rounded,
        size: 52,
        color: palette.muted,
      );
    }
    return Text(
      monogram,
      style: TextStyle(
        color: palette.text,
        fontSize: 38,
        fontWeight: FontWeight.w700,
        letterSpacing: 1,
      ),
    );
  }
}

/// Name and handle as they will appear on the profile, updating as they are
/// typed. Placeholder copy is muted so it never reads as a saved value.
class _IdentityPreview extends StatelessWidget {
  const _IdentityPreview({
    required this.name,
    required this.hasName,
    required this.handle,
    required this.photoHint,
  });

  final String name;
  final bool hasName;
  final String handle;
  final String photoHint;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        children: [
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: TextStyle(
              color: hasName ? palette.text : palette.muted,
              fontSize: 21,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '@$handle',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: palette.brandText,
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            photoHint,
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.muted, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

/// How complete the profile is. Counts the optional fields too — the point is
/// to show that a bio and a location are worth adding, which a meter that hits
/// 100% on the two required fields would not do.
class _ProfileProgress extends StatelessWidget {
  const _ProfileProgress({required this.filled, required this.total});

  final int filled;
  final int total;

  String get _label {
    if (filled <= 1) return 'Just getting started';
    if (filled == 2) return 'Off the ground';
    if (filled == 3) return 'Looking good';
    if (filled == total - 1) return 'Almost there';
    return 'Ready to go';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final complete = filled >= total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              complete ? Icons.check_circle_rounded : Icons.trending_up_rounded,
              size: 16,
              color: complete ? palette.success : palette.brandText,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$filled/$total',
              style: TextStyle(
                color: palette.muted,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: filled / total),
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => LinearProgressIndicator(
              value: value,
              minHeight: 6,
              backgroundColor: palette.surfaceHigh,
              valueColor: AlwaysStoppedAnimation(
                complete ? palette.success : AppColors.orangeBright,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A titled group of fields. Splitting the form in two says which half is
/// required without putting the word "required" on every second line.
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return LiquidGlass(
      // Painted by the lens rather than by a fill of its own: a pane
      // over the app backdrop, like every other card.
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: palette.stroke),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(11),
                    color: AppColors.orangeBright.withValues(alpha: 0.14),
                  ),
                  child: Icon(icon, size: 18, color: palette.brandText),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: palette.text,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(color: palette.muted, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.icon, required this.label, this.trailing});

  final IconData icon;
  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      children: [
        Icon(icon, size: 15, color: palette.muted),
        const SizedBox(width: 6),
        // Flexible rather than fixed: the label and its tag share one line, and
        // on a narrow phone the longest of them would otherwise push the tag
        // off the card.
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: palette.text,
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          trailing!,
        ],
      ],
    );
  }
}

class _RequiredTag extends StatelessWidget {
  const _RequiredTag();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Required',
      style: TextStyle(
        color: context.palette.brandText,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.3,
      ),
    );
  }
}

class _CounterTag extends StatelessWidget {
  const _CounterTag({required this.count, required this.limit});

  final int count;
  final int limit;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Text(
      '$count/$limit',
      style: TextStyle(
        color: count >= limit ? palette.brandText : palette.muted,
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

/// The save action, pinned below the scroll so it is reachable without hunting
/// for the bottom of the form, and so a failed save is never scrolled offscreen.
class _SubmitBar extends StatelessWidget {
  const _SubmitBar({
    required this.errorMessage,
    required this.isLoading,
    required this.onSubmit,
  });

  final String? errorMessage;
  final bool isLoading;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return LiquidGlass(
      // Painted by the lens rather than by a fill of its own: a pane
      // over the app backdrop, like every other card.
      borderRadius: BorderRadius.circular(0),
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: palette.stroke)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (errorMessage != null) ...[
                  _SetupErrorBanner(message: errorMessage!),
                  const SizedBox(height: AppSpacing.md),
                ],
                PrimaryButton(
                  label: isLoading ? 'Saving…' : 'Complete Setup',
                  icon: isLoading ? null : Icons.arrow_forward_rounded,
                  onPressed: isLoading ? null : onSubmit,
                ),
              ],
            ),
          ),
        ),
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
    final palette = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.danger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.danger.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, color: palette.danger, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: palette.danger, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
