import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_palette.dart';
import '../../shared/widgets/liquid_glass.dart';
import '../../shared/widgets/primary_button.dart';
import '../config/feature_flags.dart';

/// The workout features Premium will unlock, once there is a Premium.
///
/// What stays free is decided as much by what is not here: logging of every
/// kind, set types, RPE, the rest timer, supersets, PREVIOUS, live records and
/// the all-time record list, custom exercises, and the warm-up and plate
/// calculators. Nothing free today is ever taken away.
enum PremiumFeature {
  /// More than [freeRoutineLimit] routines.
  unlimitedRoutines(
    'Unlimited routines',
    'Free accounts keep up to $freeRoutineLimit routines. Premium keeps as '
        'many as you like, in as many folders.',
  ),

  /// Exercise charts past the last three months.
  longRangeCharts(
    'Long-range progress',
    'Free accounts chart the last three months. Premium charts a year, or '
        'everything you have ever logged.',
  ),

  /// The heaviest weight at every rep count.
  setRecords(
    'Set records',
    'The heaviest weight you have lifted at every rep count from 1 to 12.',
  ),

  /// Muscle ranges past this week.
  muscleHistory(
    'Muscle history',
    'Free accounts see this week. Premium adds last week and the last 30 '
        'days.',
  ),

  /// The month-by-month training report.
  monthlyReport(
    'Monthly report',
    'A month of training against the month before: sets per muscle, what '
        'was in target, what was missed.',
  );

  const PremiumFeature(this.title, this.pitch);

  final String title;
  final String pitch;
}

/// How many routines a free account keeps — the spec's suggested five.
const freeRoutineLimit = 5;

/// Whether the signed-in user has Premium.
///
/// False for everyone: billing is not built yet. This is the one seam a
/// subscription check replaces, and whatever replaces it must be enforced on
/// the server too — a client-side gate is a suggestion.
final premiumProvider = Provider<bool>((ref) => false);

/// Whether [feature] is locked for this user right now: the gates are on
/// and they do not have Premium. With the gates off — the default — nothing
/// is ever locked.
final premiumLockedProvider =
    Provider.family<bool, PremiumFeature>((ref, feature) {
  if (!ref.watch(featureEnabledProvider(FeatureFlag.workoutPremiumGates))) {
    return false;
  }
  return !ref.watch(premiumProvider);
});

/// Returns true and shows the Premium sheet when [feature] is locked; false,
/// doing nothing, when it is open. The caller goes ahead only on false.
bool requiresPremium(
  BuildContext context,
  WidgetRef ref,
  PremiumFeature feature,
) {
  if (!ref.read(premiumLockedProvider(feature))) return false;
  showPremiumSheet(context, feature);
  return true;
}

/// The paywall, as a stub: what the feature is, and that Premium is coming.
/// There is nothing to buy yet, so it says so rather than pretending.
Future<void> showPremiumSheet(BuildContext context, PremiumFeature feature) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    isScrollControlled: true,
    builder: (_) => _PremiumSheet(feature: feature),
  );
}

class _PremiumSheet extends StatelessWidget {
  const _PremiumSheet({required this.feature});

  final PremiumFeature feature;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        12,
        0,
        12,
        12 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      child: LiquidGlass(
        lens: true,
        borderRadius: BorderRadius.circular(28),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: palette.stroke),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: palette.stroke,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Icon(Icons.workspace_premium_rounded,
                      color: palette.brand, size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      feature.title,
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                feature.pitch,
                style: TextStyle(
                  color: palette.text,
                  fontSize: 14.5,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Part of FitSocial Premium, coming soon.',
                style: TextStyle(color: palette.muted, fontSize: 13),
              ),
              const SizedBox(height: 18),
              PrimaryButton(
                label: 'Got it',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small lock beside a gated choice, so it reads as Premium before it is
/// tapped. Nothing when the feature is open.
class PremiumLock extends ConsumerWidget {
  const PremiumLock({required this.feature, super.key});

  final PremiumFeature feature;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(premiumLockedProvider(feature))) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Icon(
        Icons.lock_rounded,
        size: 14,
        color: context.palette.muted,
        semanticLabel: 'Premium',
      ),
    );
  }
}
