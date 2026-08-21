import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/dark_card.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../main/domain/app_models.dart';
import '../application/music_providers.dart';
import '../domain/music_brand.dart';
import '../domain/music_feature_flags.dart';
import 'connect_music_sheet.dart';
import 'widgets/music_brand_logos.dart';
import '../../../shared/widgets/liquid_glass.dart';

/// The entry point into the music setup flow.
///
/// Before anything is set up this is a single call to action; afterwards it
/// becomes the list of linked accounts, with the same button relabelled so a
/// second service can be added.
///
/// While [kMusicAccountsEnabled] is false there are no accounts to list, so it
/// stays a call to action and asks for the one thing that does work: access to
/// the phone's own media session.
class ConnectMusicAction extends ConsumerWidget {
  const ConnectMusicAction({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final connections = ref.watch(musicConnectionsProvider);
    final connected = connections.connectedServices;
    final accountsEnabled = ref.watch(musicAccountsEnabledProvider);

    return DarkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: palette.brandSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.library_music_rounded,
                  color: palette.brand,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      connected.isNotEmpty
                          ? 'Your music accounts'
                          : (accountsEnabled
                              ? 'Connect your music app'
                              : 'Turn on music'),
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      connected.isNotEmpty
                          ? 'Tap an account to make it the one the player '
                              'controls.'
                          : (accountsEnabled
                              ? 'Link Spotify, Apple Music or YouTube Music to '
                                  'play your workout soundtrack from here.'
                              : 'Play from any music app and control it here — '
                                  'no account, no password, one switch.'),
                      style: TextStyle(
                        color: palette.muted,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (connected.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            for (final service in connected)
              _ConnectedRow(
                service: service,
                connection: connections[service],
                isPrimary: connections.activeConnection?.service == service,
                onSelect: () => ref
                    .read(musicConnectionsProvider.notifier)
                    .setPrimary(service),
                onDisconnect: () => ref
                    .read(musicConnectionsProvider.notifier)
                    .disconnect(service),
              ),
          ],
          const SizedBox(height: AppSpacing.md),
          PrimaryButton(
            label: connected.isNotEmpty
                ? 'Connect another app'
                : (accountsEnabled
                    ? 'Connect your music app'
                    : 'Set up music'),
            icon: accountsEnabled
                ? Icons.add_link_rounded
                : Icons.headphones_rounded,
            onPressed: () => showConnectMusicSheet(context),
          ),
        ],
      ),
    );
  }
}

class _ConnectedRow extends StatelessWidget {
  const _ConnectedRow({
    required this.service,
    required this.connection,
    required this.isPrimary,
    required this.onSelect,
    required this.onDisconnect,
  });

  final MusicProviderService service;
  final MusicServiceConnection connection;
  final bool isPrimary;
  final VoidCallback onSelect;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final brand = MusicBrand.of(service);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onSelect,
          borderRadius: BorderRadius.circular(16),
          child: LiquidGlass(
            // Painted by the lens rather than by a fill of its own: a pane
            // over the app backdrop, like every other card.
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isPrimary ? brand.accent : palette.stroke,
                ),
              ),
              child: Row(
                children: [
                  MusicServiceLogo(service: service, size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          brand.name,
                          style: TextStyle(
                            color: palette.text,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          connection.accountName ?? 'Connected',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isPrimary)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: brand.accent.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Playing here',
                        style: TextStyle(
                          color: brand.accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  IconButton(
                    tooltip: 'Disconnect ${brand.name}',
                    onPressed: connection.isBusy ? null : onDisconnect,
                    icon: const Icon(Icons.link_off_rounded, size: 20),
                    color: palette.muted,
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
