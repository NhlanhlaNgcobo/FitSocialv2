import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health/health.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/dark_card.dart';
import '../../../shared/widgets/glass.dart';
import '../../../shared/widgets/staggered_fade_in.dart';
import '../application/heart_rate_connection_controller.dart';
import '../application/tracking_providers.dart';
import '../domain/heart_rate_models.dart';
import '../data/health_service.dart';
import '../../music/presentation/music_island_action.dart';

/// One hue per metric, unadjusted — every tile resolves it for the current
/// theme through [AppPalette.accent], the same way the Create actions and the
/// macro bars do. Picking them here rather than tinting everything brand orange
/// is what lets the grid be read at a glance: the card's shape is the same
/// every day, so colour is the only thing carrying *which number is which*.
const Color _kStepsHue = AppColors.orangeBright;
const Color _kHeartHue = Color(0xFFFF4D6D);
const Color _kSleepHue = Color(0xFF7C6BF5);
const Color _kEnergyHue = Color(0xFFFFA51F);
const Color _kSensorHue = Color(0xFF2ECBFF);
const Color _kDeviceHue = Color(0xFF4FB6A5);

/// Health & Devices: today's metrics from Health Connect (which watches
/// like Galaxy/Pixel/Fitbit sync into), the phone's live step counter,
/// and Bluetooth heart-rate device pairing.
class HealthDashboardScreen extends ConsumerStatefulWidget {
  const HealthDashboardScreen({super.key});

  @override
  ConsumerState<HealthDashboardScreen> createState() =>
      _HealthDashboardScreenState();
}

