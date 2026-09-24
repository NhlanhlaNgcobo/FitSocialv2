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
import '../../notifications/application/push_providers.dart';
import '../../tracking/application/run_draft_providers.dart';
import 'delete_account_sheet.dart';
import 'set_password_sheet.dart';
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
const Color _kSafetyAccent = Color(0xFF2E9C94);

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(appSessionProvider);
    final profile = session.profile;
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
              // Only for accounts with no password — usually Google-only ones.
              // For them Forgot Password silently sends nothing, so without
              // this the account has exactly one way in.
              if (session.canAddPassword)
                _SettingsTile(
                  icon: Icons.password_rounded,
                  accent: _kProfileAccent,
                  label: 'Set a password',
                  subtitle: 'So you can also log in with your email',
                  onTap: () => _setPassword(context),
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
              const _RunImportTile(),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const _SettingsNote(
            icon: Icons.directions_run_rounded,
            accent: _kHealthAccent,
            text: 'A run your watch recorded turns up on the Create page as a '
                'draft. It stays on your phone until you post it.',
          ),
          const SizedBox(height: AppSpacing.lg),
          const _SectionLabel('Safety'),
          _SettingsGroup(
            children: [
              _SettingsTile(
                icon: Icons.shield_outlined,
                accent: _kSafetyAccent,
                label: 'Safety',
                subtitle: 'Panic alert, safety contacts and PINs',
                onTap: () => context.push('/safety'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          const _SectionLabel('Notifications'),
          const _SettingsGroup(children: [_PushNotificationsTile()]),
          const SizedBox(height: AppSpacing.sm),
          const _SettingsNote(
            icon: Icons.notifications_none_rounded,
            accent: _kNotifyAccent,
            text: 'Open someone\'s profile and tap the bell to hear about '
                'what they post.',
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

  Future<void> _setPassword(BuildContext context) async {
    final overlay = Overlay.of(context, rootOverlay: true);
    final added = await showSetPasswordSheet(context);
    if (!added) return;
    showQuickToastOn(
      overlay,
      'Password set. You can now log in with it.',
      icon: Icons.check_circle_outline_rounded,
      tone: ToastTone.success,
    );
  }

  /// Signing out drops the whole session, so it asks first.
  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final palette = context.palette;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
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

/// The master switch for push.
///
/// The switch reflects a choice stored on this device, not on the account:
/// silencing FitSocial on a phone says nothing about a tablet. Turning it off
/// deletes this device's registration token, which is what actually stops
/// anything being sent — the stored preference only remembers the answer for
/// the next launch.
/// The switch for filing runs the app finds in the platform health store.
///
/// Sits under Health data and takes its hue, rather than earning one of its
/// own: it is about the same connection, and the accent list at the top of this
/// file is short on purpose.
///
/// Stateless where [_PushNotificationsTile] is not, because there is no system
/// dialog behind this one and nothing to hold the switch down for — the store
/// is written in the background and the switch moves at once.
class _RunImportTile extends ConsumerWidget {
  const _RunImportTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _SettingsSwitchTile(
      icon: Icons.directions_run_rounded,
      accent: _kHealthAccent,
      label: 'Find runs I record elsewhere',
      subtitle: 'Save runs from your watch or health app as drafts',
      value: ref.watch(runImportEnabledProvider),
      onChanged: (next) =>
          ref.read(runImportEnabledProvider.notifier).set(enabled: next),
    );
  }
}

class _PushNotificationsTile extends ConsumerStatefulWidget {
  const _PushNotificationsTile();

  @override
  ConsumerState<_PushNotificationsTile> createState() =>
      _PushNotificationsTileState();
}

class _PushNotificationsTileState
    extends ConsumerState<_PushNotificationsTile> {
  /// Held down while the change is in flight, because turning this on can put
  /// the system permission dialog on screen and a second tap behind it would
  /// queue a contradictory change.
  bool _isChanging = false;

  @override
  Widget build(BuildContext context) {
    // Defaults to on while the stored answer loads, matching what the store
    // itself falls back to — so the switch never shows the opposite of what it
    // is a moment away from showing.
    final isOn = ref.watch(pushEnabledProvider).valueOrNull ?? true;

    return _SettingsSwitchTile(
      icon: Icons.notifications_active_rounded,
      accent: _kNotifyAccent,
      label: 'Push notifications',
      subtitle: 'Follows, reactions, comments and challenges',
      value: isOn,
      onChanged: _isChanging ? null : (next) => _change(enabled: next),
    );
  }

  Future<void> _change({required bool enabled}) async {
    final overlay = Overlay.of(context, rootOverlay: true);
    setState(() => _isChanging = true);

    try {
      final willArrive =
          await ref.read(pushPreferenceActionsProvider)(enabled: enabled);

      // The operating system has a switch of its own, and it wins. Someone who
      // refused the permission prompt would otherwise be left looking at a
      // switch that says on beside a phone that never makes a sound.
      if (enabled && !willArrive) {
        showQuickToastOn(
          overlay,
          'Android is blocking notifications for FitSocial. Turn them on in '
          'your phone settings.',
          icon: Icons.error_outline_rounded,
          tone: ToastTone.danger,
        );
      }
    } catch (error) {
      debugPrint('Changing push notifications failed: $error');
      showQuickToastOn(
        overlay,
        "Couldn't change notifications. Try again.",
        icon: Icons.error_outline_rounded,
        tone: ToastTone.danger,
      );
    } finally {
      if (mounted) setState(() => _isChanging = false);
    }
  }
}

/// A row that acts in place, with a switch where [_SettingsTile] has a chevron.
///
/// Deliberately a sibling of [_SettingsTile] rather than a flag on it: the two
/// share a layout and nothing else — this one has no destination, no danger
/// variant, and a tap that means something different.
class _SettingsSwitchTile extends StatelessWidget {
  const _SettingsSwitchTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.accent,
  });

  final IconData icon;
  final String label;
  final String? subtitle;

  /// The hue that identifies this row, unadjusted — resolved for the current
  /// theme here, as [_SettingsTile] does it.
  final Color? accent;

  final bool value;

  /// Null while a change is in flight, which greys the switch and refuses the
  /// tap.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final hue = accent ?? palette.brand;
    final glyph = palette.accent(hue);
    final well = palette.accentFill(hue);
    final change = onChanged;

    return InkWell(
      // The whole row, not just the switch: a 40dp target at the far edge of a
      // phone is the hardest thing on this page to hit.
      onTap: change == null ? null : () => change(!value),
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
                      color: palette.text,
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
            Switch(
              value: value,
              onChanged: change,
              activeTrackColor: glyph,
            ),
          ],
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
