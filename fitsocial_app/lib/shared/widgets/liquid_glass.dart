import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../app/theme/app_palette.dart';
import 'glass.dart';
import 'glass_motion.dart';

/// The compiled lens, loaded once for the whole app.
///
/// Two things can make liquid glass unavailable, and neither is an error worth
/// showing anyone: the device may be on Skia rather than Impeller, where
/// [ui.ImageFilter.shader] throws outright, or the asset may fail to load. In
/// both cases every glass surface quietly falls back to the frosted path, which
/// is why nothing here rethrows.
class LiquidGlassProgram {
  LiquidGlassProgram._();

  static const String _asset = 'assets/shaders/liquid_glass.frag';

  /// Flips true once the program is compiled and usable. Glass surfaces listen
  /// to it so the first frame after a cold start upgrades itself rather than
  /// staying frosted until something else happens to rebuild.
  static final ValueNotifier<bool> ready = ValueNotifier<bool>(false);

  static ui.FragmentProgram? _program;
  static Future<void>? _loading;

  /// Whether the rendering backend can run a shader as an image filter at all.
  /// False on Skia, and on every platform the engine has not enabled Impeller.
  static bool get supported => ui.ImageFilter.isShaderFilterSupported;

  static ui.FragmentProgram? get program => _program;

  /// Called once at startup. Safe to call again; the same future is returned.
  static Future<void> warmUp() {
    if (!supported) return Future<void>.value();
    return _loading ??= _load();
  }

  static Future<void> _load() async {
    try {
      _program = await ui.FragmentProgram.fromAsset(_asset);
      ready.value = true;
    } catch (error, stack) {
      _program = null;
      // Reported, not rethrown: a missing lens costs the app its finish, not
      // its function.
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'fitsocial',
          context: ErrorDescription('loading the liquid glass shader'),
        ),
      );
    }
  }

  @visibleForTesting
  static void resetForTest() {
    _program = null;
    _loading = null;
    ready.value = false;
  }
}

/// A pane of liquid glass: the backdrop behind it, bent.
///
/// This is the real thing rather than a blur — see `liquid_glass.frag`. What it
/// needs in exchange is something *behind* it worth bending. Over a flat colour
/// a lens has nothing to displace and renders as an empty outline, which is why
/// the shell paints a [LiquidBackdrop] under everything this sits on.
///
/// Falls back to the frosted [GlassPane] wherever the shader cannot run, so a
/// Skia device gets the old finish rather than a broken one.
class LiquidGlass extends StatefulWidget {
  const LiquidGlass({
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
    this.refraction = 24,
    this.edge = 22,
    this.aberration = 0.55,
    this.light = const Offset(-0.55, -0.78),
    this.clip = true,
    this.tintScale = 1,
    this.lens = false,
    super.key,
  });

  final Widget child;

  /// Shape of the pane. The shader builds its distance field from all four
  /// corners, so this has to match whatever clips the widget or the rim lands
  /// wrong — and it is why a bottom sheet, round on top and square where it
  /// meets the screen edge, is the same material as a card.
  final BorderRadius borderRadius;

  /// How far the rim drags the backdrop inward, in logical pixels.
  final double refraction;

  /// How deep into the pane the bend reaches before the glass goes flat.
  final double edge;

  /// Per-channel spread at the lens edge, 0 to 1.
  final double aberration;

  /// Where the light comes from, in the pane's own space with y pointing down.
  /// Defaults to above and slightly left, matching the rest of the app's
  /// lighting.
  final Offset light;

  /// Whether to clip to [borderRadius]. Off for a caller that already clips,
  /// since two nested rounded clips cost a saveLayer for nothing.
  final bool clip;

  /// Thins the pane's fill, for a surface that paints its own colour
  /// underneath.
  ///
  /// A card putting a [GlassBloom] behind the glass is *saying* something with
  /// that colour, and a full-strength fill over it defeats the point. The light
  /// theme is where this bites: its fill is 78% white, so a bloom beneath it
  /// arrives at roughly a fifth of the weight it has on dark.
  final double tintScale;

