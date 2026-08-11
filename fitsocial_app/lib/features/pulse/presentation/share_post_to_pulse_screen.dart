import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/shared_post_card.dart';
import '../../main/domain/shared_post.dart';
import '../application/pulse_providers.dart';
import '../domain/pulse_models.dart';
import 'pulse_text.dart';

/// "Add this post to your Pulse" — Instagram's share-to-story, in FitSocial's
/// terms.
///
/// The same canvas the Pulse composer uses, with one thing already on it: the
/// post, as a card mounted on a gradient you pick. There is no camera and no
/// gallery here, because there is nothing to capture — the picture has already
/// been taken by somebody else, and this screen is about how you frame it.
///
/// Nothing is uploaded. The card is drawn from a snapshot written onto the
/// Pulse document, so publishing is a single write and the result opens the
/// original post when tapped.
class SharePostToPulseScreen extends ConsumerStatefulWidget {
  const SharePostToPulseScreen({required this.post, super.key});

  final SharedPostRef post;

  @override
  ConsumerState<SharePostToPulseScreen> createState() =>
      _SharePostToPulseScreenState();
}

class _SharePostToPulseScreenState
    extends ConsumerState<SharePostToPulseScreen> {
  final TextEditingController _captionController = TextEditingController();
  final FocusNode _captionFocus = FocusNode();

  String _gradientKey = PulseGradient.ember.key;
  bool _busy = false;

  @override
  void dispose() {
    _captionController.dispose();
    _captionFocus.dispose();
    super.dispose();
  }

  PulseGradient get _gradient => PulseGradient.fromKey(_gradientKey);

  Future<void> _share() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);

    final draft = PulseDraft(
      type: PulseMediaType.post,
      text: _captionController.text,
      gradientKey: _gradientKey,
      sharedPost: widget.post,
    );

    try {
      await ref.read(pulseActionsProvider).publish(draft);
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Pulse is live for 24 hours.')),
      );
      context.pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final isTyping = keyboardInset > 0;

    return Scaffold(
      backgroundColor: AppColors.mediaBackdrop,
      // Same rule as the Pulse composer: the keyboard overlays the canvas
      // rather than resizing it, and the controls are lifted by hand below.
      resizeToAvoidBottomInset: false,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildCanvas(keyboardInset),
          SafeArea(
            bottom: false,
            child: Align(
              alignment: Alignment.topCenter,
              child: _buildTopBar(isTyping),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: keyboardInset,
            child: SafeArea(
              top: false,
              bottom: !isTyping,
              child: _buildControls(isTyping),
            ),
          ),
          if (_busy)
            const ColoredBox(
              color: Color(0xAA050505),
              child: Center(
                child: CircularProgressIndicator(
                  color: AppColors.orangeBright,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCanvas(double keyboardInset) {
    return DecoratedBox(
      decoration: BoxDecoration(gradient: _gradient.linear),
      child: SafeArea(
        child: Padding(
          // Clears the top bar and the control stack, so the card centres in
          // the space that is actually free rather than under the chrome. The
          // bottom inset shrinks with the keyboard, which is what keeps the
          // card on screen while a caption is being typed.
          padding: EdgeInsets.only(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            top: 64,
            bottom: keyboardInset > 0 ? 96 : 210,
          ),
          child: Center(
            child: SingleChildScrollView(
              child: SharedPostCard(post: widget.post),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(bool isTyping) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Row(
        children: [
          IconButton(
            onPressed: () => context.pop(),
            icon: const Icon(Icons.close_rounded),
            color: AppColors.onMedia,
            tooltip: 'Close',
          ),
          const Spacer(),
          if (isTyping)
            TextButton(
              onPressed: () => FocusScope.of(context).unfocus(),
              style: TextButton.styleFrom(foregroundColor: AppColors.onMedia),
              child: const Text(
                'Done',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildControls(bool isTyping) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _CaptionField(
            controller: _captionController,
            focusNode: _captionFocus,
          ),
          // While the keyboard is up the palette and the button step out of
          // the way, the same as in the Pulse composer.
          if (!isTyping) ...[
            const SizedBox(height: AppSpacing.md),
            _GradientPicker(
              selectedKey: _gradientKey,
              onSelected: (key) => setState(() => _gradientKey = key),
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _busy ? null : _share,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.orangeBright,
                  disabledBackgroundColor: const Color(0x66111111),
                  foregroundColor: AppColors.onMedia,
                  disabledForegroundColor: AppColors.onMediaMuted,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: const Icon(Icons.bolt_rounded),
                label: const Text(
                  'Share to Pulse',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Somewhere to say why you are sharing it. Optional — the post is the point.
class _CaptionField extends StatelessWidget {
  const _CaptionField({required this.controller, required this.focusNode});

  final TextEditingController controller;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: const Color(0x99000000),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.text_fields_rounded,
              color: Color(0xCCFFFFFF), size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              maxLength: 140,
              textCapitalization: TextCapitalization.sentences,
              cursorColor: AppColors.onMedia,
              style: const TextStyle(
                color: AppColors.onMedia,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              decoration: barePulseInput(
                hintText: 'Say something about this',
                hintStyle: const TextStyle(
                  color: Color(0x8AFFFFFF),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The mount the card sits on. Same swatches as a text Pulse — there is one
/// Pulse palette, not one per composer.
class _GradientPicker extends StatelessWidget {
  const _GradientPicker({required this.selectedKey, required this.onSelected});

  final String selectedKey;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: PulseGradient.all.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, index) {
          final gradient = PulseGradient.all[index];
          final selected = gradient.key == selectedKey;
          return GestureDetector(
            onTap: () => onSelected(gradient.key),
            child: Container(
              width: 36,
              height: 36,
              margin: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: gradient.linear,
                border: Border.all(
                  color: selected ? AppColors.onMedia : const Color(0x66FFFFFF),
                  width: selected ? 3 : 1,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
