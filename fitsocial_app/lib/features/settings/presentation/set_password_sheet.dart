import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../auth/application/app_session.dart';
import '../../../shared/widgets/liquid_glass.dart';

/// The shortest password Firebase accepts, and the one signup asks for.
const int kMinPasswordLength = 6;

/// What is wrong with a new [password] and its [confirmation], or null when
/// the pair can be sent.
///
/// Kept out of the widget so the rules are the same ones signup applies, and
/// can be tested without pumping a sheet.
String? validateNewPassword(String password, String confirmation) {
  if (password.isEmpty) return 'Enter a password.';
  if (password.length < kMinPasswordLength) {
    return 'Use at least $kMinPasswordLength characters.';
  }
  if (confirmation != password) return 'Passwords do not match.';
  return null;
}

/// Asks for a new password and adds it to the signed-in account.
///
/// Returns true when the password was added.
Future<bool> showSetPasswordSheet(BuildContext context) async {
  final added = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _SetPasswordSheet(),
  );
  return added ?? false;
}

class _SetPasswordSheet extends ConsumerStatefulWidget {
  const _SetPasswordSheet();

  @override
  ConsumerState<_SetPasswordSheet> createState() => _SetPasswordSheetState();
}

class _SetPasswordSheetState extends ConsumerState<_SetPasswordSheet> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscure = true;
  bool _isSaving = false;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving) return;

    final problem = validateNewPassword(
      _passwordController.text,
      _confirmController.text,
    );
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });

    final session = ref.read(appSessionProvider);
    final added = await session.addPassword(_passwordController.text);

    if (!mounted) return;
    if (added) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _isSaving = false;
      _error = session.errorMessage ??
          'Your password could not be saved. Please try again.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final email = ref.watch(appSessionProvider).email;

    return Padding(
      // Lifts the sheet clear of the keyboard, which would otherwise cover both
      // fields.
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: LiquidGlass(
          lens: true,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: Container(
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
                Text(
                  'Set a password',
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                // Names the address because it is the other half of the new
                // login, and the one they might not realise the account uses.
                Text(
                  'You will be able to log in with ${email ?? 'your email'} '
                  '(or your username) and this password, as well as the way '
                  'you sign in now.',
                  style: TextStyle(color: palette.muted, height: 1.4),
                ),
                const SizedBox(height: AppSpacing.lg),
                TextField(
                  controller: _passwordController,
                  enabled: !_isSaving,
                  obscureText: _obscure,
                  autofocus: true,
                  autofillHints: const [AutofillHints.newPassword],
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    hintText: 'New password (at least $kMinPasswordLength '
                        'characters)',
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => _obscure = !_obscure),
                      iconSize: 20,
                      color: palette.muted,
                      tooltip: _obscure ? 'Show password' : 'Hide password',
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _confirmController,
                  enabled: !_isSaving,
                  obscureText: _obscure,
                  autofillHints: const [AutofillHints.newPassword],
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _save(),
                  decoration: const InputDecoration(
                    hintText: 'Re-enter the password',
                  ),
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
                      backgroundColor: AppColors.orangeBright,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: _isSaving ? null : _save,
                    child: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Save password',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: TextButton(
                    onPressed: _isSaving
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