class _HealthDashboardScreenState extends ConsumerState<HealthDashboardScreen>
    with SingleTickerProviderStateMixin {

  /// Drives the entrance stagger. Runs once, on open — the sections below are
  /// fed by streams that rebuild constantly, and re-running this on every
  /// heartbeat would leave the page permanently sliding around.
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  )..forward();

  @override
  void initState() {
    super.initState();
    // Reconnects the remembered strap on the way in, rather than at app start:
    // waking a chest strap's radio because somebody opened the feed would burn
    // its battery for a screen that never shows a heart rate.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(heartRateConnectionProvider.notifier).restoreIfRemembered();
    });
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  /// Pull-to-refresh, which is the gesture somebody reaches for when the count
  /// here trails what their watch app is showing — the exact situation
  /// [_SyncChip] explains.
  Future<void> _refresh() async {
    ref.invalidate(healthSummaryProvider);
    ref.invalidate(healthDiagnosticsProvider);
    // Awaited so the spinner stays up for as long as the read actually takes.
    // A failure is already rendered by the card below, so it is swallowed here
    // rather than thrown out of the gesture.
    try {
      await ref.read(healthSummaryProvider.future);
    } catch (_) {
      // Shown by the error card.
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final health = ref.watch(healthSummaryProvider);
    final sessionSteps = ref.watch(sessionStepsProvider).valueOrNull;
    final liveBpm = ref.watch(liveHeartRateProvider).valueOrNull;

    final sections = <Widget>[
      _todaySection(palette, health),
      const _DiagnosticsCard(),
      _liveSection(sessionSteps, liveBpm),
      _devicesSection(palette, liveBpm),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Health & Devices'),
        actions: [
          const MusicIslandAction(),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(healthSummaryProvider),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: palette.brand,
        backgroundColor: palette.surface,
        child: ListView(
          // Always scrollable, so the pull gesture is there on a short page —
          // the unavailable state is only a couple of cards tall and is exactly
          // the state somebody wants to retry from.
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.xl,
          ),
          children: [
            for (var i = 0; i < sections.length; i++)
              StaggeredFadeIn(
                controller: _entrance,
                index: i,
                itemCount: sections.length,
                child: Padding(
                  padding: EdgeInsets.only(
                    bottom: i == sections.length - 1 ? 0 : AppSpacing.lg,
                  ),
                  child: sections[i],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _todaySection(AppPalette palette, AsyncValue<HealthSummary> health) {
    final loaded = health.valueOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeading(
          'Today · Health Connect',
          trailing:
              loaded != null && loaded.available ? _SyncChip(loaded) : null,
        ),
        health.when(
          loading: () => const _MetricGridSkeleton(),
          error: (e, _) => _NoticeCard(
            icon: Icons.error_outline_rounded,
            color: palette.danger,
            title: 'Health data unavailable',
            text: '$e',
          ),
          data: (summary) => !summary.available
              ? _NoticeCard(
                  icon: Icons.health_and_safety_outlined,
                  color: palette.accent(_kStepsHue),
                  title: 'Not connected yet',
                  text: 'Health Connect is unavailable or permission was '
                      'denied. Install/enable Health Connect and grant access '
                      '— your smartwatch data (steps, heart rate, sleep) syncs '
                      'through it.',
                )
              : _TodayCard(summary),
        ),
      ],
    );
  }

  Widget _liveSection(int? sessionSteps, int? liveBpm) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeading('Live · Phone sensors'),
        DarkCard(
          child: _MetricRow(
            children: [
              _MetricTile(
                icon: Icons.directions_run_rounded,
                hue: _kSensorHue,
                label: 'Session steps',
                // Grouped the same way the Health Connect count above is —
                // two step counts on one page formatted differently reads as
                // two different kinds of number.
                value: _TodayCard.grouped(sessionSteps ?? 0),
                unit: 'steps',
              ),
              _MetricTile(
                icon: Icons.monitor_heart_rounded,
                hue: _kHeartHue,
                label: 'Live BPM',
                value: liveBpm?.toString(),
                unit: 'bpm',
                // The one tile on the page fed by something beating in real
                // time, so it is the one tile that moves.
                pulse: liveBpm != null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _devicesSection(AppPalette palette, int? liveBpm) {
    final connection = ref.watch(heartRateConnectionProvider);
    final controller = ref.read(heartRateConnectionProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeading('Devices · Bluetooth heart rate'),
        if (connection.deviceName case final name?) ...[
          _ConnectedCard(
            name: name,
            bpm: connection.isLive ? liveBpm : null,
            status: connection.status,
            onForget: controller.forget,
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (connection.status == HeartRateConnectionStatus.failed &&
            connection.remoteId != null) ...[
          TextButton.icon(
            onPressed: controller.retry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Try reconnecting'),
          ),
        ],
        if (connection.message case final message?) ...[
          const SizedBox(height: AppSpacing.md),
          _NoticeCard(
            icon: connection.status == HeartRateConnectionStatus.adapterOff
                ? Icons.bluetooth_disabled_rounded
                : Icons.error_outline_rounded,
            color: palette.danger,
            text: message,
          ),
        ],
        if (connection.discovered.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          DarkCard(
            // Rows band together in one card, the way a grouped list is set,
            // rather than each device arriving as its own floating pane.
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                for (var i = 0; i < connection.discovered.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      thickness: 1,
                      indent: 62,
                      color: palette.stroke,
                    ),
                  _DeviceRow(
                    device: connection.discovered[i],
                    isConnecting:
                        connection.status == HeartRateConnectionStatus.connecting,
                    onConnect: () =>
                        controller.connect(connection.discovered[i]),
                  ),
                ],
              ],
            ),
          ),
        ],
        if (connection.discovered.isEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          const _HintPanel(
            icon: Icons.watch_rounded,
            text: 'Works with smartwatches and chest straps that broadcast '
                'the standard Bluetooth heart-rate profile.',
          ),
        ],
      ],
    );
  }
}

/// The four numbers everybody opens this page for.
///
/// One card, four tiles, lit from behind by how much walking is already done —
/// see [_stepsBloom]. Each tile carries its own hue in a quiet well rather than
/// a bare glyph on the card, so a metric that is missing can go grey without
/// the grid losing its shape.
class _TodayCard extends StatelessWidget {
  const _TodayCard(this.summary);

  final HealthSummary summary;

  /// The heat behind the glass, as the day's walking builds.
  ///
  /// Nothing before the first step is recorded: a card with no data has nothing
  /// to say with colour and stays the plain pane every other card is. Ten
  /// thousand is only the scale the warmth is spread over — the card makes no
  /// claim about a goal, and none is shown.
  static Widget? _stepsBloom(AppPalette palette, int? steps) {
    if (steps == null || steps <= 0) return null;
    final t = (steps / 10000).clamp(0.0, 1.0);

    return GlassBloom(
      colors: [
        palette.brand,
        // The brighter hue joins once the day is genuinely under way, so a long
        // walk gets richer rather than merely louder.
        if (t > 0.5) AppColors.orangeBright,
      ],
      intensity: 0.35 + 0.5 * t,
    );
  }

  /// `8432` becomes `8,432`. Five unbroken digits is the difference between a
  /// step count that is read and one that has to be counted.
  static String grouped(int value) {
    final digits = value.abs().toString();
    final buffer = StringBuffer(value < 0 ? '-' : '');
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  static String? _sleepText(Duration? sleep) => sleep == null
      ? null
      : '${sleep.inHours}h ${sleep.inMinutes.remainder(60)}m';

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return DarkCard(
      backdrop: _stepsBloom(palette, summary.steps),
      child: Column(
        children: [
          _MetricRow(
            children: [
              _MetricTile(
                icon: Icons.directions_walk_rounded,
                hue: _kStepsHue,
                label: 'Steps',
                value: summary.steps == null ? null : grouped(summary.steps!),
                unit: 'steps',
              ),
              _MetricTile(
                icon: Icons.favorite_rounded,
                hue: _kHeartHue,
                label: 'Heart rate',
                value: summary.heartRateBpm?.round().toString(),
                unit: 'bpm',
              ),
            ],
          ),
          const SizedBox(height: 12),
          _MetricRow(
            children: [
              _MetricTile(
                icon: Icons.bedtime_rounded,
                hue: _kSleepHue,
                label: 'Sleep',
                value: _sleepText(summary.sleep),
              ),
              _MetricTile(
                icon: Icons.local_fire_department_rounded,
                hue: _kEnergyHue,
                // Relabelled rather than silently swapped: a watch that only
                // writes total energy reports a figure several times the active
                // one, and under the wrong label it reads as a wild overcount.
                label:
                    summary.caloriesAreTotal ? 'Total energy' : 'Active energy',
                value: summary.activeCaloriesKcal?.round().toString(),
                unit: 'kcal',
              ),
            ],
          ),
          _MissingNote(summary),
        ],
      ),
    );
  }
}

/// Two tiles, side by side and the same height whatever they hold.
class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            Expanded(child: children[i]),
          ],
        ],
      ),
    );
  }
}

