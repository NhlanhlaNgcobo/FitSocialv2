import 'package:flutter/material.dart';

import 'app_photo.dart';
import 'picture_ratio.dart';

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
    this.fallbackAspectRatio = kPictureAspectRatio,
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
    final stream =
        appPhoto(widget.imageUrl).resolve(const ImageConfiguration());
    _stream = stream..addListener(_listener);
  }

  void _onImage(ImageInfo info, bool synchronousCall) {
    final width = info.image.width;
    final height = info.image.height;
    if (height <= 0) return;
    // From the app's 9:16 up to the widest feed shape: the real shape of
    // every photo the cropper produces, and narrow enough that one malformed
    // or panoramic image can't blow out a feed's layout.
    final ratio =
        (width / height).clamp(kPictureAspectRatio, kWidestPictureRatio);
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

/// A photo post's frame: the shape it was cropped to, from [storedRatio], or
/// the photo's own shape measured as it loads when the post never stored one.
class PhotoPostAspectRatio extends StatelessWidget {
  const PhotoPostAspectRatio({
    required this.storedRatio,
    required this.imageUrl,
    required this.child,
    super.key,
  });

  final double? storedRatio;
  final String? imageUrl;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final known = photoPostRatio(storedRatio);
    final url = imageUrl;
    if (known != null || url == null || url.isEmpty) {
      return AspectRatio(
        aspectRatio: known ?? kPictureAspectRatio,
        child: child,
      );
    }
    return NetworkPhotoAspect(
      imageUrl: url,
      builder: (context, ratio) =>
          AspectRatio(aspectRatio: ratio, child: child),
    );
  }
}
