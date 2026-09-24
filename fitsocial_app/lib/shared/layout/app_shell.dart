import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_palette.dart';
import '../../features/challenges/application/daily_steps_sync.dart';
import '../../features/tracking/application/run_import_sync.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/offline_banner.dart';
import 'nav_visibility.dart';
import 'tab_reselect.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  /// Home's place in the nav bar.
  static const int _homeIndex = 0;

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
    final reselected = index == widget.navigationShell.currentIndex;
    // Home tapped while already on Home: the feed scrolls back to the top and
    // refreshes. From any other tab, Home only switches back to it.
    if (reselected && index == _homeIndex) {
      ref.read(homeTabReselectProvider.notifier).state++;
    }
    widget.navigationShell.goBranch(index, initialLocation: reselected);
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
              // Published to the branch below so a screen's own top bar can
              // leave through the top edge on the same scroll that sends the
              // nav out through the bottom. The listener has to stay outside
              // it: the scope is what reads the signal, not what produces it.
              child: NavVisibilityScope(
                hidden: _visibility.hidden,
                child: widget.navigationShell,
              ),
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