/// One number, its unit, and what it is — in a well tinted by [hue].
///
/// A null [value] is the page's "nothing was written" state and is deliberately
/// quiet: the tile keeps its place in the grid but drops its colour, so a watch
/// that only syncs steps reads as three tiles waiting rather than three errors.
class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.icon,
    required this.hue,
    required this.label,
    required this.value,
    this.unit,
    this.pulse = false,
  });

  final IconData icon;
  final Color hue;
  final String label;

  /// Null renders the em dash — see the class comment.
  final String? value;
  final String? unit;

  /// Beats the icon, for a value arriving live.
  final bool pulse;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final has = value != null;

    final glyph = has ? palette.accent(hue) : palette.muted;
    final well = has
        ? palette.accentFill(hue)
        : palette.overlay.withValues(alpha: palette.isDark ? 0.06 : 0.04);

    Widget icon = Icon(this.icon, size: 19, color: glyph);
    if (pulse) icon = _Pulse(child: icon);

    return DecoratedBox(
      decoration: BoxDecoration(
        // Translucent rather than a solid fill, so the card's bloom carries on
        // through the tiles instead of stopping at their edges.
        color: palette.overlay.withValues(alpha: palette.isDark ? 0.05 : 0.03),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.stroke),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: well,
                borderRadius: BorderRadius.circular(12),
              ),
              child: icon,
            ),
            const SizedBox(height: 14),
            // Scaled down rather than wrapped: a five-digit step count on a
            // narrow phone should shrink a point, not fold onto a second line
            // and push the label out of the tile.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    value ?? '—',
                    style: TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                      height: 1,
                      letterSpacing: -0.5,
                      color: has ? palette.text : palette.muted,
                    ),
                  ),
                  if (has && unit != null) ...[
                    const SizedBox(width: 4),
                    Text(
                      unit!,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: palette.muted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 5),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.muted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The grid's shape while the first read is in flight.
///
/// Four empty tiles rather than a spinner in a box: the card lands at the size
/// it will keep, so the page does not jump when the numbers arrive.
class _MetricGridSkeleton extends StatelessWidget {
  const _MetricGridSkeleton();

  @override
  Widget build(BuildContext context) {
    return const DarkCard(
      child: Column(
        children: [
          _MetricRow(children: [_SkeletonTile(), _SkeletonTile()]),
          SizedBox(height: 12),
          _MetricRow(children: [_SkeletonTile(), _SkeletonTile()]),
        ],
      ),
    );
  }
}

class _SkeletonTile extends StatelessWidget {
  const _SkeletonTile();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final block = palette.overlay.withValues(alpha: palette.isDark ? 0.07 : 0.05);

    Widget bar(double width, double height) => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: block,
            borderRadius: BorderRadius.circular(6),
          ),
        );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.overlay.withValues(alpha: palette.isDark ? 0.05 : 0.03),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.stroke),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            bar(34, 34),
            const SizedBox(height: 14),
            bar(62, 23),
            const SizedBox(height: 7),
            bar(44, 10),
          ],
        ),
      ),
    );
  }
}

