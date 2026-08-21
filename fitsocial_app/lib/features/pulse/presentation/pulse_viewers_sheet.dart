import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/avatar.dart';
import '../application/pulse_providers.dart';
import '../domain/pulse_models.dart';
import '../../../shared/widgets/liquid_glass.dart';

/// Who has watched one of your Pulses. Author-only — the security rules make
/// the underlying collection unreadable to anyone else.
class PulseViewersSheet extends ConsumerWidget {
  const PulseViewersSheet({required this.pulseId, super.key});

  final String pulseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final viewers = ref.watch(pulseViewersProvider(pulseId));

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return LiquidGlass(
          // A sheet always has a page behind it, which makes it the one surface
          // in the app guaranteed something worth bending.
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: Column(
            children: [
              const SizedBox(height: AppSpacing.sm),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.stroke,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.all(AppSpacing.md),
                child: Text(
                  'Viewers',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
              Expanded(
                child: viewers.when(
                  data: (list) => list.isEmpty
                      ? const _SheetMessage(
                          label: 'No one has watched this Pulse yet.',
                        )
                      : ListView.builder(
                          controller: scrollController,
                          itemCount: list.length,
                          itemBuilder: (context, index) =>
                              _ViewerRow(viewer: list[index]),
                        ),
                  loading: () => const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.orangeBright,
                    ),
                  ),
                  error: (_, __) => const _SheetMessage(
                    label: "Couldn't load viewers.",
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ViewerRow extends StatelessWidget {
  const _ViewerRow({required this.viewer});

  final PulseViewerRecord viewer;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return ListTile(
      leading: Avatar(
        initials: pulseInitials(viewer.name),
        imageUrl: viewer.avatarUrl,
        size: 40,
      ),
      title: Text(
        viewer.name,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      trailing: Text(
        pulseAgeLabel(viewer.viewedAt, DateTime.now()),
        style: TextStyle(color: palette.muted, fontSize: 12),
      ),
    );
  }
}

class _SheetMessage extends StatelessWidget {
  const _SheetMessage({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(color: palette.muted),
        ),
      ),
    );
  }
}
