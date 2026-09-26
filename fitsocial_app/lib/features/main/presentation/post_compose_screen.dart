import '../../../shared/widgets/quick_toast.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/services/instagram_photo_picker.dart';
import '../../../shared/widgets/avatar.dart';
import '../../../shared/widgets/keyboard_safe_bottom_bar.dart';
import '../../../shared/widgets/mention_suggestions.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../auth/application/app_session.dart';
import '../../auth/presentation/account_switcher_sheet.dart';
import '../application/activity_actions.dart';
import '../application/create_flow_controller.dart';
import '../data/content_repository.dart';
import '../domain/app_models.dart';
import 'tag_people_sheet.dart';
import '../../music/presentation/music_island_action.dart';
import '../../../shared/widgets/liquid_glass.dart';
import '../../../shared/widgets/picture_ratio.dart';

class PostComposeScreen extends ConsumerStatefulWidget {
  const PostComposeScreen({this.prompt, super.key});

  /// The day's question this post answers, when it was opened from the
  /// question card. Null for an ordinary post.
  final PostPrompt? prompt;

  @override
  ConsumerState<PostComposeScreen> createState() => _PostComposeScreenState();
}

class _PostComposeScreenState extends ConsumerState<PostComposeScreen> {
  /// The cap on the activity line: long enough for "5km Morning Run", short
  /// enough that it stays on one line under the author's name in the feed.
  static const int _activityLimit = 40;

  late final TextEditingController _captionController;
  late final TextEditingController _activityController;

  /// The suggestion list has to know when the caption is being typed in, and
  /// only in — an '@' left in the activity line must not open it.
  final _captionFocus = FocusNode();

  /// The cropped photo, held in memory from the moment the cropper returns.
  ///
  /// The upload reads these bytes, never the file: the cropper's output lives
  /// on disk where the OS may clear it while the user is still tagging
  /// people, and a post must not fail because of that.
  Uint8List? _imageBytes;
  double? _imageAspectRatio;

  /// People picked in the tag sheet. Held here rather than in the create-flow
  /// draft because the draft is a resume point for text, and a stale tag list
  /// restored days later would attach people to a different post.
  List<TaggedUser> _taggedUsers = const [];

  bool _isSaving = false;
  String? _errorMessage;

  /// An answer is its own short-lived thing: it neither picks up an unfinished
  /// post draft nor leaves one behind, since resuming it later without the
  /// question would turn it into a post about nothing in particular.
  bool get _isAnswer => widget.prompt != null;

  @override
  void initState() {
    super.initState();
    final draft = _isAnswer
        ? const PostComposerDraftState()
        : ref.read(createFlowControllerProvider).postDraft;
    _captionController = TextEditingController(text: draft.caption);
    _activityController = TextEditingController(text: draft.activity);
  }

  @override
  void dispose() {
    _captionController.dispose();
    _activityController.dispose();
    _captionFocus.dispose();
    super.dispose();
  }

  Future<void> _pickTaggedPeople() async {
    final picked = await showTagPeopleSheet(context, selected: _taggedUsers);
    // Null is a dismissal, which leaves the existing selection alone; an empty
    // list is a deliberate "nobody", which clears it.
    if (picked == null || !mounted) return;
    setState(() => _taggedUsers = picked);
  }

