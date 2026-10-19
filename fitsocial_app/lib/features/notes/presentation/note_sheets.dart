import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/identity/profile_identity.dart';
import '../../../shared/widgets/avatar.dart';
import '../../../shared/widgets/comment_well.dart';
import '../../../shared/widgets/keyboard_safe_bottom_bar.dart';
import '../../../shared/widgets/liquid_glass.dart';
import '../../../shared/widgets/quick_toast.dart';
import '../../auth/application/app_session.dart';
import '../../pulse/domain/pulse_models.dart' show pulseAgeLabel;
import '../application/note_providers.dart';
import '../data/firestore_note_repository.dart';
import '../domain/note_models.dart';

/// Opens today's question for the signed-in user: answer it, change the
/// answer, or take it down.
Future<void> showMyNoteSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    // Over the whole app, nav bar included: opened from inside the shell, a
    // sheet would sit under the floating nav and hide its own button.
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _AnswerSheet(),
  );
}

/// Opens someone else's Note: what they were asked, what they said, a heart,
/// and a private reply.
Future<void> showNoteSheet(BuildContext context, FitNote note) {
  return showModalBottomSheet<void>(
    context: context,
    // Over the whole app, nav bar included: opened from inside the shell, a
    // sheet would sit under the floating nav and hide its own button.
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _NoteSheet(note: note),
  );
}

/// The answer box for today's question.
///
/// The question is the user's alone until they answer — this sheet is the only
/// place it is ever shown, and nothing is written anywhere until they press
/// Share. Ignoring it leaves no trace.
class _AnswerSheet extends ConsumerStatefulWidget {
  const _AnswerSheet();

  @override
  ConsumerState<_AnswerSheet> createState() => _AnswerSheetState();
}

class _AnswerSheetState extends ConsumerState<_AnswerSheet> {
  final _controller = TextEditingController();
  final _question = todaysQuestion(DateTime.now());
  bool _busy = false;
  bool _seeded = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _share() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _busy) return;
    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    final overlay = Overlay.of(context, rootOverlay: true);
    try {
      await ref.read(noteActionsProvider).answer(_question, text);
      navigator.pop();
      showQuickToastOn(overlay, 'Your note is up for 24 hours');
    } catch (error) {
      debugPrint('Posting a note failed: $error');
      showQuickToastOn(
        overlay,
        "Couldn't share that note. Try again.",
        icon: Icons.error_outline_rounded,
        tone: ToastTone.danger,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (_busy) return;
    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    final overlay = Overlay.of(context, rootOverlay: true);
    try {
      await ref.read(noteActionsProvider).delete();
      navigator.pop();
      showQuickToastOn(overlay, 'Note deleted');
    } catch (error) {
      debugPrint('Deleting a note failed: $error');
      showQuickToastOn(
        overlay,
        "Couldn't delete that note. Try again.",
        icon: Icons.error_outline_rounded,
        tone: ToastTone.danger,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final myNote = ref.watch(myNoteProvider);
    final answeredToday = myNote != null && myNote.answers(_question.id);

    // An answer already given today is put back in the box to edit, once —
    // after that the box is the user's.
    if (!_seeded && answeredToday) {
      _controller.text = myNote.text;
      _seeded = true;
    }

    return _SheetFrame(
      title: "Today's question",
      bottom: KeyboardSafeBottomBar(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.md,
          ),
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (context, value, _) => SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: value.text.trim().isEmpty || _busy ? null : _share,
                style: FilledButton.styleFrom(
                  backgroundColor: palette.brand,
                  foregroundColor: AppColors.onBrand,
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text(
                  answeredToday ? 'Update note' : 'Share note',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ),
        ),
      ),
      children: [
        Text(
          _question.text,
          style: TextStyle(
            color: palette.text,
            fontSize: 20,
            height: 1.3,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _controller,
          autofocus: !answeredToday,
          maxLines: 2,
          minLines: 1,
          maxLength: NoteTiming.maxLength,
          maxLengthEnforcement: MaxLengthEnforcement.enforced,
          textCapitalization: TextCapitalization.sentences,
          style: TextStyle(color: palette.text, fontSize: 16),
          decoration: InputDecoration(
            hintText: 'Your answer…',
            hintStyle: TextStyle(color: palette.muted),
            filled: true,
            fillColor: palette.surfaceHigh,
            counterStyle: TextStyle(color: palette.muted),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.field),
              borderSide: BorderSide(color: palette.stroke),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.field),
              borderSide: BorderSide(color: palette.stroke),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.field),
              borderSide: BorderSide(color: palette.brand),
            ),
          ),
        ),
        Text(
          'Only you can see this question. Your answer shows over your '
          'picture in your followers\' Pulse tray for 24 hours.',
          style: TextStyle(color: palette.muted, fontSize: 12.5, height: 1.4),
        ),
        if (myNote != null) ...[
          const SizedBox(height: AppSpacing.lg),
          _MyLiveNote(
            note: myNote,
            isToday: answeredToday,
            onDelete: _busy ? null : _delete,
          ),
        ],
      ],
    );
  }
}

