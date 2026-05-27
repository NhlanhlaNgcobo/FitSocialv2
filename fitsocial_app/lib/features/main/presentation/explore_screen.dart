import 'package:flutter/material.dart';

import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/dark_card.dart';

class ExploreScreen extends StatelessWidget {
  const ExploreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Explore')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: const [
          DarkCard(
            child: Text(
              'Discovery, trending posts, and creator search will appear here once connected.',
              style: TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}
