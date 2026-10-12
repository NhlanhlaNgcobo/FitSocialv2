import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_palette.dart';
import '../../app/theme/app_spacing.dart';
import '../../features/main/domain/app_models.dart';
import 'run_map_style_sheet.dart';
import 'run_route_geometry.dart';
import 'run_route_map.dart';

/// Opens a finished run full screen and plays it back: the route draws itself
/// from the start with the camera riding its leading end, then pulls out to
/// the whole thing.
Future<void> openRunReplay(BuildContext context, List<RoutePoint> route) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => RunReplayScreen(route: route),
    ),
  );
}

class RunReplayScreen extends StatefulWidget {
  const RunReplayScreen({required this.route, super.key});

  final List<RoutePoint> route;

  /// Whether [route] has enough in it to replay — the condition for offering
  /// the button at all.
  static bool canReplay(List<RoutePoint> route) => route.length >= 2;

  @override
  State<RunReplayScreen> createState() => _RunReplayScreenState();
}

class _RunReplayScreenState extends State<RunReplayScreen>
    with SingleTickerProviderStateMixin {
  late final List<LatLng> _route = [
    for (final point in widget.route) LatLng(point.latitude, point.longitude),
  ];
  late final List<double>? _seconds = RoutePoint.secondsOf(widget.route);
  late final double _totalMeters = _measure(_route);

  late final AnimationController _playback = AnimationController(
    vsync: this,
    // Long enough to follow, short enough to watch to the end: about a second
    // per kilometre, between eight seconds and twenty.
    duration: Duration(
      milliseconds: (_totalMeters).clamp(8000, 20000).round(),
    ),
  )..addListener(_onTick);

  /// What the map is drawing. Moved on at most twenty times a second: every
  /// change sends the route across to the platform map, and sixty of those a
  /// second would choke it for no smoother a picture.
  double _shown = 0;
  DateTime _lastPush = DateTime.fromMillisecondsSinceEpoch(0);

  static double _measure(List<LatLng> route) {
    var total = 0.0;
    for (var i = 1; i < route.length; i++) {
      total += distanceMeters(route[i - 1], route[i]);
    }
    return total;
  }

  @override
  void initState() {
    super.initState();
    // A beat on the start before it sets off, so the eye finds the pin.
    Future<void>.delayed(const Duration(milliseconds: 700), () {
      if (mounted) _playback.forward();
    });
  }

  void _onTick() {
    final now = DateTime.now();
    final done = _playback.value >= 1;
    if (!done && now.difference(_lastPush).inMilliseconds < 50) return;
    _lastPush = now;
    setState(() => _shown = _playback.value);
  }

  void _togglePlay() {
    if (_playback.isAnimating) {
      _playback.stop();
    } else if (_playback.value >= 1) {
      _playback.forward(from: 0);
    } else {
      _playback.forward();
    }
    setState(() {});
  }

  @override
  void dispose() {
    _playback.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final viewPadding = MediaQuery.viewPaddingOf(context);
    final playing = _playback.isAnimating;
    final kmNow = _totalMeters * _shown / 1000;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: RunRouteMap(
              route: _route,
              routeSeconds: _seconds,
              mode: RunRouteMapMode.completed,
              replayProgress: _shown,
              height: double.infinity,
              borderRadius: BorderRadius.zero,
              showBadge: false,
              framePadding: 72,
              padding: EdgeInsets.only(
                top: viewPadding.top + 56,
                bottom: viewPadding.bottom + 96,
              ),
            ),
          ),
          Positioned(
            top: viewPadding.top + AppSpacing.sm,
            left: AppSpacing.md,
            right: AppSpacing.md,
            child: Row(
              children: [
                _RoundButton(
                  icon: Icons.close_rounded,
                  tooltip: 'Close',
                  onTap: () => Navigator.of(context).pop(),
                ),
                const Spacer(),
                const RunMapStyleButton(size: 44, iconSize: 20),
              ],
            ),
          ),
          Positioned(
            left: AppSpacing.md,
            right: AppSpacing.md,
            bottom: viewPadding.bottom + AppSpacing.md,
            child: RunMapPlate(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
              borderRadius: const BorderRadius.all(Radius.circular(36)),
              child: Row(
                children: [
                  _RoundButton(
                    icon: playing
                        ? Icons.pause_rounded
                        : (_shown >= 1
                            ? Icons.replay_rounded
                            : Icons.play_arrow_rounded),
                    tooltip: playing ? 'Pause' : 'Play',
                    filled: true,
                    onTap: _togglePlay,
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: AppColors.orangeBright,
                        inactiveTrackColor: palette.stroke,
                        thumbColor: AppColors.orangeBright,
                        overlayColor:
                            AppColors.orangeBright.withValues(alpha: 0.15),
                        trackHeight: 3,
                      ),
                      child: Slider(
                        value: _shown.clamp(0.0, 1.0),
                        onChanged: (value) {
                          _playback.stop();
                          _playback.value = value;
                          setState(() => _shown = value);
                        },
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 64,
                    child: Text(
                      '${kmNow.toStringAsFixed(2)} km',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: palette.text,
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  /// Solid brand orange — the play control — rather than the map plate.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: filled ? AppColors.orangeBright : RunMapPlate.fill(context),
        shape: CircleBorder(
          side: filled
              ? BorderSide.none
              : BorderSide(color: palette.stroke.withValues(alpha: 0.6)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              icon,
              size: 24,
              color: filled ? AppColors.onBrand : palette.text,
            ),
          ),
        ),
      ),
    );
  }
}
