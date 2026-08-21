import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/services/profile_photo_picker.dart';
import '../../../shared/widgets/avatar.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/quick_toast.dart';
import '../application/app_session.dart';
import '../application/body_metrics_providers.dart';
import '../application/username_availability_checker.dart';
import '../data/user_profile_repository.dart';
import '../data/username_repository.dart';
import '../domain/body_metrics.dart';
import '../domain/username.dart';
import 'account_switcher_sheet.dart';
import 'body_metrics_fields.dart';
import 'username_availability_hint.dart';
import '../../../shared/widgets/liquid_glass.dart';

/// Host for the user's public profile link. Usernames are unique — enforced by
/// the `usernames` collection, whose document ids are the names themselves —
/// so the username is what identifies the page.
const _profileLinkHost = 'fitsocial.app';

/// Editing a profile, one field at a time.
///
/// There is no Save button: each row opens its own editor and commits on its
/// own, which is why every save re-sends the whole profile. [AppSession]
/// writes all fields on every call, so a row that isn't being edited still
/// has to hand back its current value or it would be cleared.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  @override
  Widget build(BuildContext context) {
    final session = ref.watch(appSessionProvider);
    final profile = session.profile;
    final displayName = profile?.displayName ?? '';
    final handle = formatHandle(profile?.handle);
    final cooldown = usernameCooldownRemaining(profile?.handleChangedAt);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const _TopBar(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.xl,
                ),
                children: [
                  _PhotoArea(
                    displayName: displayName,
                    avatarUrl: profile?.avatarUrl,
                    isSaving: session.isLoading,
                    onPick: _pickPhoto,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  _Card(
                    children: [
                      _FieldRow(
                        label: 'Name',
                        value: displayName,
                        placeholder: 'Add your name',
                        onTap: () => _edit(
                          title: 'Name',
                          initial: profile?.displayName ?? '',
                          onSaved: (value) => _save(displayName: value),
                        ),
                      ),
                      _FieldRow(
                        label: 'Username',
                        value: handle,
                        bold: false,
                        // Locked rather than hidden while the cooldown runs:
                        // the row still has to show what the username is.
                        trailingIcon: cooldown == null
                            ? Icons.chevron_right_rounded
                            : Icons.lock_clock_rounded,
                        onTap: () => _editUsername(
                          current: profile?.handle ?? '',
                          cooldown: cooldown,
                        ),
                      ),
                      _LinkRow(
                        url: '$_profileLinkHost/$handle',
                        onCopy: () => _copyLink(handle),
                      ),
                    ],
                  ),
                  if (cooldown != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    UsernameCooldownNotice(remaining: cooldown),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  const _CardLabel('Basic info'),
                  _Card(
                    children: [
                      _FieldRow(
                        label: 'Bio',
                        value: profile?.bio ?? '',
                        placeholder: 'Add a bio',
                        onTap: () => _edit(
                          title: 'Bio',
                          initial: profile?.bio ?? '',
                          maxLines: 5,
                          onSaved: (value) => _save(bio: value),
                        ),
                      ),
                      _FieldRow(
                        label: 'Pronoun',
                        value: profile?.pronouns ?? '',
                        placeholder: 'Add pronouns',
                        bold: false,
                        onTap: () => _edit(
                          title: 'Pronouns',
                          initial: profile?.pronouns ?? '',
                          onSaved: (value) => _save(pronouns: value),
                        ),
                      ),
                      _FieldRow(
                        label: 'Links',
                        value: profile?.links ?? '',
                        placeholder: 'Add link',
                        bold: false,
                        onTap: () => _edit(
                          title: 'Link',
                          initial: profile?.links ?? '',
                          keyboardType: TextInputType.url,
                          onSaved: (value) => _save(links: value),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const _CardLabel('Body'),
                  _BodyCard(onEdit: _editBody),
                  const SizedBox(height: AppSpacing.sm),
                  const _PrivateNotice(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickPhoto() async {
    final path = await ProfilePhotoPicker.pick(context: context);
    if (path == null) return;
    await _save(avatarLocalPath: path);
  }

  /// The username row's own editor, because it is the only field with a
  /// gatekeeper in front of it and a live lookup inside it.
  Future<void> _editUsername({
    required String current,
    required Duration? cooldown,
  }) async {
    if (cooldown != null) {
      // The notice under the card already explains the rule; this is for the
      // person who tapped the row anyway.
      showQuickToast(
        context,
        'You can change your username again in '
        '${describeCooldownRemaining(cooldown)}.',
        icon: Icons.schedule_rounded,
      );
      return;
    }

    final checker = UsernameAvailabilityChecker(
      ref.read(usernameRepositoryProvider),
    );

    try {
      final value = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => _FieldEditorSheet(
          title: 'Username',
          initial: normalizeUsername(current),
          maxLines: 1,
          checker: checker,
        ),
      );

      if (value == null) return;
      if (normalizeUsername(value) == normalizeUsername(current)) return;
      await _save(handle: value);
    } finally {
      checker.dispose();
    }
  }

  /// Opens the height and weight editor.
  ///
  /// A sheet of its own rather than the one-value [_FieldEditorSheet] every
  /// other row uses: height and weight are two fields that only mean anything
  /// together, and a unit toggle applies to both. Editing them one at a time
  /// would let a user set a height in cm and a weight in pounds.
  Future<void> _editBody(BodyMetrics current) async {
    final saved = await showModalBottomSheet<BodyMetrics>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _BodyEditorSheet(initial: current),
    );
    if (saved == null || !mounted) return;

    try {
      await ref.read(userProfileRepositoryProvider).saveBodyMetrics(saved);
      if (!mounted) return;
      ref.invalidate(bodyMetricsProvider);
    } catch (_) {
      if (!mounted) return;
      showQuickToast(
        context,
        "Couldn't save your measurements.",
        icon: Icons.error_outline_rounded,
        tone: ToastTone.danger,
      );
    }
  }

  Future<void> _edit({
    required String title,
    required String initial,
    required Future<void> Function(String value) onSaved,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) async {
    final value = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _FieldEditorSheet(
        title: title,
        initial: initial,
        maxLines: maxLines,
        keyboardType: keyboardType,
      ),
    );
    // Null means dismissed; an unchanged value is not worth a write.
    if (value == null || value.trim() == initial.trim()) return;
    await onSaved(value);
  }

  /// Commits one changed field. Everything not named here is carried over
  /// from the session profile, because the write replaces all of them.
  Future<void> _save({
    String? displayName,
    String? handle,
    String? bio,
    String? pronouns,
    String? links,
    String? avatarLocalPath,
  }) async {
    final current = ref.read(appSessionProvider).profile;
    final saved = await ref.read(appSessionProvider).completeProfile(
          displayName: displayName ?? current?.displayName ?? '',
          handle: handle ?? current?.handle ?? '',
          bio: bio ?? current?.bio ?? '',
          // No row edits location, so it is only ever carried forward.
          location: current?.location ?? '',
          pronouns: pronouns ?? current?.pronouns ?? '',
          links: links ?? current?.links ?? '',
          avatarLocalPath: avatarLocalPath,
        );

    if (saved || !mounted) return;
    // The session keeps the reason; surfacing it here is the only place the
    // user finds out a save was rejected.
    final message =
        ref.read(appSessionProvider).errorMessage ?? "Couldn't save that.";
    showQuickToast(
      context,
      message,
      icon: Icons.error_outline_rounded,
      tone: ToastTone.danger,
    );
  }

  Future<void> _copyLink(String handle) async {
    await Clipboard.setData(
      ClipboardData(text: 'https://$_profileLinkHost/$handle'),
    );
    if (!mounted) return;
    showQuickToast(context, 'Profile link copied', icon: Icons.link_rounded);
  }
}

/// Back on the left, title centred on the screen — centred against the screen
/// rather than against the space left over, which is why the title is stacked
/// behind the button instead of sitting in a row with it.
class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SizedBox(
      height: 52,
      child: Stack(
        children: [
          Center(
            child: Text(
              'Edit profile',
              style: TextStyle(
                color: palette.text,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              onPressed: () => context.pop(),
              tooltip: 'Back',
              color: palette.text,
              icon: const Icon(Icons.chevron_left_rounded, size: 30),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoArea extends StatelessWidget {
  const _PhotoArea({
    required this.displayName,
    required this.isSaving,
    required this.onPick,
    this.avatarUrl,
  });

  final String displayName;
  final bool isSaving;
  final VoidCallback onPick;
  final String? avatarUrl;

  static const double _size = 104;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      children: [
        GestureDetector(
          onTap: isSaving ? null : onPick,
          child: SizedBox(
            width: _size,
            height: _size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Avatar(
                  initials: accountInitials(displayName),
                  size: _size,
                  imageUrl: avatarUrl,
                ),
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0x99000000),
                  ),
                  alignment: Alignment.center,
                  child: isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.onMedia,
                          ),
                        )
                      : const Icon(
                          Icons.photo_camera_rounded,
                          color: AppColors.onMedia,
                          size: 22,
                        ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextButton(
          onPressed: isSaving ? null : onPick,
          style: TextButton.styleFrom(
            foregroundColor: palette.muted,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('Change photo'),
        ),
      ],
    );
  }
}

/// Height, weight and the BMI they give, as three read-only rows over one
/// editor.
///
/// Rows rather than live fields because that is this screen's whole idiom —
/// every value here is a row that opens something. The editing happens in
/// [_BodyEditorSheet].
class _BodyCard extends ConsumerWidget {
  const _BodyCard({required this.onEdit});

  final Future<void> Function(BodyMetrics current) onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = ref.watch(bodyMetricsProvider);
    final body = metrics.asData?.value ?? const BodyMetrics();
    final imperial = body.units == MeasurementUnits.imperial;

    String height() {
      final cm = body.heightCm;
      if (cm == null) return '';
      if (!imperial) return '${_trim(cm)} cm';
      final split = cmToFeetAndInches(cm);
      return "${split.feet}' ${split.inches.round()}\"";
    }

    String weight() {
      final kg = body.weightKg;
      if (kg == null) return '';
      return imperial ? '${_trim(kgToPounds(kg))} lb' : '${_trim(kg)} kg';
    }

    return _Card(
      children: [
        _FieldRow(
          label: 'Height',
          value: height(),
          placeholder: 'Add your height',
          onTap: () => onEdit(body),
        ),
        _FieldRow(
          label: 'Weight',
          value: weight(),
          bold: false,
          placeholder: 'Add your weight',
          onTap: () => onEdit(body),
        ),
        _FieldRow(
          label: 'BMI',
          // Worked out from the two rows above rather than stored, so it can
          // never disagree with them.
          value: body.bmi == null
              ? ''
              : '${body.bmiLabel}  ·  ${body.category!.label}',
          bold: false,
          placeholder: 'Needs your height and weight',
          onTap: () => onEdit(body),
        ),
      ],
    );
  }

  /// "70" rather than "70.0", but "70.5" kept.
  static String _trim(double value) {
    final rounded = value.toStringAsFixed(1);
    return rounded.endsWith('.0')
        ? rounded.substring(0, rounded.length - 2)
        : rounded;
  }
}

/// Says the body card is not published, since every other card on this screen
/// is.
class _PrivateNotice extends StatelessWidget {
  const _PrivateNotice();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline_rounded, size: 14, color: palette.muted),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Only you can see your height and weight.',
              style: TextStyle(
                color: palette.muted,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The height and weight editor, returning the new metrics or null if
/// dismissed.
class _BodyEditorSheet extends StatefulWidget {
  const _BodyEditorSheet({required this.initial});

  final BodyMetrics initial;

  @override
  State<_BodyEditorSheet> createState() => _BodyEditorSheetState();
}

class _BodyEditorSheetState extends State<_BodyEditorSheet> {
  late BodyMetrics _draft = widget.initial;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Padding(
      // Lifts the sheet clear of the keyboard, which is up the whole time this
      // is open.
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: LiquidGlass(
        // A sheet always has a page behind it, which makes it the one
        // surface in the app guaranteed something worth bending.
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: palette.stroke),
          ),
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Height & weight',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: palette.text,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  BodyMetricsFields(
                    initial: widget.initial,
                    showReadout: false,
                    onChanged: (metrics) => setState(() => _draft = metrics),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  PrimaryButton(
                    label: 'Save',
                    // Refuses a figure it could not use rather than storing one
                    // that would show no BMI later. An empty form is fine —
                    // that is how a value gets cleared.
                    onPressed: _draft.isEmpty || _draft.issue == null
                        ? () => Navigator.of(context).pop(_draft)
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CardLabel extends StatelessWidget {
  const _CardLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: AppSpacing.sm),
      child: Text(
        label,
        style: TextStyle(color: palette.muted, fontSize: 13),
      ),
    );
  }
}

/// A group of rows on one raised surface, hairline-separated.
class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return LiquidGlass(
      // Painted by the lens now rather than by a fill of its own:
      // a pane over the app backdrop, like every other card.
      borderRadius: BorderRadius.circular(20),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  thickness: 1,
                  color: palette.stroke,
                  indent: AppSpacing.md,
                ),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// Label, current value, chevron. Tapping anywhere on it opens the editor.
class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.label,
    required this.value,
    required this.onTap,
    this.placeholder = '',
    this.bold = true,
    this.trailingIcon = Icons.chevron_right_rounded,
  });

  final String label;
  final String value;
  final VoidCallback onTap;
  final String placeholder;

  /// Whether a filled value is set in bold. Empty values never are — the
  /// placeholder has to read as absent, not as content.
  final bool bold;

  /// The affordance on the right. A chevron for a row that opens; something
  /// else for a row that will not.
  final IconData trailingIcon;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final filled = value.trim().isNotEmpty;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 14,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 86,
              child: Text(
                label,
                style: TextStyle(color: palette.muted, fontSize: 15),
              ),
            ),
            Expanded(
              child: Text(
                filled ? value : placeholder,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: filled ? palette.text : palette.muted,
                  fontSize: 15,
                  fontWeight:
                      filled && bold ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Icon(
              trailingIcon,
              color: palette.muted,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

/// The user's public profile URL. The whole row copies it.
class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.url, required this.onCopy});

  final String url;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkWell(
      onTap: onCopy,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 14,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                url,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: palette.text, fontSize: 15),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Icon(
              Icons.copy_rounded,
              color: palette.muted,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

/// One field, one sheet. Pops the new value, or null when dismissed.
class _FieldEditorSheet extends StatefulWidget {
  const _FieldEditorSheet({
    required this.title,
    required this.initial,
    required this.maxLines,
    this.keyboardType,
    this.checker,
  });

  final String title;
  final String initial;
  final int maxLines;
  final TextInputType? keyboardType;

  /// Present only for the username field, which is the one field whose value
  /// somebody else can already own. Its presence is what turns this sheet into
  /// a username editor: filtered input, a live verdict, and a Save button that
  /// waits for it.
  final UsernameAvailabilityChecker? checker;

  @override
  State<_FieldEditorSheet> createState() => _FieldEditorSheetState();
}

class _FieldEditorSheetState extends State<_FieldEditorSheet> {
  late final TextEditingController _controller;

  bool get _isUsername => widget.checker != null;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
    // Seeds the verdict from the value already in the field, so opening the
    // sheet on your own username says so rather than showing nothing.
    widget.checker?.check(widget.initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      // Lifts the sheet clear of the keyboard it just raised.
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: LiquidGlass(
          // A sheet always has a page behind it, which makes it the one
          // surface in the app guaranteed something worth bending.
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    style: TextStyle(
                      color: palette.text,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: _controller,
                    autofocus: true,
                    maxLines: widget.maxLines,
                    keyboardType: widget.keyboardType,
                    autocorrect: !_isUsername,
                    maxLength: _isUsername ? usernameMaxLength : null,
                    // Lowercased and filtered as it is typed, so what the user
                    // sees is exactly what gets saved — and exactly what becomes
                    // the reservation's document id.
                    inputFormatters: _isUsername
                        ? [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[A-Za-z0-9._]'),
                            ),
                            TextInputFormatter.withFunction(
                              (_, newValue) => newValue.copyWith(
                                text: newValue.text.toLowerCase(),
                              ),
                            ),
                          ]
                        : null,
                    onChanged: widget.checker?.check,
                    textInputAction: widget.maxLines > 1
                        ? TextInputAction.newline
                        : TextInputAction.done,
                    onSubmitted: widget.maxLines > 1 ? null : (_) => _submit(),
                    style: TextStyle(color: palette.text),
                    decoration: _isUsername
                        ? const InputDecoration(
                            prefixText: '@', counterText: '')
                        : null,
                  ),
                  if (widget.checker != null)
                    UsernameAvailabilityHint(checker: widget.checker!),
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: AnimatedBuilder(
                      animation: widget.checker ?? kAlwaysDismissedAnimation,
                      builder: (context, _) {
                        // Disabled while a lookup is outstanding as well as when
                        // it came back negative: neither is a yes, and letting the
                        // save through on a maybe just moves the rejection to a
                        // less helpful place.
                        final blocked =
                            _isUsername && widget.checker!.canUse != true;
                        return FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: palette.brand,
                            foregroundColor: AppColors.onBrand,
                            disabledBackgroundColor: palette.surfaceHigh,
                            disabledForegroundColor: palette.muted,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          onPressed: blocked ? null : _submit,
                          child: const Text('Save'),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          )),
    );
  }

  void _submit() {
    if (_isUsername && widget.checker!.canUse != true) return;
    Navigator.of(context).pop(_controller.text);
  }
}
