import 'package:flutter/material.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/dark_card.dart';

/// The safety teal: calm, and apart from the brand orange and the alarm red,
/// so a safety row never reads as one more social one.
const Color safetyTeal = Color(0xFF2E9C94);

/// "20 seconds ago", "4 minutes ago". For how fresh a position is, which a
/// contact has to be able to judge at a glance.
String agoLabel(DateTime? at, DateTime now) {
  if (at == null) return 'a moment ago';
  final s = now.difference(at).inSeconds;
  if (s < 5) return 'just now';
  if (s < 60) return '$s seconds ago';
  final m = s ~/ 60;
  if (m < 60) return '$m minute${m == 1 ? '' : 's'} ago';
  final h = m ~/ 60;
  return '$h hour${h == 1 ? '' : 's'} ago';
}

class SafetySectionLabel extends StatelessWidget {
  const SafetySectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, AppSpacing.sm),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: context.palette.muted,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

/// One tappable row: icon disc, title, subtitle, optional trailing.
class SafetyRow extends StatelessWidget {
  const SafetyRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.accent = safetyTeal,
    this.trailing,
    this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Color accent;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.nested),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: palette.accent(accent).withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: palette.accent(accent), size: 22),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: palette.text,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(color: palette.muted, fontSize: 13),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) trailing!,
            if (trailing == null && onTap != null)
              Icon(Icons.chevron_right_rounded, color: palette.muted),
          ],
        ),
      ),
    );
  }
}

/// A card of rows.
class SafetyCard extends StatelessWidget {
  const SafetyCard({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DarkCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(children: children),
    );
  }
}

/// A short, muted note under a card: what a setting means, or what the app
/// cannot do. The honesty copy the spec requires lives in these.
class SafetyNote extends StatelessWidget {
  const SafetyNote(this.text,
      {this.icon = Icons.info_outline_rounded, super.key});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, AppSpacing.sm, 6, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: palette.muted),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: palette.muted, fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
