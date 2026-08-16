import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_palette.dart';
import '../application/music_island_controller.dart';
import '../application/music_presence_provider.dart';
import '../domain/music_brand.dart';
import 'music_mini_player.dart';

/// The music island, as the first item in a top bar's actions.
///
/// A slot rather than a floating overlay. The earlier version positioned itself
/// over the page and had to be told which routes to keep off and which text to
/// avoid; putting it in the actions row makes the placement a fact of each
/// screen's own layout instead of a rule maintained somewhere else. Every
/// action in this app is right-aligned, so being first here means being the
/// leftmost of that cluster on every screen.
///
/// Occupies nothing at all when there is no track — the row closes up, and the
/// other actions sit where they always did.
class MusicIslandAction extends ConsumerStatefulWidget {
  const MusicIslandAction({super.key});

  /// Wider than an icon button, because the island is a pill rather than a
  /// glyph. The height still matches the actions beside it so the row stays
  /// level.
  static const double slotWidth = 56;
  static const double slotHeight = 48;

  @override
  ConsumerState<MusicIslandAction> createState() => _MusicIslandActionState();
}

class _MusicIslandActionState extends ConsumerState<MusicIslandAction>
    with SingleTickerProviderStateMixin {
  /// Drives the panel open and shut.
  ///
  /// Out is slower than back: an opening panel is showing you something new and
  /// wants to be followed, while a closing one is getting out of the way and
  /// should not be waited on.
  ///
  /// Built in [initState] rather than lazily. A `late final` here is a trap:
  /// on a screen where the panel is never opened, nothing touches it until
  /// `dispose` calls it — and constructing a ticker against an element that is
  /// already deactivated throws.
  late final AnimationController _motion;

  /// Eased rather than linear, and expressed with `drive` so no
  /// CurvedAnimation object needs owning and disposing.
  static final CurveTween _eased = CurveTween(curve: Curves.easeOutCubic);

  late final Animation<double> _fade = _motion.drive(_eased);

  late final Animation<double> _scale =
      _motion.drive(Tween<double>(begin: 0.92, end: 1).chain(_eased));

  /// A short drop, so the card reads as coming down out of the bar rather than
  /// appearing in place.
  late final Animation<Offset> _slide = _motion.drive(
    Tween<Offset>(begin: const Offset(0, -0.04), end: Offset.zero).chain(_eased),
  );

  /// Owns only the idle timeout. The expanded card is an [OverlayEntry], whose
  /// lifetime is this State's — navigating away disposes it, which is exactly
  /// what should happen to a panel belonging to a bar that is going away.
  late final MusicIslandController _island = MusicIslandController()
    ..addListener(_onExpansionChanged);

  OverlayEntry? _entry;

  /// Where the bottom of this slot was when the panel opened.
  ///
  /// Measured rather than assumed: the island sits in a standard app bar on
  /// most screens but in the profile's own action row on one, and those are
  /// different heights. Reading the slot's own box covers both without a
  /// per-screen constant.
  double _anchorBottom = kToolbarHeight;

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      reverseDuration: const Duration(milliseconds: 180),
    );
  }

  @override
  void dispose() {
    _removeEntry();
    _motion.dispose();
    _island
      ..removeListener(_onExpansionChanged)
      ..dispose();
    super.dispose();
  }

  void _onExpansionChanged() {
    if (_island.isExpanded) {
      _insertEntry();
      _motion.forward();
      return;
    }
    if (_entry == null) return;

    // The entry has to outlive the request to close it, or the card would
    // vanish on the first frame and there would be nothing left to animate.
    _motion.reverse().whenComplete(() {
      // Re-opened while it was closing: the forward run owns the entry now.
      if (!_island.isExpanded) _removeEntry();
    });
  }

  void _insertEntry() {
    if (_entry != null) return;
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    final box = context.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      _anchorBottom = box.localToGlobal(Offset.zero).dy + box.size.height;
    }

    _entry = OverlayEntry(builder: _buildExpanded);
    overlay.insert(_entry!);
  }

  void _removeEntry() {
    _entry?.remove();
    _entry = null;
  }

  Widget _buildExpanded(BuildContext context) {
    return Stack(
      children: [
        // A barrier, the way a dropdown has one: a tap anywhere else closes
        // the panel, and it stops a scroll sliding the page out from under a
        // card that is pinned to where the bar was.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _island.collapse,
          ),
        ),
        Positioned(
          top: _anchorBottom + 6,
          left: 0,
          right: 0,
          // Centred on the screen rather than hung off the slot. The slot sits
          // in the right-hand action cluster, and a 380dp card anchored to it
          // would run off the edge — the controls belong in the middle where
          // there is room for them.
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Material(
                  color: Colors.transparent,
                  child: Listener(
                    // Observes rather than intercepts, so the mini player's own
                    // buttons still get the gesture. Any touch in here is
                    // someone still using it, so the clock restarts.
                    behavior: HitTestBehavior.translucent,
                    onPointerDown: (_) => _island.keepAlive(),
                    child: FadeTransition(
                      opacity: _fade,
                      child: SlideTransition(
                        position: _slide,
                        child: ScaleTransition(
                          // Grown from the top right, which is the corner the
                          // pill sits in — the card reads as coming out of the
                          // island rather than swelling from its own middle.
                          alignment: Alignment.topRight,
                          scale: _scale,
                          child: const _ExpandedCard(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final presence = ref.watch(musicPresenceProvider);

    // Not playing — paused included — means the slot takes no space at all, so
    // the row looks exactly as it did before music was involved. Not a
    // disabled button: no button.
    if (!presence.isLive) {
      // Music stopping is not a dismissal to animate — the thing the panel
      // controls is gone, so it goes with it.
      _removeEntry();
      // Rewinding the controller notifies its listeners, and doing that from
      // inside build marks the overlay dirty mid-build. It has nothing left to
      // drive now the entry is gone, so it can be reset a frame later.
      if (_motion.value != 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _motion.stop();
          _motion.value = 0;
        });
      }
      return const SizedBox.shrink();
    }

    final service = presence.service;
    final accent = service == null
        ? context.palette.brand
        : MusicBrand.of(service).accent;

    return Semantics(
      button: true,
      // The pill carries no text, so this is the only thing naming the track
      // to a screen reader.
      label: presence.isPlaying
          ? 'Now playing: ${presence.title}'
          : 'Paused: ${presence.title}',
      child: SizedBox(
        width: MusicIslandAction.slotWidth,
        height: MusicIslandAction.slotHeight,
        child: GestureDetector(
          onTap: _island.toggle,
          behavior: HitTestBehavior.opaque,
          child: Center(child: _Pill(accent: accent)),
        ),
      ),
    );
  }
}

/// The collapsed island: a pill with the music mark in the middle of it.
///
/// Has no paused state to draw. The island is only ever built while something
/// is playing, so the mark is always the live colour.
class _Pill extends StatelessWidget {
  const _Pill({required this.accent});

  static const double _width = 46;
  static const double _height = 28;

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _width,
      height: _height,
      decoration: BoxDecoration(
        // Near-black in both themes: the island reads as its own object in the
        // bar rather than as another glyph in the row.
        color: const Color(0xF21A1A1A),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Center(
        child: Icon(Icons.music_note_rounded, size: 17, color: accent),
      ),
    );
  }
}

/// The controls, in a card that reads as belonging to the bar above it.
class _ExpandedCard extends StatelessWidget {
  const _ExpandedCard();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x59000000),
            blurRadius: 22,
            offset: Offset(0, 8),
          ),
        ],
      ),
      // No onBrowse override needed: inside a top bar this widget has a
      // Navigator above it, so the library sheet opens on its own context.
      child: const MusicMiniPlayer(),
    );
  }
}
