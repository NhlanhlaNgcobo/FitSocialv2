import 'package:flutter/material.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/primary_button.dart';

/// The chrome a live run session is made of — status pill, metric row, controls
/// and banners.
///
/// Shared by the GPS screen and the treadmill screen so the two read as the
/// same activity recorded two ways. A runner who has used one should recognise
/// every control on the other; the only difference between them is where the
/// numbers come from.

/// Soft radial orange behind the top of a run page. Barely there when idle, and
/// it lifts while the run is live — the only cue on the screen that doesn't
/// cost a pixel of layout.
class AmbientRunGlow extends StatelessWidget {
  const AmbientRunGlow({required this.active, super.key});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -0.85),
              radius: 1.1,
              colors: [
                context.palette.brand.withValues(alpha: active ? 0.16 : 0.05),
                Colors.transparent,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// LIVE / PAUSED / READY, in the tone that matches.
///
/// [accent] lights the pill in brand orange — the run is either live or held by
/// something the app decided. [pulsing] is reserved for "counting right now", so
/// a glance from arm's length tells you whether the clock is still moving.
class RunStatusPill extends StatelessWidget {
  const RunStatusPill({
    required this.label,
    required this.accent,
    required this.pulsing,
    super.key,
  });

  final String label;
  final bool accent;
  final bool pulsing;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = accent ? palette.brandText : palette.muted;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 14, 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PulseDot(color: color, active: pulsing),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// A dot that breathes while [active]. Owns its own controller so the ticker
/// only runs on the frames that actually need it.
class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.color, required this.active});

  final Color color;
  final bool active;

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_PulseDot old) {
    super.didUpdateWidget(old);
    if (widget.active == old.active) return;
    if (widget.active) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.55 * t),
                blurRadius: 4 + 6 * t,
                spreadRadius: 1 + 3 * t,
              ),
            ],
          ),
        );
      },
    );
  }
}

class RunMetricRule extends StatelessWidget {
  const RunMetricRule({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 42, color: context.palette.stroke);
  }
}

