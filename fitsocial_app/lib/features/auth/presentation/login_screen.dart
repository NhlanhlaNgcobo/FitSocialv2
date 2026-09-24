import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuthException;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/brand_image_tile.dart';
import '../../../shared/widgets/fit_social_logo.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/quick_toast.dart';
import '../../../shared/widgets/staggered_fade_in.dart';
import '../application/app_session.dart';
import '../data/auth_repository.dart';
import '../domain/username.dart';
import '../../../shared/widgets/liquid_glass.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.isLoginMode = true});

  final bool isLoginMode;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailController;
  late final TextEditingController _passwordController;
  late final TextEditingController _confirmController;
  // One-shot arrival stagger, same convention as profile_setup_screen — this
  // screen used to snap into existence while every other stop on this flow
  // (splash, welcome, profile setup) settles in.
  late final AnimationController _entranceController;
  // Seeded from the route, then owned locally so "Log in ⇄ Sign up" can swap
  // in place without a navigation that would wipe what has been typed.
  late bool _isLoginMode;
  bool _showEmailForm = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  @override
  void initState() {
    super.initState();
    _isLoginMode = widget.isLoginMode;
    _emailController = TextEditingController();
    _passwordController = TextEditingController();
    _confirmController = TextEditingController();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
  }

  /// The "Continue with Email" step: reveals the form, nothing else. Kept
  /// separate from `_submit` so one button never means two different things.
  void _revealEmailForm() {
    setState(() => _showEmailForm = true);
  }

  void _submit(AppSession session) {
    if (session.isLoading) return;

    // Validates before hitting the network, so an empty field or a typo'd
    // confirmation is caught here rather than coming back as a Firebase error.
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_isLoginMode) {
      // Either a username or an email — the session works out which.
      session.signInWithIdentifier(
        identifier: _emailController.text,
        password: _passwordController.text,
      );
    } else {
      session.signUpWithEmail(
        email: _emailController.text,
        password: _passwordController.text,
      );
    }
  }

  void _toggleMode(AppSession session) {
    // The old mode's failure ("that email is already registered") is not about
    // the form the user is now looking at.
    session.clearError();
    setState(() {
      _isLoginMode = !_isLoginMode;
      _confirmController.clear();
    });
  }

  /// Validates the one field that takes a username *or* an email when logging
  /// in, and an email only when signing up.
  ///
  /// Signup stays email-only because an account needs a reachable address
  /// before it has a username: password resets go there, and there is nowhere
  /// else to send them.
  String? _validateIdentifier(String? value) {
    final identifier = value?.trim() ?? '';

    if (identifier.isEmpty) {
      return _isLoginMode
          ? 'Enter your username or email.'
          : 'Enter your email address.';
    }

    if (_isLoginMode && !looksLikeEmail(identifier)) {
      // A username. Checked no further than this on purpose: whether the
      // account exists is the server's answer, and holding old usernames to
      // today's format rules would lock out whoever registered under the old
      // ones.
      if (identifier.contains(RegExp(r'\s'))) {
        return "That username doesn't look valid.";
      }
      return null;
    }

    // Deliberately loose: the goal is to catch fat-fingered input, not to
    // adjudicate RFC 5322. Firebase is the real authority.
    if (!RegExp(r'^[^@\s]+@[^@\s.]+\.[^@\s]+$').hasMatch(identifier)) {
      return "That email address doesn't look valid.";
    }
    return null;
  }

  String? _validatePassword(String? value) {
    final password = value ?? '';
    if (password.isEmpty) return 'Enter your password.';
    // Only enforced on signup — an existing account may predate this rule, and
    // rejecting its password at the door would lock the owner out.
    if (!_isLoginMode && password.length < 6) {
      return 'Use at least 6 characters.';
    }
    return null;
  }

  String? _validateConfirm(String? value) {
    if (_isLoginMode) return null;
    if ((value ?? '').isEmpty) return 'Re-enter your password.';
    if (value != _passwordController.text) return 'Passwords do not match.';
    return null;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _entranceController.dispose();
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

    final overlay = Overlay.of(context, rootOverlay: true);
    try {
      await ref.read(authRepositoryProvider).sendPasswordResetEmail(email);
      if (!mounted) return;
      _resetEmailSent(overlay);
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      // 'user-not-found' is reported as success on purpose: confirming which
      // addresses have accounts would let anyone enumerate our user base.
      if (error.code == 'user-not-found') {
        _resetEmailSent(overlay);
        return;
      }
      // The code is logged rather than shown: the only failure a user can act
      // on is a malformed address, and the rest are ours to fix.
      debugPrint('Password reset failed: ${error.message ?? error.code}');
      _resetEmailFailed(
        overlay,
        error.code == 'invalid-email'
            ? "That email address doesn't look valid."
            : "Couldn't send the reset email. Try again.",
      );
    } catch (error) {
      if (!mounted) return;
      debugPrint('Password reset failed: $error');
      _resetEmailFailed(overlay, "Couldn't send the reset email. Try again.");
    }
  }

  void _resetEmailSent(OverlayState overlay) {
    showQuickToastOn(
      overlay,
      'Reset email sent — check your inbox.',
      icon: Icons.mark_email_read_rounded,
      tone: ToastTone.success,
    );
  }

  void _resetEmailFailed(OverlayState overlay, String message) {
    showQuickToastOn(
      overlay,
      message,
      icon: Icons.error_outline_rounded,
      tone: ToastTone.danger,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final session = ref.watch(appSessionProvider);

    // Google stopped on an email that already has a password. The error
    // banner says what to do; this puts the form for doing it in front of
    // them, already addressed, rather than leaving them to find it.
    ref.listen(
      appSessionProvider.select((s) => s.pendingLinkEmail),
      (_, email) {
        if (email == null) return;
        setState(() {
          _isLoginMode = true;
          _showEmailForm = true;
          _emailController.text = email;
          _passwordController.clear();
          _confirmController.clear();
        });
      },
    );

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StaggeredFadeIn(
                controller: _entranceController,
                index: 0,
                itemCount: 5,
                child: IconButton(
                  onPressed: () => context.go('/welcome'),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              // The hero and the panel below it used to be two `Expanded`
              // siblings whose `flex` flipped between 5:2 and 2:5 — a value
              // `RenderFlex` cannot interpolate, so the hero visibly jump-cut
              // size the instant the email form revealed. A `LayoutBuilder`
              // hands both an explicit share of the same measured height, so
              // the hero can animate its own height instead.
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final heroHeight = constraints.maxHeight *
                        (_showEmailForm ? 2 / 7 : 5 / 7);
                    return Column(
                      children: [
                        StaggeredFadeIn(
                          controller: _entranceController,
                          index: 1,
                          itemCount: 5,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 260),
                            curve: Curves.easeOutCubic,
                            width: double.infinity,
                            height: heroHeight,
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
                                Positioned.fill(
                                  // groupTraining's cell crops toward its
                                  // bottom-right corner, which — once the
                                  // panel shrinks to a short, wide banner
                                  // for the email form — leaves only one
                                  // person awkwardly tight-cropped.
                                  // coastalRunner's composition is already
                                  // horizontal (skyline, water, road), so it
                                  // holds together at that aspect instead.
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 260),
                                    switchInCurve: Curves.easeOutCubic,
                                    switchOutCurve: Curves.easeOutCubic,
                                    child: BrandImageTile(
                                      key: ValueKey(_showEmailForm),
                                      tile: _showEmailForm
                                          ? AppVisualTile.coastalRunner
                                          : AppVisualTile.groupTraining,
                                      borderRadius: const BorderRadius.all(
                                          Radius.circular(32)),
                                      overlay: const Color(0x78050505),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  bottom: 0,
                                  left: 0,
                                  right: 0,
                                  child: Container(
                                    height: 120,
                                    decoration: BoxDecoration(
                                      borderRadius: const BorderRadius.vertical(
                                          bottom: Radius.circular(32)),
                                      gradient: LinearGradient(
                                        colors: [
                                          AppColors.orangeBright
                                              .withValues(alpha: 0.2),
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // This whole header sits on the athlete
                                      // photo and its dark scrim, which are the
                                      // same in both themes — so nothing in it
                                      // takes the palette. FittedBox lets the
                                      // wordmark scale down on a narrow phone
                                      // instead of overflowing the card — the
                                      // same guard profile_setup_screen uses.
                                      const FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerLeft,
                                        child: FitSocialLogo(
                                          size: 36,
                                          color: AppColors.onMedia,
                                        ),
                                      ),
                                      const SizedBox(height: AppSpacing.lg),
                                      // Crossfaded rather than swapped instantly
                                      // — Log In ⇄ Sign Up used to snap the copy
                                      // the moment the mode toggled.
                                      AnimatedSwitcher(
                                        duration:
                                            const Duration(milliseconds: 220),
                                        switchInCurve: Curves.easeOutCubic,
                                        switchOutCurve: Curves.easeOutCubic,
                                        layoutBuilder:
                                            (currentChild, previousChildren) =>
                                                Stack(
                                          alignment: Alignment.centerLeft,
                                          children: [
                                            ...previousChildren,
                                            if (currentChild != null)
                                              currentChild,
                                          ],
                                        ),
                                        child: Text(
                                          _isLoginMode
                                              ? 'Welcome back'
                                              : 'Create your account',
                                          key: ValueKey(_isLoginMode),
                                          style: const TextStyle(
                                            color: AppColors.onMedia,
                                            fontSize: 30,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      AnimatedSwitcher(
                                        duration:
                                            const Duration(milliseconds: 220),
                                        switchInCurve: Curves.easeOutCubic,
                                        switchOutCurve: Curves.easeOutCubic,
                                        layoutBuilder:
                                            (currentChild, previousChildren) =>
                                                Stack(
                                          alignment: Alignment.centerLeft,
                                          children: [
                                            ...previousChildren,
                                            if (currentChild != null)
                                              currentChild,
                                          ],
                                        ),
                                        child: Text(
                                          _isLoginMode
                                              ? 'Log in to continue.'
                                              : 'Join the fitness community.',
                                          key: ValueKey(_isLoginMode),
                                          style: const TextStyle(
                                            color: AppColors.onMediaMuted,
                                            fontSize: 16,
                                          ),
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
                        // Shares leftover height with the hero above exactly
                        // like the fields did before — it can shrink and
                        // scroll instead of overflowing on a short screen or
                        // with the keyboard up. AnimatedSize only smooths its
                        // own growth from zero to full.
                        Expanded(
                          child: StaggeredFadeIn(
                            controller: _entranceController,
                            index: 2,
                            itemCount: 5,
                            child: SingleChildScrollView(
                              child: AnimatedSize(
                                duration: const Duration(milliseconds: 260),
                                curve: Curves.easeOutCubic,
                                alignment: Alignment.topCenter,
                                child: _showEmailForm
                                    ? _EmailPanel(
                                        formKey: _formKey,
                                        emailController: _emailController,
                                        passwordController: _passwordController,
                                        confirmController: _confirmController,
                                        isLoginMode: _isLoginMode,
                                        obscurePassword: _obscurePassword,
                                        obscureConfirm: _obscureConfirm,
                                        onTogglePassword: () => setState(
                                          () => _obscurePassword =
                                              !_obscurePassword,
                                        ),
                                        onToggleConfirm: () => setState(
                                          () => _obscureConfirm =
                                              !_obscureConfirm,
                                        ),
                                        validateEmail: _validateIdentifier,
                                        validatePassword: _validatePassword,
                                        validateConfirm: _validateConfirm,
                                        onSubmitted: () => _submit(session),
                                        // Only offered when logging in — there
                                        // is no password to reset while
                                        // creating an account.
                                        onForgotPassword: _isLoginMode
                                            ? _handleForgotPassword
                                            : null,
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              // The reveal ("Continue with Email") and the submit ("Log In" /
              // "Create Account") are two distinct buttons, never the same
              // control relabelled — so a tap always does what it currently
              // says. Only how they're presented (a crossfade) changed.
              StaggeredFadeIn(
                controller: _entranceController,
                index: 2,
                itemCount: 5,
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: session.errorMessage == null
                      ? const SizedBox(width: double.infinity)
                      : Column(
                          key: ValueKey(session.errorMessage),
                          children: [
                            LiquidGlass(
                              // Painted by the lens rather than by a fill of
                              // its own: a pane over the app backdrop, like
                              // every other card.
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
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
                            ),
                            const SizedBox(height: AppSpacing.md),
                          ],
                        ),
                ),
              ),
              StaggeredFadeIn(
                controller: _entranceController,
                index: 2,
                itemCount: 5,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeOutCubic,
                  child: PrimaryButton(
                    key: ValueKey(
                      '$_showEmailForm-$_isLoginMode-${session.isLoading}',
                    ),
                    label: !_showEmailForm
                        ? 'Continue with Email'
                        : (session.isLoading
                            ? 'Please wait…'
                            : (_isLoginMode ? 'Log In' : 'Create Account')),
                    onPressed: session.isLoading
                        ? null
                        : (!_showEmailForm
                            ? _revealEmailForm
                            : () => _submit(session)),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              StaggeredFadeIn(
                controller: _entranceController,
                index: 3,
                itemCount: 5,
                child: _SocialButton(
                  icon: SvgPicture.asset(
                    'assets/images/google_logo.svg',
                    width: 20,
                    height: 20,
                  ),
                  label: _isLoginMode
                      ? 'Continue with Google'
                      : 'Sign up with Google',
                  loading: session.isLoading,
                  onPressed: () {
                    ref.read(appSessionProvider).continueWithProvider('google');
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              StaggeredFadeIn(
                controller: _entranceController,
                index: 4,
                itemCount: 5,
                child: Center(
                  child: TextButton(
                    onPressed:
                        session.isLoading ? null : () => _toggleMode(session),
                    child: RichText(
                      text: TextSpan(
                        style: TextStyle(color: palette.muted, fontSize: 14),
                        children: [
                          TextSpan(
                            text: _isLoginMode
                                ? "Don't have an account? "
                                : 'Already have an account? ',
                          ),
                          TextSpan(
                            text: _isLoginMode ? 'Sign up' : 'Log in',
                            style: const TextStyle(
                              color: AppColors.orangeBright,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
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
    required this.formKey,
    required this.emailController,
    required this.passwordController,
    required this.confirmController,
    required this.isLoginMode,
    required this.obscurePassword,
    required this.obscureConfirm,
    required this.onTogglePassword,
    required this.onToggleConfirm,
    required this.validateEmail,
    required this.validatePassword,
    required this.validateConfirm,
    required this.onSubmitted,
    this.onForgotPassword,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final TextEditingController confirmController;
  final bool isLoginMode;
  final bool obscurePassword;
  final bool obscureConfirm;
  final VoidCallback onTogglePassword;
  final VoidCallback onToggleConfirm;
  final FormFieldValidator<String> validateEmail;
  final FormFieldValidator<String> validatePassword;
  final FormFieldValidator<String> validateConfirm;
  final VoidCallback onSubmitted;
  final VoidCallback? onForgotPassword;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return LiquidGlass(
      // Painted by the lens rather than by a fill of its own: a pane
      // over the app backdrop, like every other card.
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: palette.stroke),
        ),
        child: Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isLoginMode ? 'Username or email' : 'Email',
                style:
                    TextStyle(color: palette.text, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: emailController,
                // The email keyboard is right for signup and wrong for logging in
                // with a username, where its layout buries the letters people
                // actually need behind an '@' and a '.com'.
                keyboardType: isLoginMode
                    ? TextInputType.text
                    : TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                // Offering `username` as well lets a password manager fill either
                // credential; `email` alone would leave a saved username unfilled.
                autofillHints: isLoginMode
                    ? const [AutofillHints.username, AutofillHints.email]
                    : const [AutofillHints.email],
                validator: validateEmail,
                decoration: InputDecoration(
                  hintText: isLoginMode
                      ? 'yourhandle or you@example.com'
                      : 'you@example.com',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Password',
                style:
                    TextStyle(color: palette.text, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: passwordController,
                obscureText: obscurePassword,
                textInputAction:
                    isLoginMode ? TextInputAction.done : TextInputAction.next,
                autofillHints: [
                  isLoginMode
                      ? AutofillHints.password
                      : AutofillHints.newPassword,
                ],
                validator: validatePassword,
                onFieldSubmitted: (_) {
                  if (isLoginMode) onSubmitted();
                },
                decoration: InputDecoration(
                  hintText: isLoginMode
                      ? 'Enter your password'
                      : 'At least 6 characters',
                  suffixIcon: _VisibilityToggle(
                    obscured: obscurePassword,
                    onPressed: onTogglePassword,
                  ),
                ),
              ),
              if (!isLoginMode) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Confirm Password',
                  style: TextStyle(
                      color: palette.text, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: confirmController,
                  obscureText: obscureConfirm,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.newPassword],
                  validator: validateConfirm,
                  onFieldSubmitted: (_) => onSubmitted(),
                  decoration: InputDecoration(
                    hintText: 'Re-enter your password',
                    suffixIcon: _VisibilityToggle(
                      obscured: obscureConfirm,
                      onPressed: onToggleConfirm,
                    ),
                  ),
                ),
              ],
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
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The eye button inside a password field. Split out so the password and the
/// confirmation get an identical control.
class _VisibilityToggle extends StatelessWidget {
  const _VisibilityToggle({required this.obscured, required this.onPressed});

  final bool obscured;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      iconSize: 20,
      color: context.palette.muted,
      tooltip: obscured ? 'Show password' : 'Hide password',
      icon: Icon(
        obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
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
    return LiquidGlass(
      // A dialog interrupts a page, so there is always something
      // behind it -- which makes it glass like everything else.
      borderRadius: BorderRadius.circular(22),
      child: AlertDialog(
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

  final Widget icon;
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
        icon: icon,
        label: Text(label),
      ),
    );
  }
}
