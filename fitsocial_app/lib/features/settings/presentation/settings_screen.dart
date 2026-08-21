import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/theme_mode_controller.dart';
import '../../../shared/widgets/avatar.dart';
import '../../../shared/widgets/quick_toast.dart';
import '../../auth/application/app_session.dart';
import '../../auth/presentation/account_switcher_sheet.dart';
import '../../../shared/links/share_links.dart';
import '../../music/presentation/music_island_action.dart';
import 'delete_account_sheet.dart';
import '../../../shared/widgets/liquid_glass.dart';

/// One accent per row, following the Create screen's rule: a hue identifies
/// *what the row is about*, so it stays the same in both themes and is resolved
/// through `palette.accent` at paint time rather than being picked per theme.
///
/// Deliberately a short list. Settings is a page you scan, and a fresh hue on
/// every row would turn the icon column into confetti — the ones here are the
/// three destinations, plus the bell, which is the only row that isn't one.
const Color _kProfileAccent = AppColors.orangeBright;
const Color _kAchievementAccent = Color(0xFFF2B01E);
const Color _kHealthAccent = Color(0xFFFF5C7A);
const Color _kNotifyAccent = Color(0xFF2ECBFF);

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(appSessionProvider).profile;
    final displayName = profile?.displayName ?? 'FitSocial User';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: const [MusicIslandAction()],
      ),
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
          _SettingsGroup(
            children: [
              _SettingsTile(
                icon: Icons.person_outline_rounded,
                accent: _kProfileAccent,
                label: 'Edit profile',
                subtitle: 'Name, username, photo and bio',
                onTap: () => context.push('/edit-profile'),
              ),
              _SettingsTile(
                icon: Icons.workspace_premium_outlined,
                accent: _kAchievementAccent,
                label: 'Achievements',
                subtitle: 'Badges you have earned so far',
                onTap: () => context.push('/achievements'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          const _SectionLabel('Activity'),
          _SettingsGroup(
            children: [
              _SettingsTile(
                icon: Icons.favorite_outline_rounded,
                accent: _kHealthAccent,
                label: 'Health data',
                subtitle: 'Steps, heart rate and connected devices',
                onTap: () => context.push('/health'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          const _SectionLabel('Notifications'),
          const _SettingsNote(
            icon: Icons.notifications_none_rounded,
            accent: _kNotifyAccent,
            text: 'Notifications are set per person. Open someone\'s profile '
                'and tap the bell to hear about what they post.',
          ),
          const SizedBox(height: AppSpacing.lg),
          const _SectionLabel('About'),
          _SettingsGroup(
            children: [
              // No accent, so it takes the brand hue. The accent list at the
              // top of this file is deliberately short, and a legal page is
              // not the row that should earn a fifth colour.
              _SettingsTile(
                icon: Icons.privacy_tip_outlined,
                label: 'Privacy policy',
                subtitle: 'What we collect, and how to get rid of it',
                onTap: () => _openPrivacyPolicy(context),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          _SettingsGroup(
            children: [
              _SettingsTile(
                icon: Icons.logout_rounded,
                label: 'Sign out',
                subtitle: 'You will need your password to get back in',
                isDanger: true,
                showChevron: false,
                onTap: () => _confirmSignOut(context, ref),
              ),
              // Below sign-out, and last on the page. Both are red, and the
              // one that is merely inconvenient should not sit under the one
              // that is irreversible.
              _SettingsTile(
                icon: Icons.delete_forever_rounded,
                label: 'Delete account',
                subtitle: 'Permanently erase your account and everything in it',
                isDanger: true,
                showChevron: false,
                onTap: () => showDeleteAccountSheet(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Opens the hosted privacy policy in a browser.
  ///
  /// Deliberately external rather than a screen inside the app. The policy has
  /// to stay reachable by somebody who has signed out or deleted the app, the
  /// Play listing needs the same URL, and two copies of a legal document is one
  /// copy too many — the hosted page is the only version there is.
  ///
  /// Note this only lands in a browser because the App Link intent filter in
  /// AndroidManifest.xml is scoped to /post/ and /user/. A host-wide claim
  /// would send this straight back into the app, which has no route for it.
  Future<void> _openPrivacyPolicy(BuildContext context) async {
    final url = FitSocialLinks.privacyPolicy;
    // Resolved before the await: the context may be gone by the time a failing
    // launch comes back, and the overlay cannot be looked up from a dead one.
    final overlay = Overlay.of(context, rootOverlay: true);

    var opened = false;
    try {
      opened = await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {
      // A device with no browser at all. Handled the same as a refusal below.
    }

    if (opened) return;
    // The address is in the message on purpose: a user who cannot open it here
    // can still read the policy by typing it somewhere else, which is the
    // whole point of hosting it publicly.
    showQuickToastOn(
      overlay,
      'Could not open a browser. Visit $url',
      icon: Icons.error_outline_rounded,
      tone: ToastTone.danger,
      visibleFor: const Duration(milliseconds: 4000),
    );
  }

  /// Signing out drops the whole session, so it asks first.
  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final palette = context.palette;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => LiquidGlass(
        // A dialog interrupts a page, so there is always something
        // behind it -- which makes it glass like everything else.
        borderRadius: BorderRadius.circular(22),
        child: AlertDialog(
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

    return LiquidGlass(
      // Painted by the lens now rather than by a fill of its own:
      // a pane over the app backdrop, like every other card.
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
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
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? palette.brandSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(15),
            // The pill needs an edge of its own on light, where `brandSoft` is
            // pale enough against white that fill alone barely reads as a
            // selection.
            border: Border.all(
              color: isSelected ? palette.brandSoftStroke : Colors.transparent,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected ? palette.brand : palette.muted,
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

/// The person whose settings these are, at the top of their own page.
///
/// Washed with the brand rather than left as another plain card: it is the one
/// element here that is about *you* instead of about a preference, and the
/// gradient is what stops the page opening on four identical rectangles.
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
    return Container(
      decoration: BoxDecoration(
        // Stops short of the far corner so the wash reads as light falling
        // across the card rather than as a two-tone block.
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.brandSoft, palette.surface],
          stops: const [0, 0.85],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: palette.brandSoftStroke),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Avatar(
                  initials: accountInitials(displayName),
                  size: 58,
                  imageUrl: avatarUrl,
                  // The one place a brand ring is earned: this card exists to
                  // point at a person.
                  border: AvatarBorder.brand,
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
                          fontSize: 18,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        handle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.muted,
                          fontSize: 13.5,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Edit profile',
                        style: TextStyle(
                          color: palette.brandText,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: palette.brandText,
                ),
              ],
            ),
          ),
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
      padding: const EdgeInsets.only(left: 6, bottom: AppSpacing.sm),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: palette.muted,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

/// The rows of one section, banded together in a single card.
///
/// Grouping is the whole point: bare [ListTile]s on the page put every row on
/// its own with nothing tying a section together, so the headings did all the
/// structural work alone. One card per section draws the section instead, and
/// the hairlines inside it separate rows without cutting the card in half —
/// they start past the icon column, the way a grouped list is normally set.
class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return LiquidGlass(
      // Painted by the lens now rather than by a fill of its own:
      // a pane over the app backdrop, like every other card.
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: palette.stroke),
        ),
        // So a row's ripple stops at the card's rounded corner instead of
        // squaring it off.
        clipBehavior: Clip.antiAlias,
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    thickness: 1,
                    // 14 padding + 40 well + 14 gap: the hairline starts where
                    // the labels do.
                    indent: 68,
                    color: palette.stroke,
                  ),
                children[i],
              ],
            ],
          ),
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
    this.subtitle,
    this.accent,
    this.isDanger = false,
    this.showChevron = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// The one line under the label that says what the row actually opens.
  final String? subtitle;

  /// The hue that identifies this row, unadjusted — the tile resolves it for
  /// the current theme. Ignored when [isDanger] is set.
  final Color? accent;

  /// Paints the row in the palette's danger colour and skips the accent
  /// machinery, which would deepen an already-tuned red a second time.
  final bool isDanger;

  /// Off for rows that act in place rather than navigating; a chevron on a
  /// row that opens a dialog promises a page that never arrives.
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final hue = accent ?? palette.brand;
    final glyph = isDanger ? palette.danger : palette.accent(hue);
    final well = isDanger
        ? Color.alphaBlend(
            palette.danger.withValues(alpha: palette.isDark ? 0.18 : 0.10),
            palette.surface,
          )
        : palette.accentFill(hue);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: well,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: glyph, size: 21),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: isDanger ? palette.danger : palette.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        color: palette.muted,
                        fontSize: 12.5,
                        height: 1.3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (showChevron)
              Icon(
                Icons.chevron_right_rounded,
                color: palette.muted,
                size: 22,
              ),
          ],
        ),
      ),
    );
  }
}

/// A section that explains something instead of offering a row to tap.
///
/// Still a card, so the page keeps one rhythm — an unboxed paragraph between
/// two boxed sections reads as text that lost its container.
class _SettingsNote extends StatelessWidget {
  const _SettingsNote({
    required this.icon,
    required this.accent,
    required this.text,
  });

  final IconData icon;
  final Color accent;
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return LiquidGlass(
      // Painted by the lens now rather than by a fill of its own:
      // a pane over the app backdrop, like every other card.
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: palette.stroke),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: palette.accentFill(accent),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: palette.accent(accent), size: 21),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  color: palette.muted,
                  fontSize: 13.5,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