/// A slow heartbeat for whatever it wraps.
///
/// Deliberately gentle and slow: this sits under a number that is already
/// changing on its own, and anything faster turns a live reading into a
/// flicker.
class _Pulse extends StatefulWidget {
  const _Pulse({required this.child});

  final Widget child;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  late final Animation<double> _scale = Tween<double>(
    begin: 1,
    end: 1.14,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(scale: _scale, child: widget.child);
  }
}

/// Explains blank tiles, when there are any.
///
/// A dash means "nothing was written", which is a normal and permanent state
/// for a lot of watches -- plenty of budget models sync step counts and nothing
/// else, and heart-rate monitoring is commonly off by default even on ones that
/// can do it. Left unexplained, that reads as FitSocial being broken, and the
/// support question that follows is always the same one. Naming the missing
/// metrics and pointing at the diagnostic answers it on the screen where it is
/// asked.
class _MissingNote extends StatelessWidget {
  const _MissingNote(this.summary);

  final HealthSummary summary;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    final missing = <String>[
      if (summary.heartRateBpm == null) 'heart rate',
      if (summary.sleep == null) 'sleep',
      if (summary.activeCaloriesKcal == null) 'calories',
    ];

    // Nothing missing, or nothing arriving at all -- the "Health Connect is
    // unavailable" card already covers the second case and would be repeated.
    if (missing.isEmpty || summary.steps == null) {
      return const SizedBox.shrink();
    }

