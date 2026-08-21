import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/identity/profile_identity.dart';
import '../../../shared/widgets/avatar.dart';
import '../../../shared/widgets/quick_toast.dart';
import '../application/app_session.dart';
import '../../../shared/widgets/liquid_glass.dart';

/// The account list behind the chevron next to the profile name.
///
/// Lists the account that is signed in, then offers to add another. Firebase
/// Auth holds one signed-in user per app instance, so "Add account" cannot
/// simply open the login screen — a second session has to be stored
/// alongside the first before it can. Until that lands the row says so rather
/// than dropping the user into a flow that would sign them out.
Future<void> showAccountSwitcherSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => const _AccountSwitcherSheet(),
  );
}

class _AccountSwitcherSheet extends ConsumerWidget {
  const _AccountSwitcherSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final profile = ref.watch(appSessionProvider).profile;
    final displayName = profile?.displayName ?? 'FitSocial User';

    return SafeArea(
      top: false,
      child: LiquidGlass(
        // A sheet always has a page behind it, which makes it the
        // one surface guaranteed something worth bending.
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Container(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: AppSpacing.sm),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: palette.stroke,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: 4,
                ),
                leading: Avatar(
                  initials: accountInitials(displayName),
                  size: 44,
                  imageUrl: profile?.avatarUrl,
                ),
                title: Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  formatHandle(profile?.handle),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: palette.muted),
                ),
                trailing: Icon(
                  Icons.check_circle_rounded,
                  color: palette.brand,
                ),
              ),
              Divider(color: palette.stroke, height: 1),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: 4,
                ),
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: palette.stroke),
                  ),
                  child: Icon(
                    Icons.add_rounded,
                    color: palette.brand,
                  ),
                ),
                title: Text(
                  'Add account',
                  style: TextStyle(
                    color: palette.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onTap: () {
                  // Resolved before the pop: afterwards this context is gone
                  // and the overlay can no longer be looked up from it.
                  final overlay = Overlay.of(context, rootOverlay: true);
                  Navigator.of(context).pop();
                  showQuickToastOn(
                    overlay,
                    'A second account is coming soon.',
                    icon: Icons.schedule_rounded,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Initials to stand in for a missing profile photo, empty when the account
/// has no real name yet — see [avatarInitials].
String accountInitials(String value) => avatarInitials(value);

/// Handles are stored bare or with a leading '@' depending on what the user
/// typed, so normalise to exactly one before showing it.
String formatHandle(String? handle) {
  final trimmed = handle?.trim().replaceAll(RegExp(r'^@+'), '') ?? '';
  return trimmed.isEmpty ? '@fitsocial' : '@$trimmed';
}
