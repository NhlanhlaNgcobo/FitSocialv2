import 'package:flutter/material.dart';

import 'app_photo.dart';

/// Resolves a network photo's real width/height before laying out [builder],
/// so a card built around it shows the photo the way it was actually taken
/// instead of cropping it to a guessed shape.
///
/// [fallbackAspectRatio] is what [builder] gets before the photo has decoded
/// — briefly, and only once per URL, since a photo already in Flutter's image
/// cache resolves on the same frame.
class NetworkPhotoAspect extends StatefulWidget {
  const NetworkPhotoAspect({
    required this.imageUrl,
    required this.builder,
    this.fallbackAspectRatio = 1,
    super.key,
  });

  final String imageUrl;
  final Widget Function(BuildContext context, double aspectRatio) builder;
  final double fallbackAspectRatio;

  @override
  State<NetworkPhotoAspect> createState() => _NetworkPhotoAspectState();
}

class _NetworkPhotoAspectState extends State<NetworkPhotoAspect> {
  double? _aspectRatio;
  ImageStream? _stream;
  late final ImageStreamListener _listener;

  @override
  void initState() {
    super.initState();
    _listener = ImageStreamListener(_onImage, onError: (_, __) {});
    _resolve();
  }

  @override
  void didUpdateWidget(covariant NetworkPhotoAspect oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl == widget.imageUrl) return;
    _stream?.removeListener(_listener);
    _aspectRatio = null;
    _resolve();
  }

  void _resolve() {
    // The same provider the card itself draws with, so measuring the photo and
    // showing it are one fetch rather than two.
    final stream = appPhoto(widget.imageUrl).resolve(const ImageConfiguration());
    _stream = stream..addListener(_listener);
  }

  void _onImage(ImageInfo info, bool synchronousCall) {
    final width = info.image.width;
    final height = info.image.height;
    if (height <= 0) return;
    // Instagram's own legal range: wide enough to show the real shape of
    // every ordinary camera photo, narrow enough that one malformed or
    // panoramic image can't blow out a feed's layout.
    final ratio = (width / height).clamp(0.8, 1.91);
    if (!mounted) return;
    setState(() => _aspectRatio = ratio);
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _aspectRatio ?? widget.fallbackAspectRatio);
  }
}