    final list = missing.length == 1
        ? missing.first
        : '${missing.take(missing.length - 1).join(', ')} and ${missing.last}';

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        children: [
          Divider(height: 1, thickness: 1, color: palette.stroke),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.lightbulb_outline_rounded,
                size: 16,
                color: palette.muted,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'No $list yet. Many watches only sync step counts, and '
                  'heart-rate tracking is often off by default. Diagnostics '
                  'below shows what yours is providing.',
                  style: TextStyle(
                    color: palette.muted,
                    fontSize: 12.5,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Says where the numbers came from, and when.
///
/// The card is a faithful read of Health Connect, but Health Connect is not
/// live: Samsung Health and the watch write into it in batches, so their own
/// screens can sit a few hundred steps ahead. Without a timestamp that gap
/// reads as "FitSocial is wrong". With one it reads as "FitSocial is a few
/// minutes behind", which is both true and something a refresh fixes.
///
/// It sits in the section heading rather than under the numbers: it is a
/// provenance line, and putting it beside the heading keeps the card itself to
/// the four numbers it is for.
class _SyncChip extends StatelessWidget {
  const _SyncChip(this.summary);

  final HealthSummary summary;

  static String _hhmm(DateTime t) {
    final local = t.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  void _explain(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Where this number comes from'),
        content: const Text(
          'FitSocial reads Health Connect — the shared store your watch and '
          'Samsung Health write into. It does not talk to your watch '
          'directly.\n\n'
          'Those apps write in batches rather than continuously, so their own '
          'screens can be ahead of what Health Connect holds. Open Samsung '
          'Health for a few seconds, then refresh here, and the count catches '
          'up.\n\n'
          'Challenge progress keeps the highest count seen during the day, so '
          'a reading that comes back low never erases walking already '
          'recorded.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final asOf = summary.stepsAsOf;
    final readAt = summary.readAt;

    final text = asOf != null
        ? 'Synced ${_hhmm(asOf)}'
        : readAt != null
            ? 'Checked ${_hhmm(readAt)}'
            : 'Health Connect';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _explain(context),
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.fromLTRB(9, 5, 10, 5),
          decoration: BoxDecoration(
            color: palette.surfaceHigh,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: palette.stroke),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.info_outline_rounded, size: 13, color: palette.muted),
              const SizedBox(width: 5),
              Text(
                text,
                style: TextStyle(
                  color: palette.muted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The label over a group of cards, with room for one status on the right.
class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.label, {this.trailing});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Padding(
      padding: const EdgeInsets.only(left: 6, bottom: AppSpacing.sm + 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: TextStyle(
                color: palette.muted,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
          ),
          if (trailing case final trailing?) trailing,
        ],
      ),
    );
  }
}

/// A card that says something rather than showing a number: an error, a
/// permission that was never granted, a scan that failed.
class _NoticeCard extends StatelessWidget {
  const _NoticeCard({
    required this.icon,
    required this.color,
    required this.text,
    this.title,
  });

  final IconData icon;

  /// Already resolved for the theme — pass `palette.accent(hue)` for a hue, or
  /// `palette.danger` straight, which is tuned per theme and would be deepened
  /// a second time by going through `accent`.
  final Color color;

  final String text;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return DarkCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                color.withValues(alpha: palette.isDark ? 0.18 : 0.10),
                palette.surface,
              ),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: color, size: 21),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title case final title?) ...[
                  Text(
                    title,
                    style: TextStyle(
                      color: palette.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  text,
                  style: TextStyle(
                    color: palette.muted,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The quiet panel at the foot of the devices section: what it works with.
class _HintPanel extends StatelessWidget {
  const _HintPanel({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      decoration: BoxDecoration(
        color: palette.overlay.withValues(alpha: palette.isDark ? 0.03 : 0.02),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.stroke),
      ),
      child: Column(
        children: [
          Icon(icon, size: 26, color: palette.muted),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: palette.muted,
              fontSize: 12.5,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

/// The strap this phone is paired with, and what it is currently doing.
///
/// Shows the state rather than just a name: a strap that has dropped looks
/// exactly like a connected one if all you render is the last reading, which is
/// the confusion this card exists to end.
class _ConnectedCard extends StatelessWidget {
  const _ConnectedCard({
    required this.name,
    required this.bpm,
    required this.status,
    required this.onForget,
  });

  final String name;
  final int? bpm;
  final HeartRateConnectionStatus status;
  final VoidCallback onForget;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final live = status == HeartRateConnectionStatus.connected;
    final busy = status == HeartRateConnectionStatus.reconnecting ||
        status == HeartRateConnectionStatus.connecting;
    final success = live
        ? palette.success
        : busy
            ? palette.accent(_kDeviceHue)
            : palette.muted;

    final label = switch (status) {
      HeartRateConnectionStatus.connected => 'CONNECTED',
      HeartRateConnectionStatus.connecting => 'CONNECTING',
      HeartRateConnectionStatus.reconnecting => 'RECONNECTING',
      HeartRateConnectionStatus.adapterOff => 'BLUETOOTH OFF',
      HeartRateConnectionStatus.failed => 'NOT CONNECTED',
      _ => 'REMEMBERED',
    };

    return DarkCard(
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                success.withValues(alpha: palette.isDark ? 0.18 : 0.10),
                palette.surface,
              ),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              live
                  ? Icons.bluetooth_connected_rounded
                  : busy
                      ? Icons.bluetooth_searching_rounded
                      : Icons.bluetooth_disabled_rounded,
              color: success,
              size: 21,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // The dot breathes only while readings are actually
                    // arriving. A reconnecting strap that still pulsed would be
                    // making the same promise a frozen BPM used to.
                    if (live)
                      _Pulse(
                        child: Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: success,
                            shape: BoxShape.circle,
                          ),
                        ),
                      )
                    else
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: success,
                          shape: BoxShape.circle,
                        ),
                      ),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: TextStyle(
                        color: success,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (bpm != null) ...[
            const SizedBox(width: AppSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '$bpm',
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
                const SizedBox(width: 3),
                Text(
                  'bpm',
                  style: TextStyle(
                    color: palette.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
          // Pairing survives a relaunch now, so there has to be a way out of it.
          IconButton(
            tooltip: 'Forget this device',
            onPressed: onForget,
            icon: Icon(Icons.link_off_rounded, size: 19, color: palette.muted),
          ),
        ],
      ),
    );
  }
}

/// One result from the scan.
class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.device,
    required this.isConnecting,
    required this.onConnect,
  });

  final DiscoveredHeartRateDevice device;
  final bool isConnecting;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette.accentFill(_kDeviceHue),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              Icons.watch_rounded,
              color: palette.accent(_kDeviceHue),
              size: 21,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    _SignalBars(rssi: device.rssi),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        '${device.rssi} dBm · ${device.remoteId}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: palette.muted, fontSize: 11.5),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: palette.brandSoft,
              foregroundColor: palette.brandText,
              elevation: 0,
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: palette.brandSoftStroke),
              ),
            ),
            onPressed: isConnecting ? null : onConnect,
            child: Text(isConnecting ? '…' : 'Connect'),
          ),
        ],
      ),
    );
  }
}

