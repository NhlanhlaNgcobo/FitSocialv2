import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/theme_mode_controller.dart';
import '../../../shared/widgets/avatar.dart';
import '../../auth/application/app_session.dart';
import '../../auth/presentation/account_switcher_sheet.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final profile = ref.watch(appSessionProvider).profile;
    final displayName = profile?.displayName ?? 'FitSocial User';

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.xl,
        ),
        children: [
          _AccountCard(
            displayName: displayName,
            handle: formatHandle(profile?.handle),
            avatarUrl: profile?.avatarUrl,
            onTap: () => context.push('/edit-profile'),
          ),
          const SizedBox(height: AppSpacing.lg),
          const _SectionLabel('Appearance'),
          const _ThemeModePicker(),
          const SizedBox(height: AppSpacing.lg),
          const _SectionLabel('Account'),
          _SettingsTile(
            icon: Icons.person_outline_rounded,
            label: 'Edit profile',
            onTap: () => context.push('/edit-profile'),
          ),
          _SettingsTile(
            icon: Icons.workspace_premium_outlined,
            label: 'Achievements',
            onTap: () => context.push('/achievements'),
          ),
          const SizedBox(height: AppSpacing.lg),
          const _SectionLabel('Activity'),
          _SettingsTile(
            icon: Icons.favorite_outline_rounded,
            label: 'Health data',
            onTap: () => context.push('/health'),
          ),
          const SizedBox(height: AppSpacing.lg),
          const _SectionLabel('Notifications'),
          const _SettingsNote(
            'Notifications are set per person. Open someone\'s profile and '
            'tap the bell to hear about what they post.',
          ),
          const SizedBox(height: AppSpacing.xl),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: palette.danger,
              minimumSize: const Size.fromHeight(56),
              side: BorderSide(color: palette.stroke),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            onPressed: () => _confirmSignOut(context, ref),
            icon: const Icon(Icons.logout_rounded),
            label: const Text(
              'Sign Out',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  /// Signing out drops the whole session, so it asks first.
  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final palette = context.palette;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: palette.surface,
        title: const Text('Sign out?'),
        content: Text(
          "You'll need your email and password to get back in.",
          style: TextStyle(color: palette.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              'Cancel',
              style: TextStyle(color: palette.muted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              'Sign out',
              style: TextStyle(color: palette.danger),
            ),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      // The router's redirect takes over from here and lands on /welcome.
      await ref.read(appSessionProvider).signOut();
    }
  }
}

/// System / Light / Dark, as one segmented control.
///
/// Built from the app's own parts rather than Material's [SegmentedButton],
/// which arrives with its own outline, check marks and selected-fill and would
/// be the only control on the screen that looks like stock Material.
///
/// System is offered — and is the default — because most people set this once
/// at the OS level and expect apps to follow. The other two are for the people
/// who want this app pinned regardless.
class _ThemeModePicker extends ConsumerWidget {
  const _ThemeModePicker();

  static const _options = <(ThemeMode, String, IconData)>[
    (ThemeMode.system, 'System', Icons.brightness_auto_rounded),
    (ThemeMode.light, 'Light', Icons.light_mode_rounded),
    (ThemeMode.dark, 'Dark', Icons.dark_mode_rounded),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final selected = ref.watch(themeModeProvider);

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.stroke),
      ),
      child: Row(
        children: [
          for (final (mode, label, icon) in _options)
            Expanded(
              child: _ThemeModeSegment(
                label: label,
                icon: icon,
                isSelected: mode == selected,
                onTap: () =>
                    ref.read(themeModeProvider.notifier).setMode(mode),
              ),
            ),
        ],
      ),
    );
  }
}

class _ThemeModeSegment extends StatelessWidget {
  const _ThemeModeSegment({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Semantics(
      button: true,
      selected: isSelected,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        // Animated, because the whole screen is already crossfading to the new
        // theme underneath it — a segment that snapped would be the one thing
        // on screen that didn't.
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.orangeBright.withValues(alpha: 0.16)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected ? AppColors.orangeBright : palette.muted,
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? palette.brandText : palette.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.displayName,
    required this.handle,
    required this.onTap,
    this.avatarUrl,
  });

  final String displayName;
  final String handle;
  final VoidCallback onTap;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: palette.stroke),
        ),
        child: Row(
          children: [
            Avatar(
              initials: accountInitials(displayName),
              size: 52,
              imageUrl: avatarUrl,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.text,
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    handle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: palette.muted),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: palette.muted),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: AppSpacing.sm),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: palette.muted,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Icon(icon, color: palette.text),
      title: Text(label, style: TextStyle(color: palette.text)),
      trailing: Icon(Icons.chevron_right_rounded, color: palette.muted),
      onTap: onTap,
    );
  }
}

class _SettingsNote extends StatelessWidget {
  const _SettingsNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        text,
        style: TextStyle(
          color: palette.muted,
          fontSize: 14,
          height: 1.5,
        ),
      ),
    );
  }
}
