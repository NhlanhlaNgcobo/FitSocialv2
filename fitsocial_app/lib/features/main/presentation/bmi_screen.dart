import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/dark_card.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../auth/application/body_metrics_providers.dart';
import '../../auth/data/user_profile_repository.dart';
import '../../auth/domain/body_metrics.dart';
import '../../auth/presentation/body_metrics_fields.dart';
import '../../music/presentation/music_island_action.dart';

class BmiScreen extends ConsumerStatefulWidget {
  const BmiScreen({super.key});

  @override
  ConsumerState<BmiScreen> createState() => _BmiScreenState();
}

class _BmiScreenState extends ConsumerState<BmiScreen> {
  /// What the fields currently hold. Seeded from storage on the first load and
  /// owned by [BodyMetricsFields] from then on.
  BodyMetrics _draft = const BodyMetrics();

  bool _isSaving = false;
  String? _errorMessage;

  Future<void> _save() async {
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await ref.read(userProfileRepositoryProvider).saveBodyMetrics(_draft);
      if (!mounted) return;
      // The card on the profile reads the same provider, so it has to be told
      // the stored copy moved.
      ref.invalidate(bodyMetricsProvider);
      Navigator.of(context).maybePop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = "Couldn't save your measurements.");
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final stored = ref.watch(bodyMetricsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('BMI'),
        actions: const [MusicIslandAction()],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          BodyMetricsFields(
            // Empty until the stored values land; the fields adopt them then,
            // and only while nothing has been typed.
            initial: stored.asData?.value ?? const BodyMetrics(),
            enabled: !_isSaving,
            onChanged: (metrics) => _draft = metrics,
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              _errorMessage!,
              style:
                  TextStyle(color: palette.danger, fontWeight: FontWeight.w600),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          PrimaryButton(
            label: _isSaving ? 'Saving…' : 'Save',
            onPressed: _isSaving ? null : _save,
          ),
          const SizedBox(height: AppSpacing.lg),
          const BmiFootnote(),
        ],
      ),
    );
  }
}

/// What BMI is not. Worth saying on a fitness app, where a good chunk of the
/// audience carries the muscle that makes the number lie.
class BmiFootnote extends StatelessWidget {
  const BmiFootnote({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    // A pane rather than loose text under the button. The caveat matters more
    // than its position in the scroll suggests, and on a page whose fields are
    // already glass, bare text was the one thing that read as unfinished.
    return DarkCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: palette.muted),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'BMI is a rough screen, not a diagnosis. It cannot tell muscle '
              'from fat, so athletes often read high. Talk to a professional '
              'before acting on it.',
              style: TextStyle(color: palette.muted, fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