/// Four rising bars for how strong a scan result is.
///
/// A raw `-71 dBm` is precise and means nothing to most people; the bars say
/// "this one is in the room and that one is through a wall", which is the only
/// thing the number is being read for. The figure stays beside them for anybody
/// who does want it.
class _SignalBars extends StatelessWidget {
  const _SignalBars({required this.rssi});

  final int rssi;

  /// Roughly -100 dBm (out of range) to -40 (in your hand), mapped onto four
  /// steps and floored at one so a listed device never shows as nothing.
  int get _filled => (((rssi + 100) / 60).clamp(0.0, 1.0) * 4).ceil().clamp(1, 4);

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final lit = palette.accent(_kDeviceHue);

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < 4; i++) ...[
          if (i > 0) const SizedBox(width: 2.5),
          Container(
            width: 3,
            height: 4.0 + i * 3,
            decoration: BoxDecoration(
              color: i < _filled ? lit : palette.stroke,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ],
    );
  }
}

/// Per-type readout of what Health Connect is actually handing over.
///
/// The four metrics above collapse every failure into a dash: a type the user
/// never granted, a type the watch does not write, and a read that threw all
/// look identical. That is the right amount of detail for somebody checking
/// their steps and the wrong amount for working out why their watch is only
/// supplying some of them. This card is the difference, and it is the first
/// thing to open when a newly paired watch shows blanks.
///
/// Not gated behind a debug flag on purpose. The phone with the watch paired to
/// it is frequently running a release build, and a panel that hides exactly
/// where it is needed is not a diagnostic. Collapsed by default, so it costs a
/// line of screen to somebody who does not need it.
class _DiagnosticsCard extends ConsumerStatefulWidget {
  const _DiagnosticsCard();

