import 'package:flutter/material.dart';

import '../../../app/theme/app_palette.dart';

/// The speech bubble that sits over an avatar in the tray, as on Instagram.
///
/// Two looks. An answer is a plain bubble. The day's question, which only its
/// owner ever sees, is tinted in the brand colour and led by a "?" — it is
/// asking something of them, and should not pass for an answer at a glance.
class NoteBubble extends StatelessWidget {
  const NoteBubble({
    required this.text,
    this.isQuestion = false,
    this.onTap,
    super.key,
  });

  final String text;
  final bool isQuestion;
  final VoidCallback? onTap;

  /// Wider than the 76 px tile it sits on, so two short lines fit; the tray
  /// leaves the room for the overhang.
  static const double maxWidth = 84;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final fill = isQuestion ? palette.brandSoft : palette.surfaceHigh;
    final edge = isQuestion ? palette.brandSoftStroke : palette.stroke;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            constraints: const BoxConstraints(maxWidth: maxWidth),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: edge),
            ),
            child: Text.rich(
              TextSpan(
                children: [
                  if (isQuestion)
                    TextSpan(
                      text: '? ',
                      style: TextStyle(
                        color: palette.brandText,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  TextSpan(text: text),
                ],
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.text,
                fontSize: 10.5,
                height: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // The tail: one small dot under the bubble, pointing at the face.
          Padding(
            // Off-centre, the way a speech bubble's tail is.
            padding: const EdgeInsets.only(top: 2, right: 18),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: fill,
                shape: BoxShape.circle,
                border: Border.all(color: edge),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