  /// Picks a photo, then hands the user the crop screen so they choose the
  /// framing. The cropper also downscales to 1080px and encodes JPEG at
  /// quality 80, so what comes back is already Instagram-spec.
  Future<void> _pickImage(ImageSource source) async {
    final path = await InstagramPhotoPicker.pickAndCrop(
      context: context,
      source: source,
      // 9:16 first, and the post is shown at whichever shape is picked.
      otherShapes: true,
    );
    // Null means the user backed out of the picker or the cropper — leave any
    // previously chosen photo alone rather than clearing it.
    if (path == null) return;

    // Load the bytes now, while the cropper's file is guaranteed to exist.
    // XFile so this also works on web, where the path is a blob: URL.
    final Uint8List bytes;
    try {
      bytes = await XFile(path).readAsBytes();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = "Couldn't load that photo. Please try again.";
      });
      return;
    }

    // Record the shape the user chose so the feed renders it faithfully
    // instead of forcing every photo into one aspect ratio.
    final ratio = await _readAspectRatio(bytes);
    if (!mounted) return;
    setState(() {
      _imageBytes = bytes;
      _imageAspectRatio = ratio;
      _errorMessage = null;
    });
  }

  /// Decodes just enough of the image to read its dimensions.
  Future<double?> _readAspectRatio(Uint8List bytes) async {
    try {
      final image = await decodeImageFromList(bytes);
      if (image.height == 0) return null;
      return image.width / image.height;
    } catch (_) {
      // A missing ratio only costs us the fallback shape, so never let this
      // failure block the post.
      return null;
    }
  }

  void _syncDraft() {
    if (_isAnswer) return;
    ref.read(createFlowControllerProvider.notifier).updatePost(
          PostComposerDraftState(
            caption: _captionController.text,
            activity: _activityController.text,
          ),
        );
  }

  Future<void> _sharePost() async {
    final caption = _captionController.text.trim();
    if (caption.isEmpty) {
      setState(() {
        _errorMessage = _isAnswer
            ? 'Write your answer before sharing.'
            : 'Write a caption before sharing.';
      });
      return;
    }

    _syncDraft();
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      String? imageUrl;
      final bytes = _imageBytes;
      if (bytes != null) {
        imageUrl = await ref
            .read(contentRepositoryProvider)
            .uploadPostImageBytes(bytes);
      }

      final result = await ref.read(activityActionsProvider).sharePost(
            PostDraft(
              caption: caption,
              activity: _activityController.text.trim(),
              imageUrl: imageUrl,
              imageAspectRatio: _imageAspectRatio,
              taggedUsers: _taggedUsers,
              prompt: widget.prompt,
            ),
          );
      if (!mounted) return;
      if (!_isAnswer) {
        ref.read(createFlowControllerProvider.notifier).completePost(
              result.message,
            );
      }
      showQuickToast(context, result.message, tone: ToastTone.success);
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
    final profile = ref.watch(appSessionProvider).profile;
    final displayName = profile?.displayName ?? 'FitSocial User';

    return Scaffold(
      // Transparent so this page sits on the app's one backdrop, the
      // same ground every other screen looks through.
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(_isAnswer ? 'Your answer' : 'Share Post'),
        actions: const [MusicIslandAction()],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.md,
        ),
        children: [
          if (widget.prompt case final prompt?) ...[
            _PromptBanner(prompt: prompt),
            const SizedBox(height: AppSpacing.md),
          ],
          if (_imageBytes == null)
            _MediaPicker(
              onGallery:
                  _isSaving ? null : () => _pickImage(ImageSource.gallery),
              onCamera: _isSaving ? null : () => _pickImage(ImageSource.camera),
            )
          else
            _SelectedPhoto(
              bytes: _imageBytes!,
              aspectRatio: _imageAspectRatio,
              onChange:
                  _isSaving ? null : () => _pickImage(ImageSource.gallery),
              onRemove:
                  _isSaving ? null : () => setState(() => _imageBytes = null),
            ),
          const SizedBox(height: AppSpacing.md),
          _ComposerCard(
            displayName: displayName,
            handle: formatHandle(profile?.handle),
            avatarUrl: profile?.avatarUrl,
            captionController: _captionController,
            captionFocusNode: _captionFocus,
            activityController: _activityController,
            activityLimit: _activityLimit,
            taggedUsers: _taggedUsers,
            captionHint: _isAnswer ? 'Your answer…' : 'How did the session go?',
            onTagPeople: _isSaving ? null : _pickTaggedPeople,
            onChanged: () {
              // Rebuilds for the activity counter as well as saving the draft.
              setState(_syncDraft);
            },
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: AppSpacing.md),
            _ErrorBanner(message: _errorMessage!),
          ],
        ],
      ),
      // Without this the Share button sits under the keyboard the caption
      // field raises — a Scaffold does not lift its bottom bar for it.
      bottomNavigationBar: KeyboardSafeBottomBar(
        child: _ShareBar(
          isSaving: _isSaving,
          // Only the photo upload takes long enough to be worth narrating.
          showProgress: _isSaving && _imageBytes != null,
          onPressed: _isSaving ? null : _sharePost,
        ),
      ),
    );
  }
}

