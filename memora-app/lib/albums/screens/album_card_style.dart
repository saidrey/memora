import 'package:flutter/material.dart';

import '../../design/memora_colors.dart';

/// Deterministic visual variety for the album cards: `AlbumListItem` carries
/// no cover photo (`GET /api/v1/albums` doesn't return one — see
/// `CLAUDE.md`), so each card gets a gradient derived from the Aurora
/// palette, varied by angle and color mix using a pure hash of the album's
/// `id`. Kept as a standalone, side-effect-free function so it's
/// unit-testable without a device — same pattern as
/// `computeTargetDimensions`/`buildUriRecord` elsewhere in this app.
///
/// **Light-first pivot**: this used to blend the accent colors at low alpha
/// onto `surface1`/`surface2` (then dark navy tones) to fill an entire card
/// with a moody, dark-tinted gradient. Now `AlbumsListScreen`'s
/// `_AlbumGridCard` uses this gradient as a thick BORDER frame around a
/// light `MemoraCard`, not a full-card fill (Referencia B pattern) — so the
/// gradient needs to read as a vivid, saturated frame instead of a dark
/// wash. The dark-surface blending was dropped; this now interpolates
/// directly between the two accent colors. Still used as a full-bleed
/// fallback background too (`AlbumDetailScreen._AlbumHero`, when an album
/// has no photos) — that spot's own Deep Ink scrims still guarantee overlay
/// text contrast regardless of how bright the base gradient is.
const _beginAlignments = [
  Alignment.topLeft,
  Alignment.topRight,
  Alignment.centerLeft,
  Alignment.bottomLeft,
  Alignment.topCenter,
];

const _endAlignments = [
  Alignment.bottomRight,
  Alignment.bottomLeft,
  Alignment.centerRight,
  Alignment.topRight,
  Alignment.bottomCenter,
];

/// A simple, stable string hash (djb2-like) — no dependency on
/// [Object.hashCode], which isn't guaranteed stable across runs/isolates.
int _stableHash(String input) {
  var hash = 0;
  for (final unit in input.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return hash;
}

/// Builds a deterministic gradient for an album card from its [albumId]:
/// same id always yields the same gradient (so a card doesn't visually
/// "jump" between rebuilds/refreshes), while different ids spread across a
/// handful of angles and a blue<->violet mix ratio so a grid of cards
/// doesn't look identical.
LinearGradient gradientForAlbumId(String albumId) {
  final hash = _stableHash(albumId);
  final alignmentIndex = hash % _beginAlignments.length;
  final mixPercent = (hash ~/ _beginAlignments.length) % 100;
  final mix = 0.15 + (mixPercent / 100) * 0.7; // spread within [0.15, 0.85]

  final colorA = Color.lerp(
    MemoraColors.glassBlue,
    MemoraColors.auraViolet,
    mix,
  )!;
  final colorB = Color.lerp(
    MemoraColors.auraViolet,
    MemoraColors.glassBlue,
    mix,
  )!;

  return LinearGradient(
    begin: _beginAlignments[alignmentIndex],
    end: _endAlignments[alignmentIndex],
    colors: [colorA, colorB],
  );
}
