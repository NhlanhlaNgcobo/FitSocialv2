import 'package:flutter/material.dart';

import '../../app/theme/app_palette.dart';
import '../../app/theme/app_spacing.dart';
import '../services/run_card_exporter.dart';
import '../services/run_card_saver.dart';
import 'liquid_glass.dart';
import 'quick_toast.dart';

/// Takes the run card off the screen and puts it somewhere the runner keeps
/// things: the camera roll, or whatever the OS share sheet offers.
///
/// Three shapes to take it in: the card as posted, a full 1080 × 1920 story,
/// or a transparent sticker to lay over a story of their own.
///
/// Sits under the card it acts on, and acts on exactly what is being previewed
/// — including the photo, if one has been picked. Never navigates and never
/// touches the save the screen around it is there to make: this is a side
/// errand, and a failed one must not cost the run.
class SaveRunCardRow extends StatefulWidget {
  const SaveRunCardRow({required this.card, super.key});

  /// What to draw. Rebuilt by the parent whenever the preview changes, so the
  /// file always matches what is on screen.
  final RunCardExport card;

  @override
  State<SaveRunCardRow> createState() => _SaveRunCardRowState();
}

class _SaveRunCardRowState extends State<SaveRunCardRow> {
  /// Which button is working, or null. Drives both spinners and the disable, so
  /// a double tap cannot start a second capture.
  _CardAction? _busy;

  /// Which shape the next save or share comes out in.
  RunCardFormat _format = RunCardFormat.post;

  Future<void> _run(_CardAction action) async {
    if (_busy != null) return;
    setState(() => _busy = action);
    try {
      final format = _format;
      final bytes =
          await renderRunCardPng(context, widget.card, format: format);
      if (!mounted) return;
      final name = switch (format) {
        RunCardFormat.post => runCardFileName(),
        RunCardFormat.story => '${runCardFileName()}-story',
        RunCardFormat.sticker => '${runCardFileName()}-sticker',
      };
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
          await shareImageFile(context, bytes, name: name);
      }
    } catch (error) {
      if (!mounted) return;
      reportRunCardFailure(Overlay.maybeOf(context, rootOverlay: true), error);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _busy != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _FormatPicker(
          value: _format,
          onChanged: busy ? null : (format) => setState(() => _format = format),
        ),
        const SizedBox(height: AppSpacing.sm),
        _buttons(busy),
      ],
    );
  }

  Widget _buttons(bool busy) {
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

/// Post · Story · Sticker, as one segmented control.
class _FormatPicker extends StatelessWidget {
  const _FormatPicker({required this.value, required this.onChanged});

  final RunCardFormat value;
  final ValueChanged<RunCardFormat>? onChanged;

  static const _options = [
    (format: RunCardFormat.post, label: 'Post', icon: Icons.crop_portrait),
    (format: RunCardFormat.story, label: 'Story', icon: Icons.smartphone),
    (
      format: RunCardFormat.sticker,
      label: 'Sticker',
      icon: Icons.layers_outlined,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.stroke),
      ),
      child: Row(
        children: [
          for (final option in _options)
            Expanded(
              child: Semantics(
                button: true,
                selected: option.format == value,
                child: Material(
                  color: option.format == value
                      ? palette.brandSoft
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(11),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(11),
                    onTap: onChanged == null
                        ? null
                        : () => onChanged!(option.format),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            option.icon,
                            size: 16,
                            color: option.format == value
                                ? palette.brand
                                : palette.muted,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              option.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: option.format == value
                                    ? palette.text
                                    : palette.muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One half of a save/share row: an icon that becomes a spinner while
/// [working], glass-styled to match the photo picker sitting above it. Shared
/// with [SaveMealCardRow] so every "download this card" control looks and
/// behaves like one design rather than two.
class CardActionButton extends StatelessWidget {
  const CardActionButton({
    required this.icon,
    required this.label,
    required this.working,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool working;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return LiquidGlass(
      borderRadius: BorderRadius.circular(14),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Same 18 square either way, so the label does not shift
                // sideways when the spinner takes the icon's place.
                SizedBox.square(
                  dimension: 18,
                  child: working
                      ? CircularProgressIndicator(
                          strokeWidth: 2,
                          color: palette.brand,
                        )
                      : Icon(icon, size: 18, color: palette.brand),
                ),
                const SizedBox(width: AppSpacing.sm),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: onTap == null ? palette.muted : palette.text,
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
