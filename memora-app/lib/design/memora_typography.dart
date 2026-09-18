import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'memora_colors.dart';

/// Single-family typography (Manrope, weights 400/600/700/800) for the
/// Aurora design system. Builds a full [TextTheme] with a clear hierarchy —
/// hero/display, titles, subtitles, body, captions — reused by every
/// screen instead of ad hoc `TextStyle`s.
///
/// **Light-first pivot**: every style's explicit `color` used to default to
/// [MemoraColors.paper] (text-on-dark, when Deep Ink was the canvas) — now
/// they default to [MemoraColors.deepInk] (text-on-light, now that
/// [MemoraColors.paper] is the canvas). The deliberate dark exceptions
/// (`photo_viewer_screen.dart`, `HomeScreen`'s Welcome/hero composition, the
/// album-detail hero overlay, any `MemoraCardElevation.ink` card) must pass
/// an explicit `.copyWith(color: MemoraColors.paper, ...)` at the call site —
/// same mechanic as the old `MemoraCardElevation.light`'s gotcha, just
/// mirrored: an explicit `textTheme.*` color always wins over any ambient
/// `DefaultTextStyle`, so relying on "the surface will fix it" doesn't work.
abstract final class MemoraTypography {
  static TextTheme textTheme() {
    return TextTheme(
      // Hero/display ~34-40sp, weight 800.
      displayLarge: GoogleFonts.manrope(
        fontSize: 40,
        fontWeight: FontWeight.w800,
        height: 1.1,
        letterSpacing: -0.6,
        color: MemoraColors.deepInk,
      ),
      displayMedium: GoogleFonts.manrope(
        fontSize: 34,
        fontWeight: FontWeight.w800,
        height: 1.15,
        letterSpacing: -0.4,
        color: MemoraColors.deepInk,
      ),
      // Titles ~24sp, weight 700.
      headlineMedium: GoogleFonts.manrope(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        height: 1.2,
        color: MemoraColors.deepInk,
      ),
      headlineSmall: GoogleFonts.manrope(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        height: 1.2,
        color: MemoraColors.deepInk,
      ),
      // Subtitles ~16sp, weight 600.
      titleMedium: GoogleFonts.manrope(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: MemoraColors.deepInk,
      ),
      titleSmall: GoogleFonts.manrope(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: MemoraColors.deepInk,
      ),
      // Body ~15sp, weight 400.
      bodyLarge: GoogleFonts.manrope(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: MemoraColors.deepInk,
      ),
      bodyMedium: GoogleFonts.manrope(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: MemoraColors.textSecondary,
      ),
      bodySmall: GoogleFonts.manrope(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: MemoraColors.textTertiary,
      ),
      // Buttons ~15sp, weight 700. Unchanged: this is the CTA label color
      // over `signatureGradient`/light surfaces, already Deep Ink before the
      // pivot (the gradient was always light enough for it) and still
      // correct now.
      labelLarge: GoogleFonts.manrope(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: MemoraColors.deepInk,
      ),
      // Captions/metadata ~12-13sp, weight 500.
      labelMedium: GoogleFonts.manrope(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: MemoraColors.textTertiary,
      ),
      labelSmall: GoogleFonts.manrope(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: MemoraColors.textTertiary,
      ),
    );
  }

  /// A soft, photo-legibility text shadow — never a hard/comic-style
  /// stroke — for any headline/label composited directly over a photo (a
  /// hero image, an overlay caption) where a scrim alone can't guarantee
  /// contrast in every zone of the photo. Two stops — a tight dark one plus
  /// a softer wide one — read as a natural shadow instead of a single flat
  /// blur. [intensity] scales both down for smaller/secondary text under the
  /// same headline (e.g. a subtitle needs less than the headline itself).
  ///
  /// Only meaningful paired with an explicit `color: MemoraColors.paper`
  /// override (see the class doc) — this helper only adds the shadow, it
  /// never changes the text's own color.
  static List<Shadow> legibilityShadows({double intensity = 1}) => [
    Shadow(
      color: MemoraColors.deepInk.withValues(alpha: 0.55 * intensity),
      offset: const Offset(0, 1),
      blurRadius: 3,
    ),
    Shadow(
      color: MemoraColors.deepInk.withValues(alpha: 0.35 * intensity),
      offset: const Offset(0, 2),
      blurRadius: 10,
    ),
  ];
}
