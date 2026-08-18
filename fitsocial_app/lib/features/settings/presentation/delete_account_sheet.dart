import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../auth/application/app_session.dart';
import '../../auth/presentation/account_switcher_sheet.dart' show formatHandle;

/// What a user has to type to confirm when their account has no handle yet.
///
/// Reachable: an account that finished sign-up but abandoned profile setup has
/// no username, and it is exactly the account somebody is most likely to want
/// deleted.
const String kDeleteConfirmationFallback = 'DELETE';

/// The phrase this account must type to confirm deletion.
///
/// Their own handle, which asks the person to name what they are destroying
/// rather than to copy a generic word — the difference between reading the
/// dialog and dismissing it.
String deleteConfirmationPhrase(String? handle) {
  final trimmed = handle?.trim().replaceAll(RegExp(r'^@+'), '') ?? '';
  return trimmed.isEmpty ? kDeleteConfirmationFallback : trimmed;
}

/// Whether [typed] confirms deletion for an account whose phrase is [phrase].
///
/// Case-insensitive, and a leading '@' is ignored: the field shows a handle,
/// people type handles with the '@', and refusing that would be pedantry
/// standing between someone and their own data.
bool confirmsDeletion(String typed, String phrase) {
  final normalised = typed.trim().replaceAll(RegExp(r'^@+'), '');
  return normalised.toLowerCase() == phrase.toLowerCase();
}

/// Asks for confirmation, then deletes the account.
///
/// Returns true when the account was deleted, at which point the caller is
/// signed out and the router's redirect takes over.
Future<bool> showDeleteAccountSheet(BuildContext context) async {
  final deleted = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    // Neither dismissible by tap-away nor draggable, unlike every other sheet
    // in the app. A half-swipe that cancels a destructive flow is fine; one
    // that cancels it *mid-delete* is not, and the sheet is the only thing
    // showing the user that work is in progress.
    isDismissible: false,
    enableDrag: false,
    builder: (_) => const _DeleteAccountSheet(),
  );
  return deleted ?? false;
}

class _DeleteAccountSheet extends ConsumerStatefulWidget {
  const _DeleteAccountSheet();

  @override
  ConsumerState<_DeleteAccountSheet> createState() =>
      _DeleteAccountSheetState();
}

class _DeleteAccountSheetState extends ConsumerState<_DeleteAccountSheet> {
  final _controller = TextEditingController();
  bool _isDeleting = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _delete(String phrase) async {
    if (!confirmsDeletion(_controller.text, phrase)) return;

    setState(() {
      _isDeleting = true;
      _error = null;
    });

    final session = ref.read(appSessionProvider);
    final deleted = await session.deleteAccount();

    if (!mounted) return;

    if (deleted) {
      Navigator.of(context).pop(true);
      return;
    }

    setState(() {
      _isDeleting = false;
      _error = session.errorMessage ??
          'Your account could not be deleted. Please try again.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final profile = ref.watch(appSessionProvider).profile;
    final phrase = deleteConfirmationPhrase(profile?.handle);
    final canDelete = confirmsDeletion(_controller.text, phrase);

    return PopScope(
      // The delete is already in flight server-side; backing out of the sheet
      // would not stop it, and would leave the user staring at a settings page
      // for an account that is being erased.
      canPop: !_isDeleting,
      child: Padding(
        // Lifts the sheet clear of the keyboard, which otherwise covers the
        // one field on it.
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SafeArea(
          top: false,
          child: Container(
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.md,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: palette.danger,
                      size: 26,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Delete your account',
                        style: TextStyle(
                          color: palette.text,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'This deletes everything, permanently. There is no undo and '
                  'no way for us to bring it back.',
                  style: TextStyle(color: palette.muted, height: 1.4),
                ),
                const SizedBox(height: AppSpacing.md),
                // Named rather than summarised as "your data": people are
                // entitled to know that the training history goes with the
                // account, and a run log is often the part they would have
                // wanted to keep.
                const _WhatGoes(
                  items: [
                    'Your posts, Pulses, comments and reactions',
                    'Every run, workout and meal you have logged',
                    'Your challenge progress, points and badges',
                    'Your followers and everyone you follow',
                    'Your profile, photos and body metrics',
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: palette.background,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: palette.stroke),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.lock_clock_rounded,
                        size: 18,
                        color: palette.muted,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          'Your username is held for 14 days before anyone '
                          'else can take it.',
                          style: TextStyle(
                            color: palette.muted,
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  phrase == kDeleteConfirmationFallback
                      ? 'Type $kDeleteConfirmationFallback to confirm'
                      : 'Type ${formatHandle(phrase)} to confirm',
                  style: TextStyle(
                    color: palette.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _controller,
                  enabled: !_isDeleting,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.done,
                  inputFormatters: [LengthLimitingTextInputFormatter(40)],
                  style: TextStyle(color: palette.text),
                  decoration: InputDecoration(
                    hintText: phrase == kDeleteConfirmationFallback
                        ? kDeleteConfirmationFallback
                        : formatHandle(phrase),
                    hintStyle: TextStyle(color: palette.muted),
                    filled: true,
                    fillColor: palette.background,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: palette.stroke),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: palette.danger),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => canDelete ? _delete(phrase) : null,
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _error!,
                    style: TextStyle(color: palette.danger, fontSize: 13),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: palette.danger,
                      disabledBackgroundColor: palette.danger.withValues(
                        alpha: 0.35,
                      ),
                      foregroundColor: Colors.white,
                      disabledForegroundColor: Colors.white70,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed:
                        canDelete && !_isDeleting ? () => _delete(phrase) : null,
                    child: _isDeleting
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(width: AppSpacing.sm),
                              // Says "may take a moment" because it genuinely
                              // can: the server is walking every collection,
                              // and silence on a destructive action reads as a
                              // hang.
                              Text('Deleting — this may take a moment'),
                            ],
                          )
                        : const Text(
                            'Delete my account',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: TextButton(
                    onPressed: _isDeleting
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        color: palette.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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

class _WhatGoes extends StatelessWidget {
  const _WhatGoes({required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: palette.danger,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    item,
                    style: TextStyle(color: palette.text, height: 1.35),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
