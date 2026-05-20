import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/bootstrap/app_bootstrap.dart';
import 'core/bootstrap/bootstrap_status.dart';

Future<void> main() async {
  final bootstrapStatus = await bootstrapApp();

  runApp(
    ProviderScope(
      overrides: [
        bootstrapStatusProvider.overrideWithValue(bootstrapStatus),
      ],
      child: const FitSocialApp(),
    ),
  );
}
