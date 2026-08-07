import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/services/profile_photo_picker.dart';
import '../../../shared/widgets/avatar.dart';
import '../application/app_session.dart';
import 'account_switcher_sheet.dart';

/// Host for the user's public profile link. Handles are unique, so the
/// handle is what identifies the page.
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
                        onTap: () => _edit(
                          title: 'Username',
                          initial: profile?.handle ?? '',
                          onSaved: (value) => _save(handle: value),
                        ),
                      ),
                      _LinkRow(
                        url: '$_profileLinkHost/$handle',
                        onCopy: () => _copyLink(handle),
                      ),
                    ],
                  ),
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
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _copyLink(String handle) async {
    await Clipboard.setData(
      ClipboardData(text: 'https://$_profileLinkHost/$handle'),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profile link copied.')),
    );
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
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: palette.surfaceHigh,
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
  });

  final String label;
  final String value;
  final VoidCallback onTap;
  final String placeholder;

  /// Whether a filled value is set in bold. Empty values never are — the
  /// placeholder has to read as absent, not as content.
  final bool bold;

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
              Icons.chevron_right_rounded,
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
  });

  final String title;
  final String initial;
  final int maxLines;
  final TextInputType? keyboardType;

  @override
  State<_FieldEditorSheet> createState() => _FieldEditorSheetState();
}

class _FieldEditorSheetState extends State<_FieldEditorSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
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
      child: Container(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
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
                textInputAction: widget.maxLines > 1
                    ? TextInputAction.newline
                    : TextInputAction.done,
                onSubmitted: widget.maxLines > 1 ? null : (_) => _submit(),
                style: TextStyle(color: palette.text),
              ),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.orangeBright,
                    foregroundColor: AppColors.onBrand,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onPressed: _submit,
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _submit() => Navigator.of(context).pop(_controller.text);
}