/// The question being answered, above the composer — so the answer is written
/// looking at what it answers.
class _PromptBanner extends StatelessWidget {
  const _PromptBanner({required this.prompt});

  final PostPrompt prompt;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: palette.brandSoft,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.brandSoftStroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "TODAY'S QUESTION",
            style: TextStyle(
              color: palette.brandText,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            prompt.text,
            style: TextStyle(
              color: palette.text,
              fontSize: 16,
              height: 1.3,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// The empty media slot: one panel that both explains itself and carries the
/// two ways of filling it, rather than a blank box with a stray text button
/// floating underneath it.
class _MediaPicker extends StatelessWidget {
  const _MediaPicker({required this.onGallery, required this.onCamera});

  final VoidCallback? onGallery;
  final VoidCallback? onCamera;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return LiquidGlass(
      // Painted by the lens rather than by a fill of its own: a pane
      // over the app backdrop, like every other card.
      borderRadius: BorderRadius.circular(28),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.lg,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: palette.stroke),
        ),
        child: Column(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: palette.brandSoft,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: palette.brandSoftStroke),
              ),
              child: Icon(
                Icons.add_photo_alternate_rounded,
                color: palette.brand,
                size: 32,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            const Text(
              'Add a photo',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'Optional — a post without one still lands in the feed.',
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: palette.muted, fontSize: 13, height: 1.35),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: _MediaAction(
                    icon: Icons.photo_library_rounded,
                    label: 'Gallery',
                    onTap: onGallery,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _MediaAction(
                    icon: Icons.photo_camera_rounded,
                    label: 'Camera',
                    onTap: onCamera,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MediaAction extends StatelessWidget {
  const _MediaAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return LiquidGlass(
      // Material stays for the ink splash and gives up its colour:
      // an opaque fill in there would sit between the glass and
      // everything it is meant to bend.
      borderRadius: BorderRadius.circular(16),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 13),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: palette.brandText),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
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

/// The chosen photo, shown in the shape the user cropped it to — the same
/// shape the feed will give it.
class _SelectedPhoto extends StatelessWidget {
  const _SelectedPhoto({
    required this.bytes,
    required this.aspectRatio,
    required this.onChange,
    required this.onRemove,
  });

  final Uint8List bytes;
  final double? aspectRatio;
  final VoidCallback? onChange;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Stack(
        children: [
          AspectRatio(
            // 9:16 only stands in when the decode failed; it is the crop
            // screen's default, so the fallback is never a surprise.
            aspectRatio: aspectRatio ?? kPictureAspectRatio,
            child: ColoredBox(
              color: AppColors.mediaBackdrop,
              // Rendered from the same bytes the upload sends, so the
              // preview and the post can never disagree.
              child: Image.memory(bytes, fit: BoxFit.cover),
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: Row(
              // Without this the row fills the stack and drags both controls
              // off the left edge.
              mainAxisSize: MainAxisSize.min,
              children: [
                _GlassButton(
                  icon: Icons.swap_horiz_rounded,
                  label: 'Change',
                  onTap: onChange,
                ),
                const SizedBox(width: 8),
                _GlassIconButton(icon: Icons.close_rounded, onTap: onRemove),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Caption and activity in one card, under the author's own name and photo —
/// so what is being written looks like the post it becomes.
class _ComposerCard extends StatelessWidget {
  const _ComposerCard({
    required this.displayName,
    required this.handle,
    required this.avatarUrl,
    required this.captionController,
    required this.captionFocusNode,
    required this.activityController,
    required this.activityLimit,
    required this.taggedUsers,
    required this.captionHint,
    required this.onTagPeople,
    required this.onChanged,
  });

  final String displayName;
  final String handle;
  final String? avatarUrl;
  final TextEditingController captionController;
  final FocusNode captionFocusNode;
  final TextEditingController activityController;
  final int activityLimit;
  final List<TaggedUser> taggedUsers;
  final String captionHint;
  final VoidCallback? onTagPeople;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final activityLength = activityController.text.characters.length;

    return LiquidGlass(
      // Painted by the lens rather than by a fill of its own: a pane
      // over the app backdrop, like every other card.
      borderRadius: BorderRadius.circular(28),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: palette.stroke),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Avatar(
                  initials: accountInitials(displayName),
                  imageUrl: avatarUrl,
                  size: 40,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        handle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: palette.muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const _AudienceChip(),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: captionController,
              focusNode: captionFocusNode,
              minLines: 4,
              maxLines: 10,
              textCapitalization: TextCapitalization.sentences,
              cursorColor: palette.brand,
              style: TextStyle(
                color: palette.text,
                fontSize: 16,
                height: 1.45,
              ),
              decoration: InputDecoration(
                filled: false,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: captionHint,
                hintStyle: TextStyle(
                  color: palette.muted,
                  fontSize: 16,
                  height: 1.45,
                ),
              ),
              onChanged: (_) => onChanged(),
            ),
            // Below the caption, where there is room to open: unlike the comment
            // bar this field is not sitting on the keyboard.
            MentionSuggestions(
              controller: captionController,
              focusNode: captionFocusNode,
            ),
            const SizedBox(height: AppSpacing.sm),
            Divider(color: palette.stroke, height: 1),
            const SizedBox(height: AppSpacing.sm),
            TagPeopleRow(tagged: taggedUsers, onTap: onTagPeople),
            const SizedBox(height: AppSpacing.sm),
            Divider(color: palette.stroke, height: 1),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Icon(
                  Icons.bolt_rounded,
                  size: 18,
                  color: palette.brandText,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: activityController,
                    textCapitalization: TextCapitalization.sentences,
                    maxLength: activityLimit,
                    cursorColor: palette.brand,
                    style: TextStyle(
                      color: palette.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      filled: false,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      // The built-in counter parks itself below the field and
                      // pulls the whole row out of line; this one sits in it.
                      counterText: '',
                      hintText: 'Add an activity, e.g. 5km Morning Run',
                      hintStyle: TextStyle(color: palette.muted, fontSize: 14),
                    ),
                    onChanged: (_) => onChanged(),
                  ),
                ),
                // Only worth showing once the limit is in sight.
                if (activityLength > activityLimit - 12) ...[
                  const SizedBox(width: 8),
                  Text(
                    '${activityLimit - activityLength}',
                    style: TextStyle(
                      color: activityLength >= activityLimit
                          ? palette.danger
                          : palette.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Says where the post is going. Static for now — there is one audience — but
/// it is the thing that makes the card read as a post rather than a form.
class _AudienceChip extends StatelessWidget {
  const _AudienceChip();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: palette.surfaceHigh,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.stroke),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.public_rounded, size: 13, color: palette.brandText),
          const SizedBox(width: 6),
          Text(
            'Feed',
            style: TextStyle(
              color: palette.muted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// The action bar pinned under the list. Its host lifts it clear of the
/// keyboard and the phone's own navigation — see [KeyboardSafeBottomBar] —
/// so it must not pad for either itself.
class _ShareBar extends StatelessWidget {
  const _ShareBar({
    required this.isSaving,
    required this.showProgress,
    required this.onPressed,
  });

  final bool isSaving;
  final bool showProgress;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return LiquidGlass(
      // Painted by the lens rather than by a fill of its own: a pane
      // over the app backdrop, like every other card.
      borderRadius: BorderRadius.circular(0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: palette.stroke)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showProgress) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: palette.brand,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Uploading your photo...',
                      style: TextStyle(color: palette.muted, fontSize: 13),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              PrimaryButton(
                label: isSaving ? 'Sharing...' : 'Share Post',
                icon: isSaving ? null : Icons.send_rounded,
                onPressed: onPressed,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.danger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.danger.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, size: 18, color: palette.danger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: palette.danger,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Controls that sit on a photo, so their colours are fixed rather than
/// theme-dependent — the backdrop is the user's own image either way.
class _GlassButton extends StatelessWidget {
  const _GlassButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0x66000000),
      shape: const StadiumBorder(
        side: BorderSide(color: Color(0x33FFFFFF)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: AppColors.onMedia),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.onMedia,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0x66000000),
      shape: const CircleBorder(side: BorderSide(color: Color(0x33FFFFFF))),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 32,
          height: 32,
          child: Icon(icon, size: 17, color: AppColors.onMedia),
        ),
      ),
    );
  }
}