/// One of the supporting numbers under a run hero.
class RunMetric extends StatelessWidget {
  const RunMetric({
    required this.icon,
    required this.label,
    required this.value,
    this.accent = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final valueColor = accent ? palette.brandText : palette.text;

    return Column(
      children: [
        Icon(icon, size: 14, color: accent ? valueColor : palette.muted),
        const SizedBox(height: 6),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w800,
            color: valueColor,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: palette.muted,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}

/// The card every run session is built around: a status pill, one enormous
/// headline number, and the supporting metrics under a rule.
///
/// What the headline *is* differs by mode — distance on GPS, the clock on a
/// treadmill — so the caller supplies it; everything around it is fixed.
class RunHeroCard extends StatelessWidget {
  const RunHeroCard({
    required this.statusLabel,
    required this.statusAccent,
    required this.isRunning,
    required this.headlineValue,
    required this.headlineUnit,
    required this.metrics,
    super.key,
  });

  final String statusLabel;
  final bool statusAccent;

  /// Counting right now: lights the card's border and glow.
  final bool isRunning;

  final String headlineValue;

  /// Null for a headline that carries its own unit — a clock reads as time
  /// without anything after it, and `12:34 MIN` would be wrong anyway.
  final String? headlineUnit;

  /// Laid out evenly with a hairline between each pair.
  final List<RunMetric> metrics;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg - 4,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.surface, palette.surfaceHigh],
        ),
        border: Border.all(
          color: isRunning
              ? palette.brand.withValues(alpha: 0.35)
              : palette.stroke,
        ),
        boxShadow: [
          BoxShadow(
            color: isRunning
                ? palette.brand.withValues(alpha: 0.18)
                : palette.navShadow,
            blurRadius: 26,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          RunStatusPill(
            label: statusLabel,
            accent: statusAccent,
            pulsing: isRunning,
          ),
          const SizedBox(height: AppSpacing.lg),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  headlineValue,
                  style: TextStyle(
                    fontSize: 76,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -2,
                    color: palette.text,
                    // Fixed-width digits: without them the whole number
                    // shuffles sideways every time a digit ticks over.
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (headlineUnit != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    headlineUnit!,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                      color: palette.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Container(height: 1, color: palette.stroke),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              for (var i = 0; i < metrics.length; i++) ...[
                if (i > 0) const RunMetricRule(),
                Expanded(child: metrics[i]),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// [PrimaryButton] with the brand glow the run-log hero card uses, dropped
/// while the button is disabled so a dead control doesn't look lit.
class RunGlowButton extends StatelessWidget {
  const RunGlowButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: context.palette.brand
                .withValues(alpha: onPressed == null ? 0 : 0.32),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: PrimaryButton(label: label, icon: icon, onPressed: onPressed),
    );
  }
}

/// The secondary mid-run control: same height as the primary bar beside it, so
/// the pair reads as one row rather than two stacked ideas.
class RunCircleControl extends StatelessWidget {
  const RunCircleControl({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: Material(
          color: palette.surfaceHigh,
          shape: CircleBorder(side: BorderSide(color: palette.stroke)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: 56,
              height: 56,
              child: Icon(icon, size: 26, color: palette.text),
            ),
          ),
        ),
      ),
    );
  }
}

/// Start, or pause-and-finish. Pause is the quiet circle and Finish is the lit
/// bar, so the two mid-run controls can't be confused for one another at a
/// glance the way two identical orange buttons could.
class RunControls extends StatelessWidget {
  const RunControls({
    required this.isTracking,
    required this.isPaused,
    required this.isSaving,
    required this.startLabel,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onFinish,
    super.key,
  });

  final bool isTracking;
  final bool isPaused;
  final bool isSaving;

  /// 'Start GPS Run', 'Start Treadmill Run' — the one word of copy that says
  /// which kind of run this screen records.
  final String startLabel;

  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    if (!isTracking) {
      return RunGlowButton(
        label: startLabel,
        icon: Icons.play_arrow_rounded,
        onPressed: onStart,
      );
    }

    return Row(
      children: [
        RunCircleControl(
          icon: isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
          tooltip: isPaused ? 'Resume' : 'Pause',
          onTap: isPaused ? onResume : onPause,
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: RunGlowButton(
            label: isSaving ? 'Saving...' : 'Finish',
            icon: isSaving ? null : Icons.stop_rounded,
            onPressed: isSaving ? null : onFinish,
          ),
        ),
      ],
    );
  }
}

enum RunBannerTone { brand, danger }

class RunBanner extends StatelessWidget {
  const RunBanner({
    required this.icon,
    required this.message,
    required this.tone,
    super.key,
  });

  final IconData icon;
  final String message;
  final RunBannerTone tone;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = switch (tone) {
      RunBannerTone.brand => palette.brandText,
      RunBannerTone.danger => palette.danger,
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Heart-rate shortcut in the app bar. Reads as a lit chip once a strap is
/// connected, and as a plain glyph when there is nothing to show.
class RunHeartRateAction extends StatelessWidget {
  const RunHeartRateAction({
    required this.bpm,
    required this.onPressed,
    this.isReconnecting = false,
    super.key,
  });

  final int? bpm;
  final VoidCallback onPressed;

  /// A remembered strap being reached for. Rendered differently from "no
  /// strap": one is worth waiting on, the other needs the runner to go and
  /// pair something.
  final bool isReconnecting;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isLive = bpm != null;

    return Tooltip(
      message: isLive
          ? 'Heart-rate device'
          : isReconnecting
              ? 'Reconnecting to your heart-rate device'
              : 'Connect heart-rate device',
      child: Material(
        color: isLive || isReconnecting
            ? palette.brandSoft
            : Colors.transparent,
        borderRadius: BorderRadius.circular(99),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Icon(
              isLive
                  ? Icons.favorite_rounded
                  : isReconnecting
                      ? Icons.bluetooth_searching_rounded
                      : Icons.monitor_heart_outlined,
              size: 20,
              color: isLive || isReconnecting ? palette.brand : palette.text,
            ),
          ),
        ),
      ),
    );
  }
}
