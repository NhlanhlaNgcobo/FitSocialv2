import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../services/photo_crop.dart';
import 'primary_button.dart';
import 'quick_toast.dart';

/// FitSocial's own photo crop screen.
///
/// The photo sits under a fixed frame in the chosen shape; pinch to zoom, drag
/// to place it, double-tap to start again. The frame never moves and the photo
/// can never be dragged clear of it, so what is inside the frame is exactly
/// what gets posted.
///
/// Pops with the cropped JPEG, ready to upload, or null if the user backs out.
class CropPhotoScreen extends StatefulWidget {
  const CropPhotoScreen({
    required this.bytes,
    this.shapes = CropShape.storyOnly,
    this.title = 'Crop photo',
    this.quality = 80,
    super.key,
  }) : assert(shapes.length > 0, 'Offer at least one shape.');

  /// The photo as picked, in whatever format the picker handed back.
  final Uint8List bytes;

  /// The shapes on offer. The first is where the screen starts; with only one
  /// there is no shape row at all.
  final List<CropShape> shapes;

  /// The heading across the top.
  final String title;

  /// JPEG quality of the result.
  final int quality;

  /// Opens the screen over everything, and returns the cropped JPEG.
  static Future<Uint8List?> open(
    BuildContext context,
    Uint8List bytes, {
    List<CropShape> shapes = CropShape.storyOnly,
    String title = 'Crop photo',
    int quality = 80,
  }) {
    return Navigator.of(context, rootNavigator: true).push<Uint8List>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CropPhotoScreen(
          bytes: bytes,
          shapes: shapes,
          title: title,
          quality: quality,
        ),
      ),
    );
  }

  @override
  State<CropPhotoScreen> createState() => _CropPhotoScreenState();
}

class _CropPhotoScreenState extends State<CropPhotoScreen> {
  /// How far past the covering scale the photo may be zoomed.
  static const double _maxZoom = 6;

  /// Longest side the on-screen copy is decoded at: sharp at any zoom a phone
  /// screen can show, without holding the full original in memory.
  static const int _previewSide = 2048;

  ui.Image? _preview;
  bool _failed = false;
  bool _saving = false;

  late CropShape _shape = widget.shapes.first;
  int _quarterTurns = 0;

  /// Multiples of the covering scale, so a zoom survives the frame changing
  /// size. 1 is "just covers the frame".
  double _zoom = 1;

  /// The photo's centre relative to the frame's, in screen pixels.
  Offset _offset = Offset.zero;

  bool _gesturing = false;
  double _gestureZoom = 1;
  Offset _gestureOffset = Offset.zero;
  Offset _gestureFocal = Offset.zero;

  /// Kept from the last layout, for the gesture and save handlers.
  Size _frame = Size.zero;
  Offset _frameCenter = Offset.zero;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  Future<void> _decode() async {
    try {
      final preview = await decodePhoto(widget.bytes, maxSide: _previewSide);
      if (!mounted) {
        preview.dispose();
        return;
      }
      setState(() => _preview = preview);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _preview?.dispose();
    super.dispose();
  }

  Size get _photoSize {
    final preview = _preview!;
    return CropGeometry.turned(
      Size(preview.width.toDouble(), preview.height.toDouble()),
      _quarterTurns,
    );
  }

  double get _scale => CropGeometry.coverScale(_photoSize, _frame) * _zoom;

  void _reset() => setState(() {
        _zoom = 1;
        _offset = Offset.zero;
      });

  void _pickShape(CropShape shape) {
    if (shape == _shape) return;
    HapticFeedback.selectionClick();
    setState(() {
      _shape = shape;
      _zoom = 1;
      _offset = Offset.zero;
    });
  }

  void _rotate() {
    HapticFeedback.selectionClick();
    setState(() {
      _quarterTurns = (_quarterTurns + 1) % 4;
      _zoom = 1;
      _offset = Offset.zero;
    });
  }

  void _onScaleStart(ScaleStartDetails details) {
    _gestureZoom = _zoom;
    _gestureOffset = _offset;
    _gestureFocal = details.localFocalPoint;
    setState(() => _gesturing = true);
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_preview == null || _frame.isEmpty) return;
    final zoom = (_gestureZoom * details.scale).clamp(1.0, _maxZoom);
    // Keep the point under the fingers under the fingers: scale its distance
    // from the photo's centre, then follow the fingers as they move.
    final ratio = zoom / _gestureZoom;
    final anchored = (_gestureFocal - _frameCenter - _gestureOffset) * ratio;
    final offset = details.localFocalPoint - _frameCenter - anchored;
    setState(() {
      _zoom = zoom;
      _offset = CropGeometry.clampOffset(
        offset,
        _photoSize,
        CropGeometry.coverScale(_photoSize, _frame) * zoom,
        _frame,
      );
    });
  }

