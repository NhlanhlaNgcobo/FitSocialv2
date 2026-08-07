import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuthException;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/brand_image_tile.dart';
import '../../../shared/widgets/fit_social_logo.dart';
import '../../../shared/widgets/primary_button.dart';
import '../application/app_session.dart';
import '../data/auth_repository.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.isLoginMode = true});

  final bool isLoginMode;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  late final TextEditingController _emailController;
  late final TextEditingController _passwordController;
  bool _showEmailForm = false;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController();
    _passwordController = TextEditingController();
  }

  void _submit(AppSession session) {
    if (!_showEmailForm) {
      setState(() => _showEmailForm = true);
      return;
    }
    if (widget.isLoginMode) {
      session.signInWithEmail(
        email: _emailController.text,
        password: _passwordController.text,
      );
    } else {
      session.signUpWithEmail(
        email: _emailController.text,
        password: _passwordController.text,
      );
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleForgotPassword() async {
    final email = await showDialog<String>(
      context: context,
      builder: (_) => _ForgotPasswordDialog(
        initialEmail: _emailController.text.trim(),
      ),
    );
    if (email == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(authRepositoryProvider).sendPasswordResetEmail(email);
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Password reset email sent! Check your inbox.'),
        ),
      );
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      // 'user-not-found' is reported as success on purpose: confirming which
      // addresses have accounts would let anyone enumerate our user base.
      if (error.code == 'user-not-found') {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Password reset email sent! Check your inbox.'),
          ),
        );
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            error.code == 'invalid-email'
                ? "That email address doesn't look valid."
                : 'Could not send the reset email: ${error.message ?? error.code}',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Could not send the reset email: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final session = ref.watch(appSessionProvider);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                onPressed: () => context.go('/welcome'),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              const SizedBox(height: AppSpacing.sm),
              Expanded(
                flex: _showEmailForm ? 2 : 5,
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(32),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF191919), Color(0xFF090909)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    border: Border.all(color: palette.stroke),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    children: [
                      const Positioned.fill(
                        child: BrandImageTile(
                          tile: AppVisualTile.groupTraining,
                          borderRadius: BorderRadius.all(Radius.circular(32)),
                          overlay: Color(0x78050505),
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          height: 120,
                          decoration: BoxDecoration(
                            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
                            gradient: LinearGradient(
                              colors: [
                                AppColors.orangeBright.withValues(alpha: 0.2),
                                Colors.transparent,
                              ],
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 28,
                        left: 24,
                        right: 24,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // This whole header sits on the athlete photo and
                            // its dark scrim, which are the same in both
                            // themes — so nothing in it takes the palette.
                            const FitSocialLogo(
                              size: 36,
                              color: AppColors.onMedia,
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            Text(
                              widget.isLoginMode ? 'Welcome back' : 'Create your account',
                              style: const TextStyle(
                                color: AppColors.onMedia,
                                fontSize: 30,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              widget.isLoginMode ? 'Log in to continue.' : 'Join the fitness community.',
                              style: const TextStyle(
                                color: AppColors.onMediaMuted,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Positioned(
                        right: 24,
                        bottom: 26,
                        child: Icon(
                          Icons.arrow_outward_rounded,
                          size: 58,
                          color: AppColors.orangeBright,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              // Email fields appear ABOVE the primary CTA once revealed, so
              // the flow reads top-to-bottom: enter details, then submit.
              if (_showEmailForm) ...[
                _EmailPanel(
                  emailController: _emailController,
                  passwordController: _passwordController,
                  onSubmitted: () => _submit(session),
                  // Only offered when logging in — there is no password to
                  // reset while creating an account.
                  onForgotPassword:
                      widget.isLoginMode ? _handleForgotPassword : null,
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              if (session.errorMessage != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: palette.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: palette.stroke),
                  ),
                  child: Text(
                    session.errorMessage!,
                    style: const TextStyle(
                      color: AppColors.orangeBright,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              PrimaryButton(
                label: session.isLoading
                    ? 'Please wait…'
                    : _showEmailForm
                        ? (widget.isLoginMode ? 'Log In' : 'Sign Up')
                        : 'Use Email',
                onPressed: session.isLoading ? null : () => _submit(session),
              ),
              const SizedBox(height: AppSpacing.md),
              _SocialButton(
                icon: Icons.mail_outline_rounded,
                label: 'Continue with Google',
                loading: session.isLoading,
                onPressed: () {
                  ref.read(appSessionProvider).continueWithProvider('google');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmailPanel extends StatelessWidget {
  const _EmailPanel({
    required this.emailController,
    required this.passwordController,
    required this.onSubmitted,
    this.onForgotPassword,
  });

  final TextEditingController emailController;
  final TextEditingController passwordController;
  final VoidCallback onSubmitted;
  final VoidCallback? onForgotPassword;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: palette.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Email',
            style: TextStyle(color: palette.text, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: emailController,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            decoration: const InputDecoration(hintText: 'you@example.com'),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Password',
            style: TextStyle(color: palette.text, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: passwordController,
            obscureText: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onSubmitted(),
            decoration: const InputDecoration(hintText: 'Enter your password'),
          ),
          if (onForgotPassword != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onForgotPassword,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.orangeBright,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Forgot Password?',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Collects the address to send a reset link to. Pops with the trimmed email,
/// or null when dismissed.
class _ForgotPasswordDialog extends StatefulWidget {
  const _ForgotPasswordDialog({required this.initialEmail});

  final String initialEmail;

  @override
  State<_ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<_ForgotPasswordDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final email = _controller.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() {
        _errorText = 'Enter a valid email address.';
      });
      return;
    }
    Navigator.of(context).pop(email);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AlertDialog(
      backgroundColor: palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: palette.stroke),
      ),
      title: const Text(
        'Reset your password',
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "We'll email you a link to set a new password.",
            style: TextStyle(color: palette.muted, height: 1.4),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _controller,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            autocorrect: false,
            autofocus: true,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              hintText: 'you@example.com',
              errorText: _errorText,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(foregroundColor: palette.muted),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _submit,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.orangeBright,
          ),
          child: const Text(
            'Send Link',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.icon,
    required this.label,
    required this.loading,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.text,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          side: BorderSide(color: palette.stroke),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        onPressed: loading ? null : onPressed,
        icon: Icon(icon),
        label: Text(label),
      ),
    );
  }
}
