import 'package:flutter_test/flutter_test.dart';

import 'package:memora_app/albums/screens/album_card_style.dart';

void main() {
  group('gradientForAlbumId', () {
    test('is deterministic for the same id', () {
      final a = gradientForAlbumId('album-123');
      final b = gradientForAlbumId('album-123');

      expect(a.begin, b.begin);
      expect(a.end, b.end);
      expect(a.colors, b.colors);
    });

    test('varies across different ids (not every card looks identical)', () {
      final ids = List.generate(12, (i) => 'album-$i');
      final gradients = ids.map(gradientForAlbumId).toList();

      final distinctBegins = gradients.map((g) => g.begin).toSet();
      final distinctFirstColors = gradients.map((g) => g.colors.first).toSet();

      // With 12 sample ids spread over 5 alignment variants and a wide mix
      // range, both the angle and the color mix should show real variety —
      // not a strict uniqueness requirement (hash collisions are fine), but
      // clearly more than one distinct value.
      expect(distinctBegins.length, greaterThan(1));
      expect(distinctFirstColors.length, greaterThan(1));
    });

    test('always returns exactly two colors', () {
      final gradient = gradientForAlbumId('any-id');
      expect(gradient.colors.length, 2);
    });
  });
}
