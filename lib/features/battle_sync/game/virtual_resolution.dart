import 'dart:math';
import 'dart:ui';

class VirtualResolution {
  const VirtualResolution({this.width = 1000, this.height = 600});

  final double width;
  final double height;

  double get aspectRatio => width / height;

  Rect fitWithin(Size maxSize) {
    final scale = min(maxSize.width / width, maxSize.height / height);
    final fittedWidth = width * scale;
    final fittedHeight = height * scale;
    return Rect.fromLTWH(
      (maxSize.width - fittedWidth) / 2,
      (maxSize.height - fittedHeight) / 2,
      fittedWidth,
      fittedHeight,
    );
  }

  double scaleFor(Size maxSize) {
    return min(maxSize.width / width, maxSize.height / height);
  }

  Offset toLogical(Offset physical, Rect viewport) {
    final scale = viewport.width / width;
    return Offset(
      (physical.dx - viewport.left) / scale,
      (physical.dy - viewport.top) / scale,
    );
  }

  Offset toPhysical(Offset logical, Rect viewport) {
    final scale = viewport.width / width;
    return Offset(
      logical.dx * scale + viewport.left,
      logical.dy * scale + viewport.top,
    );
  }
}