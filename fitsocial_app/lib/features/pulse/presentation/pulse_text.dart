import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';

/// Input styling with every scrap of Material chrome stripped off.
///
/// The app's global [InputDecorationTheme] fills its fields with a dark
/// surface and outlines them — orange once focused. That is right everywhere
/// else and completely wrong on a Pulse, where the text sits directly on the
/// photo or gradient with nothing around it. Setting `border` alone does not
/// undo it: a theme's `enabledBorder` and `focusedBorder` take precedence over
/// `border`, and `filled` has to be turned off by name. Hence all of it,
/// explicitly.
InputDecoration barePulseInput({String? hintText, TextStyle? hintStyle}) {
  return InputDecoration(
    filled: false,
    isCollapsed: true,
    contentPadding: EdgeInsets.zero,
    counterText: '',
    hintText: hintText,
    hintStyle: hintStyle,
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
    disabledBorder: InputBorder.none,
    errorBorder: InputBorder.none,
    focusedErrorBorder: InputBorder.none,
  );
}

/// Type scale for a written Pulse: big and loud when short, stepping down as
/// the message runs long so it always fits the frame.
double pulseTextSize(String text) {
  final length = text.trim().length;
  if (length > 200) return 20;
  if (length > 120) return 24;
  if (length > 60) return 30;
  if (length > 24) return 36;
  return 44;
}

/// A caption over a photo or clip.
///
/// Shared by the composer and the player so what someone writes is positioned
/// and weighted identically in both — no surprise on publish.
class PulseCaption extends StatelessWidget {
  const PulseCaption({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      // A black plate over the user's photo, in both themes — so what sits on
      // it is fixed too.
      decoration: BoxDecoration(
        color: const Color(0x99000000),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: AppColors.onMedia,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          height: 1.3,
        ),
      ),
    );
  }
}
