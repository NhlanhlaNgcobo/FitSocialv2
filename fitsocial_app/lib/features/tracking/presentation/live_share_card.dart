import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/quick_toast.dart';
import '../../../shared/widgets/share_sheet.dart' show shareOriginOf;
import '../../auth/application/app_session.dart';
import '../../main/domain/activity_kind.dart';
import '../application/live_share_controller.dart';
import 'run_session_widgets.dart';

/// The "Share activity" control on a live GPS screen.
///
/// Three faces, driven by [liveShareControllerProvider]: a button to start
/// sharing, a moment of "Starting…" while the document is created, and — once
/// the share is open — a card that says location is being shared, with the
/// link to hand out again and the way to stop.
///
/// Starting a share opens the OS share sheet straight away with the link in
/// it, because that is the only reason anyone taps this: the runner is about
/// to leave, and the person at home needs the link before they do.
class LiveShareCard extends ConsumerWidget {
  const LiveShareCard({required this.kind, super.key});

  final ActivityKind kind;

  Future<void> _startAndShare(BuildContext context, WidgetRef ref) async {
    final controller = ref.read(liveShareControllerProvider.notifier);
    await controller.start(kind);
    if (!context.mounted) return;
    final session = ref.read(liveShareControllerProvider).session;
    if (session == null) return;
    await _shareLink(context, ref, session.link);
  }

  Future<void> _shareLink(BuildContext context, WidgetRef ref, Uri link) async {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    final name = ref.read(appSessionProvider).profile?.displayName.trim();
    final who = (name == null || name.isEmpty) ? 'Someone' : name;
    final title =
        "$who's ${kind.descriptor.singular.toLowerCase()} — live on FitSocial";
    try {
      await SharePlus.instance.share(
        ShareParams(
          uri: link,
          subject: title,
          title: title,
          sharePositionOrigin: shareOriginOf(context),
        ),
      );
    } catch (_) {
      // No share sheet on this device. The clipboard keeps the link in the
      // runner's hands, which is what the tap was for.
      await Clipboard.setData(ClipboardData(text: link.toString()));
      if (overlay == null) return;
      showQuickToastOn(overlay, 'Link copied instead', icon: Icons.link_rounded);
    }
  }

  Future<void> _copyLink(BuildContext context, Uri link) async {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    await Clipboard.setData(ClipboardData(text: link.toString()));
    if (overlay == null) return;
    showQuickToastOn(overlay, 'Link copied', icon: Icons.link_rounded);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(liveShareControllerProvider);
    final session = state.session;
    final palette = context.palette;

    if (session == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ShareButton(
            label: state.isStarting ? 'Starting…' : 'Share activity',
            onPressed: state.isStarting ? null : () => _startAndShare(context, ref),
          ),
          if (state.errorMessage != null) ...[
            const SizedBox(height: AppSpacing.sm),
            RunBanner(
              icon: Icons.error_outline_rounded,
              message: state.errorMessage!,
              tone: RunBannerTone.danger,
            ),
          ],
        ],
      );
    }

    final color = palette.brandText;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.share_location_rounded, size: 18, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Sharing your live location',
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const RunStatusPill(label: 'LIVE', accent: true),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 28),
            child: Text(
              'Anyone with the link can follow this '
              '${kind.descriptor.singular.toLowerCase()} until you finish.',
              style: TextStyle(
                color: palette.muted,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              _CardAction(
                icon: Icons.ios_share_rounded,
                label: 'Send link',
                color: color,
                onPressed: () => unawaited(_shareLink(context, ref, session.link)),
              ),
              const SizedBox(width: AppSpacing.sm),
              _CardAction(
                icon: Icons.link_rounded,
                label: 'Copy',
                color: color,
                onPressed: () => unawaited(_copyLink(context, session.link)),
              ),
              const Spacer(),
              _CardAction(
                icon: Icons.location_off_rounded,
                label: 'Stop',
                color: palette.danger,
                onPressed: () => unawaited(
                  ref.read(liveShareControllerProvider.notifier).stop(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Full-width, the quiet counterpart to the lit Finish bar above it: this is
/// an option, not the next step.
class _ShareButton extends StatelessWidget {
  const _ShareButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return SizedBox(
      height: 52,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.text,
          backgroundColor: palette.surfaceHigh,
          side: BorderSide(color: palette.stroke),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        icon: const Icon(Icons.share_location_rounded, size: 20),
        label: Text(label),
      ),
    );
  }
}

class _CardAction extends StatelessWidget {
  const _CardAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        minimumSize: const Size(0, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: color.withValues(alpha: 0.14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      icon: Icon(icon, size: 16),
      label: Text(
        label,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
    );
  }
}
