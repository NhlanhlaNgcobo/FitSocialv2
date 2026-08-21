import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../app/theme/app_palette.dart';
import 'glass.dart';

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

  /// What the filter currently on hand was built from. The engine can only
  /// reuse a backdrop layer while the filter keeps one identity, so it is
  /// rebuilt when a uniform actually changes and never merely because the
  /// widget rebuilt.
  Object? _builtFrom;

  @override
  void initState() {
    super.initState();
    LiquidGlassProgram.ready.addListener(_onProgramReady);
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
    _sync();
  }

  @override
  void dispose() {
    LiquidGlassProgram.ready.removeListener(_onProgramReady);
    _shader?.dispose();
    super.dispose();
  }

  void _onProgramReady() {
    if (mounted) setState(_sync);
  }

  void _sync() {
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

  @override
  Widget build(BuildContext context) {
    final filter = _filter;
    final shape = widget.borderRadius;
    final palette = context.palette;

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
              widget.child,
            ],
          ),
        ),
      );
      return _shaped(frosted, shape, palette);
    }

    final glass = BackdropFilter(
      filter: filter,
      child: widget.child,
    );

    return _shaped(glass, shape, palette);
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
