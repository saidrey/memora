import 'package:flutter_test/flutter_test.dart';
import 'package:memora_app/photos/photo_optimizer.dart';

// PhotoOptimizer.optimize() itself calls flutter_image_compress (a
// MethodChannel plugin) and dart:ui image decoding, so it can't run as a
// plain unit test without a device — only the pure sizing math
// (computeTargetDimensions) is exercised here, per spec03-fotografias.md's
// note that the optimizer's *parameters* should be testable.
void main() {
  group('computeTargetDimensions', () {
    test('downscales a landscape photo so the long side is exactly 2048', () {
      final result = computeTargetDimensions(4000, 2000);

      expect(result.width, 2048);
      expect(result.height, 1024);
    });

    test('downscales a portrait photo so the long side is exactly 2048', () {
      final result = computeTargetDimensions(2000, 4000);

      expect(result.width, 1024);
      expect(result.height, 2048);
    });

    test('never upscales a photo already smaller than the max side', () {
      final result = computeTargetDimensions(800, 600);

      expect(result.width, 800);
      expect(result.height, 600);
    });

    test('leaves a photo exactly at the max side untouched', () {
      final result = computeTargetDimensions(2048, 1000);

      expect(result.width, 2048);
      expect(result.height, 1000);
    });

    test('respects a custom maxSide', () {
      final result = computeTargetDimensions(1000, 500, maxSide: 200);

      expect(result.width, 200);
      expect(result.height, 100);
    });

    test('a wide-but-short photo is still capped even though the shorter '
        'side is already small (the flutter_image_compress minWidth/'
        'minHeight gotcha this function exists to avoid)', () {
      // 4000x1200: raw height (1200) is already <= 2048, but the long
      // side (4000, the width) is not — it must still be capped.
      final result = computeTargetDimensions(4000, 1200);

      expect(result.width, 2048);
      expect(result.height, 614);
    });
  });
}
