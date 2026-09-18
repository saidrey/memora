import 'package:flutter/material.dart';

/// Color tokens for the "Aurora" visual system.
///
/// **Pivot to light-first (60-30-10), sin spec de Kiro** — after the
/// dark-first system (Fase 1/2 del rediseño) shipped and was validated on a
/// real device several times, the user kept reporting the app as "sin vida"
/// and "muy oscura". Direction change, decided with the user directly:
/// pivot from dark-first (Deep Ink as the dominant canvas) to **light-first**,
/// following the 60-30-10 rule with the exact same 5 colors — only their
/// ROLES change, no hex value here changed for `deepInk`/`glassBlue`/
/// `auraViolet`/`mist`/`paper` themselves:
///
/// - **60% [paper]** — the dominant canvas now (`scaffoldBackgroundColor`,
///   most screens' background). Used to be the rare "light island" exception;
///   now it's the default.
/// - **30% [mist]** — the secondary surface: cards, sections, more visible
///   dividers, sheet/dialog backgrounds.
/// - **10% split in two roles for [deepInk]**: it's no longer the canvas —
///   it's the "ink" (primary text over the light canvas, via
///   [MemoraTypography]) AND a deliberate strong dark accent for a handful
///   of protagonist elements (e.g. `AlbumsListScreen`'s plain "+" FAB — see
///   CLAUDE.md — never as a full-screen background again except the
///   deliberate dark exceptions below).
/// - **10% [signatureGradient]** — unchanged as a color accent (CTAs,
///   standout badges, avatars, and now also album-card borders instead of
///   full-card fills — see `album_card_style.dart`).
///
/// **Deliberate dark exceptions, still using the ORIGINAL (light-on-dark)
/// tokens directly, never the light-canvas-calibrated ones below**:
/// `photo_viewer_screen.dart` (full screen, platform convention — see its
/// own doc comment), `HomeScreen`'s Welcome/hero composition (a photo with
/// dark scrims), the album-detail hero overlay (same reason), and any
/// `MemoraCardElevation.ink` card. Those contexts use [paper]/[glassBlue]/
/// [auraViolet] raw, [semanticErrorOnDark]/[semanticSuccessOnDark], and
/// hardcode their own light-on-dark borders/opacities inline rather than
/// reusing [border]/[textSecondary]/[textTertiary] (which are now
/// deepInk-based, i.e. calibrated for the light canvas and close to
/// invisible on a dark background).
abstract final class MemoraColors {
  /// The "ink": primary text over the light canvas, and a deliberate strong
  /// dark accent for a handful of protagonist elements. No longer the
  /// screen background (see the class doc for the light-first pivot).
  static const deepInk = Color(0xFF080B18);

  /// Primary accent — start of the signature gradient. Raw (light) value —
  /// safe as a gradient component or over a dark surface; see
  /// [glassBlueOnLight] for any place this needs to read as an icon/text/
  /// border foreground directly on [paper]/[mist].
  static const glassBlue = Color(0xFF7DD3FC);

  /// Secondary accent — end of the signature gradient. Same caveat as
  /// [glassBlue]; see [auraVioletOnLight].
  static const auraViolet = Color(0xFFA78BFA);

  /// The 30% secondary surface: cards, sections, sheets/dialogs, more
  /// visible dividers.
  static const mist = Color(0xFFE5E7EB);

  /// The 60% dominant canvas — `scaffoldBackgroundColor` and most screens'
  /// background.
  static const paper = Color(0xFFF8FAFC);

  /// `MemoraCardElevation.level1` — the default, most common card surface:
  /// a soft, barely-tinted off-white (Paper/Mist blended 60/40, precomputed
  /// since `Color.lerp` isn't a compile-time constant) that reads as a
  /// subtle card against the Paper canvas without competing with [surface2].
  static const surface1 = Color(0xFFF0F2F5);

  /// `MemoraCardElevation.level2` — a more "raised"/louder card (bigger
  /// sections, standout summary tiles): full [mist]. Kept as its own named
  /// token (rather than call sites referencing `mist` directly) so the
  /// elevation's intent stays explicit at the call site.
  static const surface2 = mist;

  /// Deep Ink at ~10% opacity — the subtle border used across cards/
  /// dividers/inputs on the light canvas. (Previously Mist at 8%, tuned for
  /// a dark canvas — see the class doc for the pivot.)
  static const border = Color(0x1A080B18);

  /// Deep Ink at ~70% opacity — secondary text on the light canvas.
  /// (Previously Paper at reduced opacity, tuned for a dark canvas.)
  static const textSecondary = Color(0xB3080B18);

  /// Deep Ink at ~50% opacity — tertiary text/captions on the light canvas.
  /// (Previously Mist at reduced opacity.)
  static const textTertiary = Color(0x80080B18);

  /// [glassBlue] blended 45% toward [deepInk] — for any place Glass Blue
  /// needs to read as an icon/text/focus-border/spinner foreground directly
  /// on [paper]/[mist]: raw Glass Blue is very light (~1.6:1 contrast on
  /// Paper, well under the ~3:1 WCAG floor for UI components/graphics), so
  /// it's unreadable as a bare foreground on the light canvas. Precomputed
  /// (`Color.lerp` isn't const). Never use this over a dark surface/photo —
  /// use raw [glassBlue] there instead (it was calibrated for exactly that).
  static const glassBlueOnLight = Color(0xFF487995);

  /// [auraViolet] blended 45% toward [deepInk] — same rationale as
  /// [glassBlueOnLight], for Aura Violet used as a foreground on the light
  /// canvas.
  static const auraVioletOnLight = Color(0xFF5F5194);

  /// Error red, darkened/saturated for legibility on the light canvas
  /// (~6.6:1 against [paper], comfortably AA even for normal text). The
  /// original lighter value (calibrated for the dark canvas, ~2:1 on Paper —
  /// not legible there) lives on as [semanticErrorOnDark] for the deliberate
  /// dark exceptions.
  static const semanticError = Color(0xFFB91C1C);

  /// Success green, darkened/saturated for legibility on the light canvas
  /// (~4.8:1 against [paper]). See [semanticError]'s doc comment — same
  /// rationale. Original value lives on as [semanticSuccessOnDark].
  static const semanticSuccess = Color(0xFF15803D);

  /// The original (light-on-dark) error red — for the deliberate dark
  /// exceptions (a dark scrim/photo, `MemoraCardElevation.ink`) where the
  /// darkened [semanticError] above would be unreadable (dark red on a near-
  /// black background).
  static const semanticErrorOnDark = Color(0xFFFCA5A5);

  /// The original (light-on-dark) success green — kept symmetrically with
  /// [semanticErrorOnDark] for any future dark-exception context that needs
  /// it (not currently used: no dark-context screen shows success text/
  /// icons today).
  static const semanticSuccessOnDark = Color(0xFF86EFAC);

  /// The signature gradient (135°): Glass Blue -> Aura Violet. Unchanged —
  /// used strategically (primary CTA, album-card borders, standout badges,
  /// avatars) — never as a blanket background.
  static const signatureGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [glassBlue, auraViolet],
  );
}
