import 'package:flutter/material.dart';

class DarkCard extends StatelessWidget {
  const DarkCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.semanticLabel,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// Makes the whole card a target. Null leaves it inert, which is what most
  /// cards want.
  final VoidCallback? onTap;

  /// What tapping this card is for, read out when the visible content is a set
  /// of numbers rather than a sentence.
  final String? semanticLabel;

  /// Matches the radius on the card shape in the theme, so the ripple stops
  /// where the card does.
  static final BorderRadius _radius = BorderRadius.circular(24);

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: padding,
      child: child,
    );

    return Card(
      // Inside the Card rather than around it: the ripple then draws on the
      // card's own surface instead of over its border.
      child: onTap == null
          ? content
          : InkWell(
              onTap: onTap,
              borderRadius: _radius,
              child: Semantics(
                button: true,
                label: semanticLabel,
                child: content,
              ),
            ),
    );
  }
}
