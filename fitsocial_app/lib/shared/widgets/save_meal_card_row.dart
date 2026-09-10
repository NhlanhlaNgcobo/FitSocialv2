import 'package:flutter/material.dart';

import '../../app/theme/app_spacing.dart';
import '../services/meal_card_exporter.dart';
import '../services/meal_card_saver.dart';
import '../services/run_card_saver.dart' show saveImageToGallery;
import 'quick_toast.dart';
import 'save_run_card_row.dart' show CardActionButton;

/// Takes the meal card off the screen and puts it somewhere the cook keeps
/// things: the camera roll, or whatever the OS share sheet offers.
///
/// The meal-flavoured [SaveRunCardRow]: same two buttons, same behaviour,
/// acting on a [MealCardExport] instead of a [RunCardExport].
class SaveMealCardRow extends StatefulWidget {
  const SaveMealCardRow({required this.card, super.key});

  /// What to draw. Rebuilt by the parent whenever the preview changes, so the
  /// file always matches what is on screen.
  final MealCardExport card;

  @override
  State<SaveMealCardRow> createState() => _SaveMealCardRowState();
}

class _SaveMealCardRowState extends State<SaveMealCardRow> {
  /// Which button is working, or null. Drives both spinners and the disable,
  /// so a double tap cannot start a second capture.
  _CardAction? _busy;

  Future<void> _run(_CardAction action) async {
    if (_busy != null) return;
    setState(() => _busy = action);
    try {
      final bytes = await renderMealCardPng(context, widget.card);
      if (!mounted) return;
      final name = mealCardFileName();
      switch (action) {
        case _CardAction.save:
          await saveImageToGallery(bytes, name: name);
          if (!mounted) return;
          showQuickToast(
            context,
            'Saved to your photos',
            tone: ToastTone.success,
          );
        case _CardAction.share:
          await shareMealCardFile(context, bytes, name: name);
      }
    } catch (error) {
      if (!mounted) return;
      reportMealCardFailure(
        Overlay.maybeOf(context, rootOverlay: true),
        error,
      );
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _busy != null;

    return Row(
      children: [
        Expanded(
          child: CardActionButton(
            icon: Icons.download_rounded,
            label: 'Save to Photos',
            working: _busy == _CardAction.save,
            onTap: busy ? null : () => _run(_CardAction.save),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: CardActionButton(
            icon: Icons.ios_share_rounded,
            label: 'Share',
            working: _busy == _CardAction.share,
            onTap: busy ? null : () => _run(_CardAction.share),
          ),
        ),
      ],
    );
  }
}

enum _CardAction { save, share }