  /// Whether this pane actually reads the backdrop.
  ///
  /// Off by default, and that default is the difference between an app that
  /// holds sixty frames and one that does not.
  ///
  /// A [BackdropFilter] is not a decoration with a price — it is a second
  /// render pass. It breaks the frame in two, reads the finished pixels back,
  /// runs `liquid_glass.frag` and a gaussian over them, and paints the result.
  /// Two panes cost two passes; a feed of thirty cards costs thirty. Nothing
  /// batches them, because each one has to sample everything painted before it.
  ///
  /// What the app gets back for that is *displacement* — the backdrop bent
  /// around the rim — and displacement is only visible where the backdrop has
  /// detail to displace. Over [LiquidBackdrop], three soft radial pools, it has
  /// none: bending a smooth gradient yields the same smooth gradient. Every
  /// ordinary card in this app was paying for a lens aimed at a blank wall.
  ///
  /// So the pane defaults to painting its material by hand — the tint, the
  /// sheen and the rim, exactly what [_held] has always drawn while a screen is
  /// changing. That material is not a downgrade nobody has seen; it is the one
  /// on screen during every transition the app has ever run.
  ///
  /// Turn this on for the surfaces that genuinely have something behind them:
  /// the bottom nav, fixed while the feed scrolls under it, and a modal sheet
  /// over the screen it came from. There the bend is the whole point, and there
  /// is only ever one of them on screen at a time.
  final bool lens;

  /// A gentle softening applied *under* the refraction. Liquid glass wants
  /// almost none — enough to take the aliasing off displaced text, not enough
  /// to fog it.
  static final ui.ImageFilter _underBlur = ui.ImageFilter.blur(
    sigmaX: 3,
    sigmaY: 3,
  );

  /// The light theme's softening, heavier than the dark theme's.
  ///
  /// A light pane is mostly tint, so there is little bend left to see and the
  /// material has to read as *frost* instead. Sigma is the difference between
  /// a pane that looks like clear glass with nothing behind it and one that
  /// looks like glass.
  static final ui.ImageFilter _underBlurLight = ui.ImageFilter.blur(
    sigmaX: 6,
    sigmaY: 6,
  );

  /// What the glass falls back to where the lens cannot run. This is a real
  /// blur and not a tinted fill: frosted is the honest second material, and a
  /// flat capsule is neither.
  ///
  /// Sigma is deliberately moderate — blur cost scales with it, and on the nav
  /// this runs on every scrolled frame.
  static final ui.ImageFilter fallbackBlur = ui.ImageFilter.blur(
    sigmaX: 18,
    sigmaY: 18,
  );

  @override
  State<LiquidGlass> createState() => _LiquidGlassState();
}

class _LiquidGlassState extends State<LiquidGlass> {
  ui.FragmentShader? _shader;
  ui.ImageFilter? _filter;

  /// Whether the app is standing still. A backdrop filter inside a screen
  /// transition has no backdrop to read — see [GlassMotion] — so while one runs
  /// the pane paints itself instead.
  bool _settled = GlassMotion.settled.value;

  /// What the filter currently on hand was built from. The engine can only
  /// reuse a backdrop layer while the filter keeps one identity, so it is
  /// rebuilt when a uniform actually changes and never merely because the
  /// widget rebuilt.
  Object? _builtFrom;

