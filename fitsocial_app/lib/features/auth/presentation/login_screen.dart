import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/brand_image_tile.dart';
import '../../../shared/widgets/fit_social_logo.dart';
import '../../../shared/widgets/primary_button.dart';
import '../application/app_session.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

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
    _emailController = TextEditingController(text: 'neo@fitsocial.app');
    _passwordController = TextEditingController(text: 'password123');
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(32),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF191919), Color(0xFF090909)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    border: Border.all(color: AppColors.stroke),
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
                                AppColors.orangeBright.withOpacity(0.2),
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
                          children: const [
                            FitSocialLogo(size: 36),
                            SizedBox(height: AppSpacing.lg),
                            Text(
                              'Create your account',
                              style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Join the fitness community.',
                              style: TextStyle(color: AppColors.muted, fontSize: 16),
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
              PrimaryButton(
                label: _showEmailForm ? 'Continue with Email' : 'Use Email',
                onPressed: session.isLoading
                    ? null
                    : () {
                        if (_showEmailForm) {
                          ref.read(appSessionProvider).signInWithEmail(
                                email: _emailController.text,
                                password: _passwordController.text,
                              );
                        } else {
                          setState(() {
                            _showEmailForm = true;
                          });
                        }
                      },
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
              const SizedBox(height: AppSpacing.md),
              _SocialButton(
                icon: Icons.apple_rounded,
                label: 'Continue with Apple',
                loading: session.isLoading,
                onPressed: () {
                  ref.read(appSessionProvider).continueWithProvider('apple');
                },
              ),
              if (_showEmailForm) ...[
                const SizedBox(height: AppSpacing.md),
                _EmailPanel(
                  emailController: _emailController,
                  passwordController: _passwordController,
                ),
              ],
              if (session.errorMessage != null) ...[
                const SizedBox(height: AppSpacing.md),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.stroke),
                  ),
                  child: Text(
                    session.errorMessage!,
                    style: const TextStyle(
                      color: AppColors.orangeBright,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
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
  });

  final TextEditingController emailController;
  final TextEditingController passwordController;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.stroke),
      ),
      child: Column(
        children: [
          TextField(
            controller: emailController,
            decoration: const InputDecoration(hintText: 'you@example.com'),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: passwordController,
            obscureText: true,
            decoration: const InputDecoration(hintText: 'Enter your password'),
          ),
        ],
      ),
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
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          side: const BorderSide(color: AppColors.stroke),
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