/// What the user has up right now, who hearted it, and the way to take it
/// down.
class _MyLiveNote extends ConsumerWidget {
  const _MyLiveNote({
    required this.note,
    required this.isToday,
    required this.onDelete,
  });

  final FitNote note;
  final bool isToday;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final hearts =
        ref.watch(noteHeartsProvider(note.noteId)).valueOrNull ?? const [];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: palette.surfaceHigh,
        borderRadius: BorderRadius.circular(AppRadius.nested),
        border: Border.all(color: palette.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isToday
                ? 'YOUR NOTE · ${pulseAgeLabel(note.createdAt, DateTime.now())}'
                : "YOUR NOTE · YESTERDAY'S QUESTION",
            style: TextStyle(
              color: palette.muted,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
          if (!isToday) ...[
            const SizedBox(height: 4),
            Text(
              note.promptText,
              style: TextStyle(color: palette.muted, fontSize: 12.5),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            note.text,
            style: TextStyle(
              color: palette.text,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Icon(
                Icons.favorite_rounded,
                size: 16,
                color: hearts.isEmpty ? palette.muted : const Color(0xFFE23D5A),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  heartsLabel(hearts),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: palette.muted, fontSize: 13),
                ),
              ),
              TextButton(
                onPressed: onDelete,
                style: TextButton.styleFrom(foregroundColor: palette.danger),
                child: const Text('Delete'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "No likes yet", "Thabo liked this", "Thabo, Lerato and 3 others liked this".
String heartsLabel(List<NoteHeart> hearts) {
  if (hearts.isEmpty) return 'No likes yet';
  String first(NoteHeart heart) => heart.userName.trim().split(' ').first;
  if (hearts.length == 1) return '${first(hearts[0])} liked this';
  if (hearts.length == 2) {
    return '${first(hearts[0])} and ${first(hearts[1])} liked this';
  }
  final others = hearts.length - 2;
  return '${first(hearts[0])}, ${first(hearts[1])} and $others '
      '${others == 1 ? 'other' : 'others'} liked this';
}

/// Someone else's Note.
class _NoteSheet extends ConsumerStatefulWidget {
  const _NoteSheet({required this.note});

  final FitNote note;

  @override
  ConsumerState<_NoteSheet> createState() => _NoteSheetState();
}

class _NoteSheetState extends ConsumerState<_NoteSheet> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _reply() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    if (text.length > FirestoreNoteRepository.maxReplyLength) {
      showQuickToast(
        context,
        'Keep replies under ${FirestoreNoteRepository.maxReplyLength} characters.',
        icon: Icons.error_outline_rounded,
        tone: ToastTone.danger,
      );
      return;
    }
    setState(() => _sending = true);
    final navigator = Navigator.of(context);
    final overlay = Overlay.of(context, rootOverlay: true);
    try {
      await ref.read(noteActionsProvider).reply(widget.note, text);
      navigator.pop();
      showQuickToastOn(overlay, 'Reply sent');
    } catch (error) {
      debugPrint('Replying to a note failed: $error');
      showQuickToastOn(
        overlay,
        "Couldn't send that reply. Try again.",
        icon: Icons.error_outline_rounded,
        tone: ToastTone.danger,
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _toggleHeart(bool hearted) async {
    HapticFeedback.lightImpact();
    try {
      await ref
          .read(noteActionsProvider)
          .setHeart(widget.note, hearted: !hearted);
    } catch (error) {
      debugPrint('Hearting a note failed: $error');
      if (mounted) {
        showQuickToast(
          context,
          "Couldn't like that note. Try again.",
          icon: Icons.error_outline_rounded,
          tone: ToastTone.danger,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final note = widget.note;
    final hearted = ref
            .watch(myNoteHeartProvider(
              (authorId: note.authorId, noteId: note.noteId),
            ))
            .valueOrNull ??
        false;
    final profile = ref.watch(appSessionProvider).profile;
    final firstName = note.authorName.trim().split(' ').first;

    return _SheetFrame(
      bottom: KeyboardSafeBottomBar(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.md,
          ),
          child: CommentWell(
            controller: _controller,
            focusNode: _focusNode,
            onSubmit: _reply,
            isSending: _sending,
            hintText: 'Reply to $firstName…',
            avatarInitials: avatarInitials(profile?.displayName),
            avatarUrl: profile?.avatarUrl,
          ),
        ),
      ),
      children: [
        GestureDetector(
          onTap: () {
            // The router is taken before the pop: the sheet's context is gone
            // after it.
            final router = GoRouter.of(context);
            Navigator.of(context).pop();
            router.push('/user/${note.authorId}');
          },
          behavior: HitTestBehavior.opaque,
          child: Row(
            children: [
              Avatar(
                initials: avatarInitials(note.authorName),
                imageUrl: note.authorAvatarUrl,
                size: 40,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: note.authorName,
                        style: TextStyle(
                          color: palette.text,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      TextSpan(
                        text:
                            '  ${pulseAgeLabel(note.createdAt, DateTime.now())}',
                        style: TextStyle(color: palette.muted),
                      ),
                    ],
                  ),
                  style: const TextStyle(fontSize: 14.5),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (note.promptText.isNotEmpty)
          Text(
            note.promptText,
            style: TextStyle(
              color: palette.muted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                note.text,
                style: TextStyle(
                  color: palette.text,
                  fontSize: 20,
                  height: 1.3,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            IconButton(
              onPressed: () => _toggleHeart(hearted),
              tooltip: hearted ? 'Unlike' : 'Like',
              icon: Icon(
                hearted
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                color: hearted ? const Color(0xFFE23D5A) : palette.muted,
                size: 28,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Only $firstName sees your reply.',
          style: TextStyle(color: palette.muted, fontSize: 12.5),
        ),
      ],
    );
  }
}

/// The chrome both sheets share: glass, a grab handle, an optional title, a
/// scrolling body and a bar pinned to the bottom.
class _SheetFrame extends StatelessWidget {
  const _SheetFrame({
    required this.children,
    required this.bottom,
    this.title,
  });

  final String? title;
  final List<Widget> children;
  final Widget bottom;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return LiquidGlass(
      lens: true,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.stroke,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            if (title case final title?)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.md,
                  0,
                ),
                child: Row(
                  children: [
                    Icon(Icons.forum_rounded, size: 16, color: palette.brand),
                    const SizedBox(width: 6),
                    Text(
                      title.toUpperCase(),
                      style: TextStyle(
                        color: palette.brandText,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.md,
                  AppSpacing.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: children,
                ),
              ),
            ),
            bottom,
          ],
        ),
      ),
    );
  }
}
