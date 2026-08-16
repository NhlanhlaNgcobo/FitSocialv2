import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../main/domain/app_models.dart';
import '../application/music_providers.dart';
import '../domain/music_brand.dart';
import 'widgets/music_brand_logos.dart';

/// "Which are you connecting to?" — the three services, stacked.
///
/// Tapping one opens that service's own sign-in page in a browser tab
/// (Spotify's and Google's OAuth consent screens, Apple's MusicKit
/// authorisation), so credentials are only ever typed into the service's own
/// page and never into FitSocial.
Future<void> showConnectMusicSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _ConnectMusicSheet(),
  );
}

class _ConnectMusicSheet extends ConsumerStatefulWidget {
  const _ConnectMusicSheet();

  @override
  ConsumerState<_ConnectMusicSheet> createState() => _ConnectMusicSheetState();
}

class _ConnectMusicSheetState extends ConsumerState<_ConnectMusicSheet> {
  /// Set when the user taps a service this build has no credentials for, so
  /// the reason appears under that button instead of in a snackbar the sheet
  /// would cover.
  MusicProviderService? _noticeFor;

  Future<void> _handleTap(MusicProviderService service) async {
    final connections = ref.read(musicConnectionsProvider);
    final connection = connections[service];

    // A shaded "coming soon" button already says everything there is to say,
    // so a tap has nothing to add.
    if (connection.isComingSoon) return;

    if (!connection.isAvailable) {
      setState(() => _noticeFor = service);
      return;
    }

    setState(() => _noticeFor = null);

    if (connection.isConnected) {
      await ref.read(musicConnectionsProvider.notifier).disconnect(service);
      return;
    }

    await ref.read(musicConnectionsProvider.notifier).connect(service);

    // Close on success; on failure stay open so the error is readable right
    // under the button that produced it.
    if (!mounted) return;
    if (ref.read(musicConnectionsProvider).isConnected(service)) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final connections = ref.watch(musicConnectionsProvider);

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          12,
          AppSpacing.md,
          AppSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.stroke,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Which are you connecting to?',
              style: TextStyle(
                color: palette.text,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'You sign in on their page, not ours. FitSocial never sees your '
              'password.',
              style: TextStyle(color: palette.muted, height: 1.45),
            ),
            const SizedBox(height: AppSpacing.lg),
            for (final brand in MusicBrand.all) ...[
              _BrandConnectButton(
                brand: brand,
                connection: connections[brand.service],
                onTap: () => _handleTap(brand.service),
              ),
              if (_noticeFor == brand.service ||
                  connections[brand.service].errorMessage != null)
                _Notice(
                  message: _noticeFor == brand.service
                      ? (connections[brand.service].unavailableReason ?? '')
                      : connections[brand.service].errorMessage!,
                ),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: AppSpacing.xs),
            Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Not now'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One full-width service button: brand colours, the mark oversized as a
/// watermark behind the label, and the mark again at readable size in front.
class _BrandConnectButton extends StatelessWidget {
  const _BrandConnectButton({
    required this.brand,
    required this.connection,
    required this.onTap,
  });

  final MusicBrand brand;
  final MusicServiceConnection connection;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final comingSoon = brand.comingSoon;
    // Unconfigured-but-planned services stay legible; a paused one gets the
    // scrim below instead, which does the dimming on its own.
    final dimmed = !connection.isAvailable && !comingSoon;

    return Opacity(
      opacity: dimmed ? 0.55 : 1,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: (connection.isBusy || comingSoon) ? null : onTap,
          borderRadius: BorderRadius.circular(20),
          child: Ink(
            height: 78,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: brand.buttonColors,
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                children: [
                  // The watermark: the same mark, oversized and faded, running
                  // off the right edge.
                  Positioned(
                    right: -26,
                    top: -18,
                    child: MusicServiceLogo(
                      service: brand.service,
                      size: 124,
                      color: brand.foreground.withValues(alpha: 0.14),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Row(
                      children: [
                        MusicServiceLogo(service: brand.service, size: 40),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                brand.name,
                                style: TextStyle(
                                  color: brand.foreground,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                connection.isConnected
                                    ? 'Connected'
                                        '${connection.accountName == null ? '' : ' · ${connection.accountName}'}'
                                    : brand.tagline,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: brand.foreground.withValues(alpha: 0.78),
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        if (!comingSoon)
                          _TrailingIcon(brand: brand, connection: connection),
                      ],
                    ),
                  ),
                  // The shade. It sits over the whole button — brand and all —
                  // so the service still reads as itself while clearly being
                  // switched off rather than broken.
                  if (comingSoon)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: ColoredBox(
                          color: palette.background.withValues(alpha: 0.62),
                          child: const Align(
                            alignment: Alignment.centerRight,
                            child: Padding(
                              padding: EdgeInsets.only(right: 18),
                              child: _ComingSoonPill(),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ComingSoonPill extends StatelessWidget {
  const _ComingSoonPill();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: palette.text.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.text.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.schedule_rounded, size: 14, color: palette.text),
          const SizedBox(width: 6),
          Text(
            'Coming soon',
            style: TextStyle(
              color: palette.text,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrailingIcon extends StatelessWidget {
  const _TrailingIcon({required this.brand, required this.connection});

  final MusicBrand brand;
  final MusicServiceConnection connection;

  @override
  Widget build(BuildContext context) {
    if (connection.isBusy) {
      return SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(
          strokeWidth: 2.4,
          color: brand.foreground,
        ),
      );
    }

    return Icon(
      connection.isConnected
          ? Icons.check_circle_rounded
          : Icons.arrow_forward_rounded,
      color: brand.foreground,
      size: 24,
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 16,
            color: context.palette.brand,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: palette.muted,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
