/// Spacing and radius tokens for the Aurora design system (Fase 1). Kept as
/// plain constants (not an enum/class hierarchy) since screens just need a
/// handful of consistent numbers to reach for instead of picking new
/// magic-number paddings per widget.
abstract final class MemoraSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;
}

abstract final class MemoraRadius {
  /// Hero/large feature cards.
  static const hero = 32.0;

  /// Standard cards.
  static const card = 20.0;

  /// Photo grid thumbnails (album-detail grid, Fase 2 del rediseño) — small
  /// enough not to compete visually with `card`/`hero`, but still a shared
  /// token instead of a one-off number so any future photo-tile grid stays
  /// consistent with this one.
  static const thumbnail = 14.0;

  /// Chips/badges/pills — fully rounded regardless of height.
  static const pill = 999.0;
}
