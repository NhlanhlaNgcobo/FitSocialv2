import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import 'pulse_photo_frame.dart';

/// Framing a photo for a Pulse, the way a story composer does it.
///
/// Pinch to zoom, drag to move. It opens on the whole photo — the shape it was
/// taken in, on a blurred copy of itself — and anything the photo does not
/// reach stays blurred backdrop. Zooming in is a crop the person chooses;
/// nothing is cropped for them.
///
/// The backdrop deliberately does not move with the gesture. It is scenery
/// standing in for the edges of the screen, and sliding it around under a photo
/// being framed reads as two pictures fighting rather than one being placed.
class PulsePhotoEditor extends StatefulWidget {
  const PulsePhotoEditor({required this.image, super.key});

  final ImageProvider image;

  /// The whole photo, visible. Pinching below this would only add blur, so it
  /// is where zooming out stops.
  static const double minScale = 1;

  /// Past this the photo is mush on any phone screen.
  static const double maxScale = 8;

  @override
  State<PulsePhotoEditor> createState() => _PulsePhotoEditorState();
}

class _PulsePhotoEditorState extends State<PulsePhotoEditor> {
  /// The photo's own size and position inside the frame at rest, in frame
  /// coordinates. Null until the image has decoded and been measured.
  Rect? _fitted;

  double _scale = 1;
  Offset _offset = Offset.zero;

  // Where the gesture began, so every update is computed from the start rather
  // than accumulated. Accumulating drifts: each frame's rounding is carried
  // into the next, and a slow pinch ends somewhere the fingers never asked for.
  double _startScale = 1;
  Offset _startOffset = Offset.zero;
  Offset _startFocal = Offset.zero;

  Size _frame = Size.zero;

  @override
  void didUpdateWidget(covariant PulsePhotoEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A different photo is a fresh framing, not a continuation of the last
    // one's zoom.
    if (oldWidget.image != widget.image) {
      _fitted = null;
      _scale = 1;
      _offset = Offset.zero;
    }
  }

  void _onScaleStart(ScaleStartDetails details) {
    _startScale = _scale;
    _startOffset = _offset;
    _startFocal = details.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final fitted = _fitted;
    if (fitted == null) return;

    final scale = (_startScale * details.scale).clamp(
      PulsePhotoEditor.minScale,
      PulsePhotoEditor.maxScale,
    );
    // Whatever sat under the fingers when the gesture began stays under them:
    // the point is pinned in the photo's own space and re-projected at the new
    // scale. With one finger `details.scale` is 1 and this reduces to a drag.
    final focal = details.localFocalPoint;
    final offset = focal - (_startFocal - _startOffset) * (scale / _startScale);

    setState(() {
      _scale = scale;
      _offset = _clamp(offset, scale, fitted);
    });
  }

  /// Keeps the photo honest about the frame it is in.
  ///
  /// Along an axis the photo now covers, it is held against the edges, so a
  /// drag cannot pull blurred backdrop into a frame the photo could fill.
  /// Along an axis it does not cover, it is centred — there is nothing to pan
  /// to, and letting it drift leaves the photo hanging off one side.
  Offset _clamp(Offset offset, double scale, Rect fitted) {
    return Offset(
      _clampAxis(offset.dx, fitted.left, fitted.width, _frame.width, scale),
      _clampAxis(offset.dy, fitted.top, fitted.height, _frame.height, scale),
    );
  }

  double _clampAxis(
    double value,
    double start,
    double extent,
    double frame,
    double scale,
  ) {
    final drawn = extent * scale;
    final origin = start * scale;
    if (drawn < frame) return (frame - drawn) / 2 - origin;

    final low = frame - origin - drawn;
    final high = -origin;
    // A photo sitting exactly as wide as the frame has one lawful position,
    // and the two bounds meet there. Compared rather than handed to `clamp`:
    // the two can arrive as 0.0 and -0.0, which are equal by `==` but ordered
    // by `compareTo` — and `clamp` uses `compareTo`, so it throws.
    if (low >= high) return high;
    return value.clamp(low, high);
  }

  /// Measures the photo against the frame, which is what makes [_clamp] mean
  /// anything. Runs once per photo, off the same provider the frame draws with.
  void _measure(Size frame) {
    if (_frame == frame && _fitted != null) return;
    _frame = frame;

    final stream = widget.image.resolve(const ImageConfiguration());
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        stream.removeListener(listener);
        if (!mounted || info.image.height <= 0) return;
        final size = Size(
          info.image.width.toDouble(),
          info.image.height.toDouble(),
        );
        final fitted = Alignment.center.inscribe(
          applyBoxFit(BoxFit.contain, size, frame).destination,
          Offset.zero & frame,
        );
        setState(() {
          _fitted = fitted;
          // The rest position: the whole photo, centred. Re-derived rather
          // than assumed, since the frame may have changed under it.
          _offset = _clamp(_offset, _scale, fitted);
        });
      },
      onError: (_, __) => stream.removeListener(listener),
    );
    stream.addListener(listener);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final frame = constraints.biggest;
        // Scheduled rather than called inline: _measure can complete
        // synchronously for an image already in the cache, and setState during
        // layout throws.
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _measure(frame));

        return ClipRect(
          child: ColoredBox(
            color: AppColors.mediaBackdrop,
            child: GestureDetector(
              // Opaque so the whole frame takes the gesture, including the
              // blurred margins either side of a fitted photo.
              behavior: HitTestBehavior.opaque,
              onScaleStart: _onScaleStart,
              onScaleUpdate: _onScaleUpdate,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  PulseBlurredBackdrop(image: widget.image),
                  Transform(
                    transform: Matrix4.identity()
                      ..translateByDouble(_offset.dx, _offset.dy, 0, 1)
                      ..scaleByDouble(_scale, _scale, 1, 1),
                    child: Image(
                      image: widget.image,
                      fit: BoxFit.contain,
                      // Filtered up as it is zoomed, rather than going blocky
                      // the moment it passes 1:1.
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
