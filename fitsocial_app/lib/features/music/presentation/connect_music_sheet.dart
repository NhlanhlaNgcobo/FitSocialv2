import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../main/domain/app_models.dart';
import '../application/music_providers.dart';
import '../domain/music_brand.dart';
import '../domain/music_feature_flags.dart';
import 'widgets/music_brand_logos.dart';
import '../../../shared/widgets/liquid_glass.dart';

/// How the app gets at your music.
///
/// One route while [kMusicAccountsEnabled] is false: notification access, which
/// lets FitSocial read and drive whatever this phone is already playing, in any
/// app, for any account. That is the whole sheet.
///
/// The account half — Spotify, Apple Music, YouTube Music — is written and
/// tested and folds back in behind that flag. It buys exactly one thing the
/// media session cannot do, starting a chosen track, and costs a developer
/// allowlist to have. When it is on, sign-in happens on the service's own page
/// in a browser tab, so credentials are never typed into FitSocial.
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

  // No lifecycle observer here any more. Notification access is granted on a
  // system screen that returns nothing and fires no callback, so the answer
  // has to be re-read on resume — but the permission controller now does that
  // for the whole app. Watching it from here was why granting access lit up
  // this tile and nothing else.

  Future<void> _grantDeviceAccess() async {
    final opened =
        await ref.read(mediaSessionServiceProvider).openPermissionSettings();
    if (!mounted || opened) return;
    // A few OEM builds hide the screen entirely. Saying where to go by hand
    // beats a button that visibly does nothing.
    setState(() => _noticeFor = MusicProviderService.device);
  }

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
    final accountsEnabled = ref.watch(musicAccountsEnabledProvider);
    final mediaSessionGranted = ref.watch(mediaSessionPermissionProvider);

    return SafeArea(
      top: false,
      child: LiquidGlass(
        // A sheet always has a page behind it, which makes it the
        // one surface guaranteed something worth bending.
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Container(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            12,
            AppSpacing.md,
            AppSpacing.md,
          ),
          // Scrollable because the sheet now carries two sections rather than
          // one, and on a short screen that is taller than the space a bottom
          // sheet is given. Without this the overflow eats the last button
          // instead of letting the user reach it.
          child: SingleChildScrollView(
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
                  accountsEnabled
                      ? 'How should we find your music?'
                      : 'Turn on music',
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'FitSocial reads what your phone is already playing, in any '
                  'music app, on any plan. One switch, no account, no password.',
                  style: TextStyle(color: palette.muted, height: 1.45),
                ),
                const SizedBox(height: AppSpacing.lg),
                _DeviceMusicTile(
                  granted: mediaSessionGranted,
                  onTap: _grantDeviceAccess,
                ),
                // Said before they see the system screen, not after. Android
                // files this under notification access, so the switch is
                // wrapped in a warning about reading every notification on the
                // phone — which is a fair description of the permission and a
                // wrong one of what we do with it. Someone who reads that cold,
                // with no idea why a fitness app wants it, closes the screen.
                if (!mediaSessionGranted) const _PrivacyNote(),
                if (_noticeFor == MusicProviderService.device)
                  const _Notice(
                    message:
                        'This phone has no notification-access screen to open. '
                        'Look for Notification access, or Special app access, in '
                        'the system Settings app.',
                  ),
                if (accountsEnabled) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Or connect an account',
                    style: TextStyle(
                      color: palette.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'You sign in on their page, not ours. FitSocial never sees '
                    'your password.',
                    style: TextStyle(
                        color: palette.muted, height: 1.45, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
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
                            ? (connections[brand.service].unavailableReason ??
                                '')
                            : connections[brand.service].errorMessage!,
                      ),
                    const SizedBox(height: 12),
                  ],
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
        ),
      ),
    );
  }
}

/// The phone's own music, and the one toggle that unlocks it.
///
/// Deliberately not a [_BrandConnectButton]: nothing here is being connected,
/// there is no account, and dressing it as one more service to sign in to
/// would misdescribe what the user is agreeing to.
///
/// [granted] reads false while the answer is still being fetched, and draws
/// exactly as "not yet granted": the tile is tappable either way, and the read
/// is one boolean off a platform channel. A spinner would animate longer than
/// the thing it waits for, and would leave any widget test that pumps to settle
/// waiting on it forever.
class _DeviceMusicTile extends StatelessWidget {
  const _DeviceMusicTile({required this.granted, required this.onTap});

  final bool granted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    const brand = MusicBrand.device;
    final isOn = granted;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        // Already on: there is nothing left to ask for, and sending the user
        // back to a settings screen to look at a switch they have already
        // flipped is not an action.
        onTap: isOn ? null : onTap,
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
            border: Border.all(color: palette.stroke),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                MusicServiceLogo(service: brand.service, size: 34),
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
                        isOn
                            ? 'On · controlling whatever this phone plays'
                            : 'Show and control what is playing, in any app',
                        maxLines: 2,
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
                Icon(
                  isOn ? Icons.check_circle : Icons.chevron_right,
                  color: brand.foreground.withValues(alpha: isOn ? 1 : 0.7),
                  size: isOn ? 22 : 24,
                ),
              ],
            ),
          ),
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
                                  color:
                                      brand.foreground.withValues(alpha: 0.78),
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

/// What the system screen is about to ask for, in our words, before it asks.
///
/// [MediaSessionListener] implements neither `onNotificationPosted` nor
/// `onNotificationRemoved`, so this app is never handed the contents of a
/// notification — the service exists purely because Android grants
/// media-session access to a notification-listener *component* and there is no
/// other kind of component to point at. That is a real distinction and an
/// invisible one: the grant screen cannot know we left those methods empty, so
/// it warns about the whole permission.
///
/// Kept concrete rather than reassuring. "We respect your privacy" is what
/// every app says at this moment; naming the two callbacks we did not write is
/// something only an app telling the truth can say.
class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline_rounded, size: 16, color: palette.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Android files this under notification access, so the next '
              'screen will ask you to let FitSocial read your notifications. '
              'It never reads one. That access is used for a single thing: '
              'asking the system what is playing, and pressing play, pause '
              'and skip on it.',
              style: TextStyle(
                color: palette.muted,
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
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
