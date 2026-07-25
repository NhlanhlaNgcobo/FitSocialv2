import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../shared/widgets/fit_social_logo.dart';

/// Shown on cold start while [AppSession] restores a persisted Firebase
/// session. The router swaps this for /home, /profile-setup, or /welcome
/// once bootstrap completes.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FitSocialLogo(size: 48, animated: true),
            SizedBox(height: 32),
            SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppColors.orangeBright,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