  @override
  void initState() {
    super.initState();
    // A painted pane has nothing to warm up and nothing to hold still for: it
    // does not read the backdrop, so a screen change cannot spoil it. Staying
    // off both notifiers is most of the point -- [GlassMotion] would otherwise
    // rebuild every surface in the app twice per navigation for no visible
    // change.
    if (!widget.lens) return;
    LiquidGlassProgram.ready.addListener(_onProgramReady);
    GlassMotion.settled.addListener(_onMotion);
    LiquidGlassProgram.warmUp();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(LiquidGlass oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Every call site passes a constant, so this is defensive rather than
    // load-bearing -- but a pane that became a lens without subscribing would
    // simply never draw one, which is a bug nobody would think to look for.
    if (widget.lens != oldWidget.lens) {
      if (widget.lens) {
        LiquidGlassProgram.ready.addListener(_onProgramReady);
        GlassMotion.settled.addListener(_onMotion);
        LiquidGlassProgram.warmUp();
        _settled = GlassMotion.settled.value;
      } else {
        LiquidGlassProgram.ready.removeListener(_onProgramReady);
        GlassMotion.settled.removeListener(_onMotion);
      }
    }
    _sync();
  }

  @override
  void dispose() {
    // Unconditional: removing a listener that was never added is a no-op, and
    // this way a pane that changed its mind about being a lens still lets go.
    LiquidGlassProgram.ready.removeListener(_onProgramReady);
    GlassMotion.settled.removeListener(_onMotion);
    _shader?.dispose();
    super.dispose();
  }

  void _onProgramReady() {
    if (mounted) setState(_sync);
  }

  /// Twice per screen change, and never per frame: the flag is a bool, so the
  /// pane rebuilds when the filter goes away and when it comes back, not while
  /// the transition runs.
  void _onMotion() {
    final settled = GlassMotion.settled.value;
    if (settled == _settled || !mounted) return;
    setState(() => _settled = settled);
  }

  void _sync() {
    // Never allocate a `FragmentShader` for a pane that will not sample
    // anything. One per instance is cheap; one per card in a feed is not.
    if (!widget.lens) return;

    final program = LiquidGlassProgram.program;
    if (program == null) return;

    final palette = context.palette;
    final tint = palette.liquidTint;

    // Which way the light goes. White on dark, near-black on light — the rim
    // and the specular are mixed toward this, so handing over the theme's own
    // rim colour is what makes one shader draw a lit edge on near-black and a
    // dark hairline on cream.
    final rim = palette.glassRimHigh;

    // Dialled back on light, where the rim now carries the edge and a
    // full-strength specular would only smear across a pane that is already
    // white.
    final sheen = palette.isDark ? 1.0 : 0.35;

    // A light pane is mostly tint, so most of the bend is hidden under the fill
    // and the work is wasted. What is left reads at the rim, which is where it
    // was doing the useful part anyway.
    final refraction = widget.refraction * (palette.isDark ? 1.0 : 0.6);

    final signature = Object.hash(
      widget.borderRadius,
      refraction,
      widget.edge,
      widget.aberration,
      widget.light,
      tint,
      Object.hash(rim, sheen, palette.isDark, widget.tintScale),
    );
    if (signature == _builtFrom && _filter != null) return;

    final shader = _shader ??= program.fragmentShader();

    // Floats 0 and 1 are the bound texture's size, written by the engine. Every
    // index here is offset past them, and they must not be set from Dart.
    final radii = widget.borderRadius;
    shader
      ..setFloat(2, radii.topLeft.x)
      ..setFloat(3, radii.topRight.x)
      ..setFloat(4, radii.bottomRight.x)
      ..setFloat(5, radii.bottomLeft.x)
      ..setFloat(6, refraction)
      ..setFloat(7, widget.edge)
      ..setFloat(8, widget.aberration)
      ..setFloat(9, widget.light.dx)
      ..setFloat(10, widget.light.dy)
      ..setFloat(11, tint.a * widget.tintScale)
      ..setFloat(12, tint.r)
      ..setFloat(13, tint.g)
      ..setFloat(14, tint.b)
      ..setFloat(15, sheen)
      // Appended past the originals, so nothing above had to be renumbered.
      ..setFloat(16, rim.r)
      ..setFloat(17, rim.g)
      ..setFloat(18, rim.b);

    _filter = ui.ImageFilter.compose(
      outer: ui.ImageFilter.shader(shader),
      inner:
          palette.isDark ? LiquidGlass._underBlur : LiquidGlass._underBlurLight,
    );
    _builtFrom = signature;
  }

  /// The child, with any form field beneath it told to stop painting a surface
  /// of its own.
  ///
  /// The app's `inputDecorationTheme` fills every input with an opaque
  /// `palette.surface`. That is right for a field standing on the page and
  /// wrong for one inside a lens: `InputBorder.none` removes a field's outline
  /// but not its fill, so the field goes on painting an opaque slab in the
  /// middle of the pane -- a box inside a box, and the one opaque thing on a
  /// surface whose whole point is that it is transparent.
  ///
  /// Only the fill is taken. The outline stays, so a field sitting in a glass
  /// *sheet* -- a comment box, a search bar -- keeps the shape that says it is
  /// a field. A GlassWell, which supplies that outline itself, drops it from
  /// closer in.
  ///
  /// [InputDecorationTheme.of] does not merge, so the ambient data is copied
  /// rather than replaced: a bare `InputDecorationTheme(filled: false)` would
  /// reset padding, borders and hint styling to Material's defaults.
  Widget _content(BuildContext context) {
    return InputDecorationTheme(
      data: InputDecorationTheme.of(context).copyWith(
        filled: false,
        fillColor: Colors.transparent,
      ),
      child: widget.child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final filter = _filter;
    final shape = widget.borderRadius;
    final palette = context.palette;

    // The ordinary case: the material, painted. No second render pass, no
    // backdrop read, nothing for a transition to spoil -- see [LiquidGlass.lens].
    if (!widget.lens) {
      return _shaped(_held(context, palette, shape, frosted: false), shape,
          palette);
    }

    // A screen change is in flight. Nothing that reads the backdrop can work
    // from inside a transition's buffer, so the pane drops its filter and
    // paints the rest of the material by hand until the app stands still.
    if (!_settled) {
      return _shaped(_held(context, palette, shape, frosted: filter == null),
          shape, palette);
    }

    // No lens on this device, or not compiled yet. The frosted pane is the
    // honest fallback: it needs nothing behind it to look deliberate, and it
    // carries the rim the shader would otherwise have drawn.
    if (filter == null) {
      final frosted = CustomPaint(
        // Outside the filter, which changes only with the theme: keeping it out
        // of the filtered subtree spares it the per-frame repaint the blur
        // itself cannot avoid.
        // The rim painter takes a single radius; the top-left corner is the
        // representative one, since the highlight lives along the top edge.
        foregroundPainter: GlassRim(
          radius: shape.topLeft.x,
          highlight: palette.glassRimHigh,
          soft: palette.glassRimSoft,
        ),
        child: BackdropFilter(
          filter: LiquidGlass.fallbackBlur,
          child: Stack(
            children: [
              const Positioned.fill(child: GlassPane()),
              _content(context),
            ],
          ),
        ),
      );
      return _shaped(frosted, shape, palette);
    }

    final glass = BackdropFilter(
      filter: filter,
      child: _content(context),
    );

    return _shaped(glass, shape, palette);
  }

  /// The same material with its filter switched off — everything the live pane
  /// draws except the part that reads the screen behind it.
  ///
  /// Deliberately built from the live pane's own ingredients rather than from
  /// something cheaper that merely looks like glass. What is left out is the
  /// bend and the softening, both of which are about *what is behind* the pane;
  /// the tint, the sheen and the rim are the pane itself, and keeping them
  /// means the surface never changes weight when the filter comes and goes.
  Widget _held(BuildContext context, AppPalette palette, BorderRadius shape,
      {required bool frosted}) {
    final tint = palette.liquidTint;

    return CustomPaint(
      foregroundPainter: GlassRim(
        radius: shape.topLeft.x,
        highlight: palette.glassRimHigh,
        soft: palette.glassRimSoft,
      ),
      child: Stack(
        // Whatever this stands in for has to hand the child the same
        // constraints, or the pane relays out the moment a transition starts.
        // A BackdropFilter is a plain proxy and passes its own through; the
        // frosted path's Stack loosens them, and is matched rather than
        // corrected here so neither device sees the layout move.
        fit: frosted ? StackFit.loose : StackFit.passthrough,
        children: [
          Positioned.fill(
            // The frosted fallback's surface *is* the pane; the lens paints its
            // tint inside the shader, so standing in for it means painting that
            // tint here and nothing heavier.
            child: frosted
                ? const GlassPane()
                : DecoratedBox(
                    decoration: BoxDecoration(
                      color: tint.withValues(alpha: tint.a * widget.tintScale),
                    ),
                    child: const GlassSheen(),
                  ),
          ),
          _content(context),
        ],
      ),
    );
  }

  /// Clips the pane to its own shape, and drops it onto the page.
  ///
  /// Both are skipped for a caller that already clips: it owns the shape, so
  /// casting the shadow is its job too, and a second rounded clip would be a
  /// saveLayer for nothing.
  Widget _shaped(Widget pane, BorderRadius shape, AppPalette palette) {
    if (!widget.clip) return pane;

    final clipped = ClipRRect(borderRadius: shape, child: pane);

    // Only the light theme casts one, and only it pays for one — see
    // [AppPalette.paneShadow].
    final shadow = palette.paneShadow;
    if (shadow.a == 0) return clipped;

    return DecoratedBox(
      // Outside the clip on purpose: a shadow drawn inside ClipRRect would be
      // clipped away by the very shape casting it.
      decoration: BoxDecoration(
        borderRadius: shape,
        boxShadow: [
          BoxShadow(color: shadow, blurRadius: 18, offset: const Offset(0, 6)),
        ],
      ),
      child: clipped,
    );
  }
}
