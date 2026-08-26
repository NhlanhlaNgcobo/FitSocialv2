import 'package:flutter/material.dart';

import '../../app/theme/app_palette.dart';

/// Icon chip, label, and an optional word on the right — the line that opens
/// each block of a logging form.
///
/// One widget because the two logging screens had grown two different answers.
/// Log Workout pinned a brand chip to the leading edge and centred the label
/// over the field below, which left the icon stranded at the far side of the
/// screen from the words it belongs to. Log Run put a small muted icon next to
/// its label and no chip at all. Side by side they read as two apps.
///
/// This is the first design with the second's grouping: the chip keeps its
/// colour, the label sits beside it where it can be read as one thing, and the
/// hint holds the trailing edge.
class FormSectionHeader extends StatelessWidget {
  const FormSectionHeader({
    required this.icon,
    required this.label,
    this.hint,
    super.key,
  });

  final IconData icon;
  final String label;

  /// "Optional", usually. Null leaves the trailing edge empty.
  final String? hint;

  /// The chip is an icon holder rather than a surface, so it keeps its own
  /// small radius instead of taking one off the pane scale — [AppRadius.nested]
  /// on 30 logical pixels would round it into a lozenge.
  static const double _chip = 30;
  static const double _chipRadius = 10;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: _chip,
            height: _chip,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette.brandSoft,
              borderRadius: BorderRadius.circular(_chipRadius),
            ),
            child: Icon(icon, size: 16, color: palette.brand),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: palette.text,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (hint case final hint?)
            Text(
              hint,
              style: TextStyle(color: palette.muted, fontSize: 12),
            ),
        ],
      ),
    );
  }
}
