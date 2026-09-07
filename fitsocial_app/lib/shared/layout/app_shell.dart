import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_palette.dart';
import '../../features/challenges/application/daily_steps_sync.dart';
import '../../features/tracking/application/run_import_sync.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/offline_banner.dart';
import 'nav_visibility.dart';

class AppShell extends StatefulWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  /// Drives whether the nav is on screen, from scroll direction.
  ///
  /// Exposes a notifier rather than calling setState so a scroll rebuilds only
  /// the bar. Holding this in element state would rebuild the whole branch
  /// stack every time the direction changed.
  final NavVisibility _visibility = NavVisibility();

  @override
  void didUpdateWidget(AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A branch change is a new page, so the bar comes back with it.
    if (widget.navigationShell.currentIndex !=
        oldWidget.navigationShell.currentIndex) {
      _visibility.reveal();
    }
  }

  @override
  void dispose() {
    _visibility.dispose();
    super.dispose();
  }

  void _onTap(int index) {
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // The status bar draws over the app's own background, so its icons have
      // to invert with the theme. Nothing set this while the app was dark-only,
      // which meant light mode would have put white glyphs on cream.
      //
      // The `Brightness` names read backwards here on purpose: statusBarIconBrightness
      // is the brightness of the *icons*, while statusBarBrightness (iOS) is the
      // brightness of what sits *behind* them.
      value: palette.isDark
          ? SystemUiOverlayStyle.light.copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: palette.background,
              systemNavigationBarIconBrightness: Brightness.light,
            )
          : SystemUiOverlayStyle.dark.copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: palette.background,
              systemNavigationBarIconBrightness: Brightness.dark,
            ),
      // Both wrappers live here for the same reason: they have to keep working
      // whichever tab the user is sitting on, and this is the one widget alive
      // for all five.
      child: DailyStepsSync(
        child: RunImportSync(child: _buildScaffold()),
      ),
    );
  }

  Widget _buildScaffold() {
    return Scaffold(
      // The floating bar overlays the page instead of displacing it — this is
      // what gives its backdrop filter real content to blur. Scroll views under
      // the shell pad themselves by FitSocialBottomNav.clearance in exchange.
      extendBody: true,
      backgroundColor: Colors.transparent,
      // Catches scrolls from any list under the shell, whichever branch is
      // showing, so no screen has to wire itself up to the nav.
      //
      // The offline strip is a Column rather than an overlay: it must push the
      // page down, not sit on top of a screen's own header.
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: _visibility.handle,
              child: widget.navigationShell,
            ),
          ),
        ],
      ),
      bottomNavigationBar: ValueListenableBuilder<bool>(
        valueListenable: _visibility.hidden,
        builder: (context, hidden, _) => FitSocialBottomNav(
          currentIndex: widget.navigationShell.currentIndex,
          onTap: _onTap,
          hidden: hidden,
        ),
      ),
    );
  }
}