  @override
  ConsumerState<_DiagnosticsCard> createState() => _DiagnosticsCardState();
}

class _DiagnosticsCardState extends ConsumerState<_DiagnosticsCard> {
  bool _expanded = false;
  bool _requesting = false;

  static String _label(HealthDataType type) {
    final words = type.name.toLowerCase().replaceAll('_', ' ');
    return words[0].toUpperCase() + words.substring(1);
  }

  static String _stamp(DateTime t) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final l = t.toLocal();
    final hh = l.hour.toString().padLeft(2, '0');
    final mm = l.minute.toString().padLeft(2, '0');
    return '${months[l.month - 1]} ${l.day}, $hh:$mm';
  }

  /// Plain-text version of the same rows, for pasting into a bug report.
  static String _report(List<HealthTypeDiagnostic> rows) {
    final buffer = StringBuffer('FitSocial health diagnostics\n')
      ..writeln('Probed ${_stamp(DateTime.now())} over the last 7 days')
      ..writeln();
    for (final row in rows) {
      buffer.write('${_label(row.type)}: ${row.verdict}');
      if (row.sources.isNotEmpty) {
        buffer.write(' | sources: ${row.sources.join(', ')}');
      }
      if (row.latest != null) {
        buffer.write(' | latest: ${_stamp(row.latest!)}');
      }
      if (row.error != null) buffer.write(' | error: ${row.error}');
      buffer.writeln();
    }
    return buffer.toString();
  }

  Future<void> _grant() async {
    setState(() => _requesting = true);
    final granted =
        await ref.read(healthServiceProvider).requestDiagnosticPermissions();
    if (!mounted) return;
    setState(() => _requesting = false);
    ref.invalidate(healthDiagnosticsProvider);
    // Refreshed too: a permission just granted changes what the metrics above
    // can show, and leaving them stale would contradict the rows below.
    ref.invalidate(healthSummaryProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          granted
              ? 'Permissions granted. Re-probing.'
              : 'Some permissions were not granted. Health Connect > App '
                  'permissions > FitSocial lets you change them per type.',
        ),
      ),
    );
  }

  Future<void> _copy(List<HealthTypeDiagnostic> rows) async {
    await Clipboard.setData(ClipboardData(text: _report(rows)));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Diagnostics copied.')));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final diagnostics = _expanded ? ref.watch(healthDiagnosticsProvider) : null;

    return DarkCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: palette.accentFill(_kDeviceHue),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    Icons.troubleshoot_rounded,
                    color: palette.accent(_kDeviceHue),
                    size: 21,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Diagnostics',
                        style: TextStyle(
                          color: palette.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        diagnostics?.when(
                              loading: () => 'Probing Health Connect…',
                              error: (e, _) => 'Probe failed',
                              data: (rows) {
                                final live =
                                    rows.where((r) => r.isHealthy).length;
                                return '$live of ${rows.length} data types '
                                    'returning data';
                              },
                            ) ??
                            'See what your watch is actually providing',
                        style: TextStyle(
                          color: palette.muted,
                          fontSize: 12.5,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: Icon(
                    Icons.expand_more_rounded,
                    color: palette.muted,
                  ),
                ),
              ],
            ),
          ),
          if (_expanded) ...[
            const SizedBox(height: AppSpacing.md),
            Divider(height: 1, thickness: 1, color: palette.stroke),
            const SizedBox(height: AppSpacing.md),
            Text(
              'What each type has written to Health Connect over the last 7 '
              'days, and which app wrote it.',
              style: TextStyle(
                color: palette.muted,
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            diagnostics!.when(
              loading: () => Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: palette.brand,
                    ),
                  ),
                ),
              ),
              error: (e, _) => Text(
                'Could not probe: $e',
                style: TextStyle(color: palette.danger, fontSize: 13),
              ),
              data: (rows) => Column(
                children: [
                  ...rows.map(_DiagnosticRow.new),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: _MiniAction(
                          icon: Icons.lock_open_rounded,
                          label: _requesting ? 'Asking…' : 'Grant all',
                          onTap: _requesting ? null : _grant,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: _MiniAction(
                          icon: Icons.refresh_rounded,
                          label: 'Re-probe',
                          onTap: () =>
                              ref.invalidate(healthDiagnosticsProvider),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: _MiniAction(
                          icon: Icons.copy_rounded,
                          label: 'Copy',
                          onTap: () => _copy(rows),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One of the three buttons along the bottom of the diagnostics panel.
///
/// A chip rather than a [TextButton]: three text buttons in a row read as a
/// dialog's actions, and these act on the panel above them rather than
/// dismissing anything.
class _MiniAction extends StatelessWidget {
  const _MiniAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;

  /// Null greys the chip out — used while a permission request is in flight.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final enabled = onTap != null;
    final foreground = enabled ? palette.brandText : palette.muted;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: palette.overlay
                .withValues(alpha: palette.isDark ? 0.06 : 0.035),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: palette.stroke),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: foreground),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
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

class _DiagnosticRow extends StatelessWidget {
  const _DiagnosticRow(this.row);

  final HealthTypeDiagnostic row;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    // Three states worth telling apart at a glance: data arriving, something
    // blocking it, and access fine but nothing being written. The last is the
    // common one for a budget watch and is not an error, so it stays neutral.
    final Color colour;
    final IconData icon;
    if (row.isHealthy) {
      colour = palette.success;
      icon = Icons.check_circle_rounded;
    } else if (row.error != null || row.granted == false || !row.supported) {
      colour = palette.danger;
      icon = Icons.error_outline_rounded;
    } else {
      colour = palette.muted;
      icon = Icons.remove_circle_outline_rounded;
    }

    final detail = <String>[
      if (row.sources.isNotEmpty) row.sources.join(', '),
      if (row.latest != null)
        'latest ${_DiagnosticsCardState._stamp(row.latest!)}',
      if (row.error != null) row.error!,
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 16, color: colour),
          ),
          const SizedBox(width: AppSpacing.sm + 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(
                        _DiagnosticsCardState._label(row.type),
                        style: TextStyle(
                          color: palette.text,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    // The verdict as a pill, so a column of them scans as a
                    // status list rather than a second column of prose.
                    //
                    // Flexible and capped at two lines because the verdicts are
                    // sentences, not words: "not supported on this platform"
                    // would otherwise take the width it wants and leave the
                    // type name squeezed into what was left.
                    Flexible(
                      flex: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Color.alphaBlend(
                            colour.withValues(
                              alpha: palette.isDark ? 0.16 : 0.10,
                            ),
                            palette.surface,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          row.verdict,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                          style: TextStyle(
                            color: colour,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (detail.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      detail,
                      style: TextStyle(
                        color: palette.muted,
                        fontSize: 11.5,
                        height: 1.35,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