  void _onScaleEnd(ScaleEndDetails details) {
    setState(() => _gesturing = false);
  }

  Future<void> _save() async {
    if (_preview == null || _frame.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      final jpeg = await renderCrop(
        widget.bytes,
        quality: widget.quality,
        quarterTurns: _quarterTurns,
        fraction: CropGeometry.cropFraction(
          photo: _photoSize,
          scale: _scale,
          offset: _offset,
          frame: _frame,
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(jpeg);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showQuickToast(
        context,
        "Couldn't crop that photo. Try again.",
        icon: Icons.error_outline_rounded,
        tone: ToastTone.danger,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: AppColors.mediaBackdrop,
      ),
      child: Scaffold(
        backgroundColor: AppColors.mediaBackdrop,
        body: SafeArea(
          child: Column(
            children: [
              _TopBar(
                title: widget.title,
                onClose: () => Navigator.of(context).pop(),
              ),
              Expanded(child: _buildStage()),
              _Controls(
                shapes: widget.shapes,
                selected: _shape,
                saving: _saving,
                ready: _preview != null,
                onShape: _saving ? null : _pickShape,
                onRotate: _saving || _preview == null ? null : _rotate,
                onDone: _saving || _preview == null ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStage() {
    final preview = _preview;
    if (_failed) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: Text(
            "This photo couldn't be opened.",
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.onMediaMuted, fontSize: 15),
          ),
        ),
      );
    }
    if (preview == null) {
      return const Center(
        child: SizedBox.square(
          dimension: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: AppColors.orangeBright,
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const inset = EdgeInsets.fromLTRB(20, 12, 20, 20);
        final area = inset.deflateSize(constraints.biggest);
        _frame = CropGeometry.fitFrame(area, _shape.ratio);
        _frameCenter = Offset(
          inset.left + area.width / 2,
          inset.top + area.height / 2,
        );
        final frameRect = Rect.fromCenter(
          center: _frameCenter,
          width: _frame.width,
          height: _frame.height,
        );

        final photo = _photoSize;
        final scale = _scale;
        final offset = CropGeometry.clampOffset(_offset, photo, scale, _frame);
        final shown = Size(photo.width * scale, photo.height * scale);
        final photoRect = Rect.fromCenter(
          center: _frameCenter + offset,
          width: shown.width,
          height: shown.height,
        );

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onScaleStart: _onScaleStart,
          onScaleUpdate: _onScaleUpdate,
          onScaleEnd: _onScaleEnd,
          onDoubleTap: _reset,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned.fromRect(
                rect: photoRect,
                child: RotatedBox(
                  quarterTurns: _quarterTurns,
                  child: RawImage(
                    image: preview,
                    fit: BoxFit.fill,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _FramePainter(
                      frame: frameRect,
                      circular: _shape.circular,
                    ),
                  ),
                ),
              ),
              Positioned.fromRect(
                rect: frameRect,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    // The thirds only while the photo is moving: they help
                    // place it, and would only clutter the picture otherwise.
                    // Never over a circle, where a square grid only clutters.
                    opacity: _gesturing && !_shape.circular ? 1 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(_frameRadius),
                      child: const CustomPaint(painter: _GridPainter()),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.title, required this.onClose});

  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          const SizedBox(width: 4),
          IconButton(
            onPressed: onClose,
            tooltip: 'Cancel',
            icon: const Icon(Icons.close_rounded, color: AppColors.onMedia),
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.onMedia,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          // Balances the close button, so the title sits in the true centre.
          const SizedBox(width: 52),
        ],
      ),
    );
  }
}

/// The shape row, the rotate button and Done.
class _Controls extends StatelessWidget {
  const _Controls({
    required this.shapes,
    required this.selected,
    required this.saving,
    required this.ready,
    required this.onShape,
    required this.onRotate,
    required this.onDone,
  });

  final List<CropShape> shapes;
  final CropShape selected;
  final bool saving;
  final bool ready;
  final ValueChanged<CropShape>? onShape;
  final VoidCallback? onRotate;
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            ready ? 'Pinch to zoom · drag to move · double-tap to reset' : '',
            style: const TextStyle(color: AppColors.onMediaMuted, fontSize: 12),
          ),
          const SizedBox(height: AppSpacing.md),
          if (shapes.length > 1) ...[
            Row(
              children: [
                for (final shape in shapes)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _ShapeChip(
                        shape: shape,
                        selected: shape == selected,
                        onTap: onShape == null ? null : () => onShape!(shape),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          Row(
            children: [
              _RoundButton(
                icon: Icons.rotate_90_degrees_cw_outlined,
                tooltip: 'Rotate',
                onPressed: onRotate,
              ),
              const SizedBox(width: AppSpacing.sm + 4),
              Expanded(
                child: PrimaryButton(
                  icon: saving ? null : Icons.check_rounded,
                  label: saving ? 'Cropping…' : 'Use photo',
                  onPressed: onDone,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One shape: a small outline of it over its name.
class _ShapeChip extends StatelessWidget {
  const _ShapeChip({
    required this.shape,
    required this.selected,
    required this.onTap,
  });

  final CropShape shape;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.orangeBright : AppColors.onMediaMuted;
    // The outline is drawn inside an 18px square, sized to the shape.
    final glyph = shape.ratio >= 1
        ? Size(18, 18 / shape.ratio)
        : Size(18 * shape.ratio, 18);

    return Semantics(
      button: true,
      selected: selected,
      label: 'Crop to ${shape.label}',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? const Color(0x24FF6B1A) : const Color(0xFF121212),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color:
                  selected ? AppColors.orangeBright : const Color(0xFF262626),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox.square(
                dimension: 18,
                child: Center(
                  child: Container(
                    width: glyph.width,
                    height: glyph.height,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2.5),
                      border: Border.all(color: color, width: 1.6),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                shape.label,
                style: TextStyle(
                  color: selected ? AppColors.onMedia : AppColors.onMediaMuted,
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: const Color(0xFF121212),
        shape: const CircleBorder(side: BorderSide(color: Color(0xFF262626))),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox.square(
            dimension: 56,
            child: Icon(
              icon,
              color: onPressed == null
                  ? AppColors.onMediaMuted.withValues(alpha: 0.4)
                  : AppColors.onMedia,
            ),
          ),
        ),
      ),
    );
  }
}

/// Corner radius of the crop frame: the same rounding every picture in the
/// app is shown with, so the frame reads as the card the photo is going into.
const double _frameRadius = 20;

/// Dims everything outside the frame and draws the frame itself: a hairline
/// edge with heavier orange corners to grab the eye, all following the
/// frame's rounded corners.
class _FramePainter extends CustomPainter {
  const _FramePainter({required this.frame, required this.circular});

  final Rect frame;

  /// A profile photo's circle: one whole orange ring instead of corners.
  final bool circular;

  @override
  void paint(Canvas canvas, Size size) {
    final rounded = RRect.fromRectAndRadius(
      frame,
      Radius.circular(circular ? frame.shortestSide / 2 : _frameRadius),
    );

    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(rounded);
    canvas.drawPath(outside, Paint()..color = AppColors.cropDimmed);

    canvas.drawRRect(
      rounded,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xB3F7F7F7),
    );

    // The heavy corners are the same rounded outline, kept only near each
    // corner: each is clipped to a square reaching [reach] along both edges.
    const reach = _frameRadius + 16;
    final corner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..color = AppColors.orangeBright;
    if (circular) {
      canvas.drawRRect(rounded, corner..strokeWidth = 2.5);
      return;
    }
    // Wide enough to hold the whole stroke, which straddles the edge.
    const bleed = 4.0;
    final squares = [
      Rect.fromLTWH(
          frame.left - bleed, frame.top - bleed, reach + bleed, reach + bleed),
      Rect.fromLTWH(
          frame.right - reach, frame.top - bleed, reach + bleed, reach + bleed),
      Rect.fromLTWH(frame.left - bleed, frame.bottom - reach, reach + bleed,
          reach + bleed),
      Rect.fromLTWH(frame.right - reach, frame.bottom - reach, reach + bleed,
          reach + bleed),
    ];
    for (final square in squares) {
      canvas
        ..save()
        ..clipRect(square)
        ..drawRRect(rounded, corner)
        ..restore();
    }
  }

  @override
  bool shouldRepaint(_FramePainter old) =>
      old.frame != frame || old.circular != circular;
}

/// Rule-of-thirds lines across the frame.
class _GridPainter extends CustomPainter {
  const _GridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeWidth = 1
      ..color = AppColors.cropGrid;
    for (var i = 1; i < 3; i++) {
      final x = size.width * i / 3;
      final y = size.height * i / 3;
      canvas
        ..drawLine(Offset(x, 0), Offset(x, size.height), paint)
        ..drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => false;
}
