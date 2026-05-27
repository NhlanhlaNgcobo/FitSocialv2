import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../auth/application/app_session.dart';
import '../application/content_providers.dart';
import '../domain/app_models.dart';
import '../../../shared/widgets/avatar.dart';
import '../../../shared/widgets/brand_image_tile.dart';
import '../../../shared/widgets/dark_card.dart';
import '../../../shared/widgets/primary_button.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(appSessionProvider).profile;
    final stats = ref.watch(profileStatsProvider);
    final displayName = profile?.displayName ?? 'FitSocial User';
    final handle = profile?.handle ?? '@fitsocial';
    final initials = _initials(displayName);

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(displayName),
          actions: [
            IconButton(
              onPressed: () => context.push('/achievements'),
              icon: const Icon(Icons.workspace_premium_outlined),
            ),
            IconButton(
              onPressed: () => context.push('/edit-profile'),
              icon: const Icon(Icons.edit_outlined),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.grid_view_rounded)),
              Tab(icon: Icon(Icons.fitness_center_rounded)),
              Tab(icon: Icon(Icons.directions_run_rounded)),
              Tab(icon: Icon(Icons.restaurant_rounded)),
            ],
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: DarkCard(
                child: Column(
                  children: [
                    Row(
                      children: [
                        Avatar(
                          initials: initials,
                          size: 68,
                          visualTile: AppVisualTile.heroPortrait,
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: stats.when(
                              data: _buildStats,
                              loading: () => const [
                                _ProfileStat(label: 'Posts', value: '--'),
                                _ProfileStat(label: 'Followers', value: '--'),
                                _ProfileStat(label: 'Following', value: '--'),
                              ],
                              error: (_, __) => const [
                                _ProfileStat(label: 'Posts', value: '--'),
                                _ProfileStat(label: 'Followers', value: '--'),
                                _ProfileStat(label: 'Following', value: '--'),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '$handle\n${profile?.bio ?? ''}\n${profile?.location ?? ''}',
                        style: const TextStyle(
                            color: AppColors.muted, height: 1.5),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        Expanded(
                          child: PrimaryButton(
                            label: 'Edit Profile',
                            onPressed: () => context.push('/edit-profile'),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        SizedBox(
                          height: 56,
                          width: 56,
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: AppColors.stroke),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            onPressed: () =>
                                ref.read(appSessionProvider).signOut(),
                            child: const Icon(Icons.logout_rounded),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: TabBarView(
                children: List.generate(4, (_) => const _MediaGrid()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildStats(List<ProfileStat> stats) {
    return stats
        .map(
          (stat) => _ProfileStat(
            label: stat.label,
            value: stat.value,
          ),
        )
        .toList();
  }
}

String _initials(String value) {
  final parts = value.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts.first.isEmpty) return 'FS';
  if (parts.length == 1) {
    return parts.first.substring(0, 1).toUpperCase();
  }
  return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
}

class _ProfileStat extends StatelessWidget {
  const _ProfileStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(color: AppColors.muted),
        ),
      ],
    );
  }
}

class _MediaGrid extends StatelessWidget {
  const _MediaGrid();

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.xl,
      ),
      itemCount: 8,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemBuilder: (context, index) {
        final tiles = AppVisualTile.values;
        return BrandImageTile(
          tile: tiles[index % tiles.length],
          borderRadius: BorderRadius.circular(16),
          overlay: const Color(0x16050505),
        );
      },
    );
  }
}
