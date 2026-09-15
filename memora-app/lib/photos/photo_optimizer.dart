import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_image_compress/flutter_image_compress.dart';

/// Fixed optimization defaults (spec03-fotografias.md, decision 3, D15/D8).
/// The user never chooses these.
const int kMaxPhotoSide = 2048;
const int kJpegQuality = 85;

/// Target pixel size for a resize, computed by [computeTargetDimensions].
class PhotoDimensions {
  const PhotoDimensions(this.width, this.height);

  final int width;
  final int height;
}

/// Caps the longer side at [maxSide] px, preserving aspect ratio, and never
/// upscales. Pure and synchronous on purpose — see [PhotoOptimizer]'s doc
/// for why this can't just be `flutter_image_compress`'s own
/// `minWidth`/`minHeight`.
PhotoDimensions computeTargetDimensions(
  int sourceWidth,
  int sourceHeight, {
  int maxSide = kMaxPhotoSide,
}) {
  final longSide = sourceWidth > sourceHeight ? sourceWidth : sourceHeight;
  if (longSide <= maxSide) {
    return PhotoDimensions(sourceWidth, sourceHeight);
  }
  final scale = maxSide / longSide;
  return PhotoDimensions(
    (sourceWidth * scale).round(),
    (sourceHeight * scale).round(),
  );
}

/// Result of optimizing one photo: the ready-to-upload bytes plus the
/// resulting pixel dimensions (decoded from the actual output, so they're
/// correct even when EXIF orientation swapped width/height).
class OptimizedPhoto {
  const OptimizedPhoto({
    required this.bytes,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final int width;
  final int height;
}

/// Optimizes a photo per D15 (automatic optimization, fixed defaults) and D8
/// (no geolocation): caps the longer side at [kMaxPhotoSide]px (never
/// upscales), recompresses as JPEG at ~[kJpegQuality]%, bakes in EXIF
/// orientation, and drops EXIF/GPS from the result.
///
/// Always works on an in-memory copy of the bytes handed to it — the
/// original file on the device is never opened for writing, let alone
/// modified or deleted.
///
/// Gotcha this class exists to work around: `flutter_image_compress`'s own
/// `minWidth`/`minHeight` are NOT "cap the longer side". Internally it
/// computes `scale = max(1, min(srcW / minWidth, srcH / minHeight))` —
/// passing the same value (2048) for both silently skips resizing whenever
/// EITHER raw dimension is already <= 2048, even if the OTHER dimension is
/// far larger (e.g. a 4000x1200 photo would stay untouched at 4000x1200). So
/// this class first decodes the real source size and computes the exact
/// target width/height itself (via [computeTargetDimensions], kept pure and
/// separately unit-testable), which collapses the plugin's formula to the
/// intended "cap the longer side, preserve aspect, never upscale".
class PhotoOptimizer {
  const PhotoOptimizer();

  Future<OptimizedPhoto> optimize(Uint8List sourceBytes) async {
    final sourceSize = await _decodeSize(sourceBytes);
    final target = computeTargetDimensions(sourceSize.width, sourceSize.height);

    final compressed = await FlutterImageCompress.compressWithList(
      sourceBytes,
      minWidth: target.width,
      minHeight: target.height,
      quality: kJpegQuality,
      format: CompressFormat.jpeg,
      // autoCorrectionAngle defaults to true: bakes EXIF orientation into
      // the output pixels (D15 "aplicar orientación EXIF").
      // keepExif defaults to false: strips EXIF/GPS from the output (D8)
      // — do not pass true here.
    );

    // Decode the actual output size rather than reusing `target`: if the
    // source's EXIF orientation implied a 90/270 rotation, the baked-in
    // output has width/height swapped relative to the raw source used to
    // compute `target`.
    final outputSize = await _decodeSize(compressed);

    return OptimizedPhoto(
      bytes: compressed,
      width: outputSize.width,
      height: outputSize.height,
    );
  }

  Future<PhotoDimensions> _decodeSize(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final size = PhotoDimensions(frame.image.width, frame.image.height);
    frame.image.dispose();
    codec.dispose();
    return size;
  }
}
