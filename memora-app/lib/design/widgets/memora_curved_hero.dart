import 'package:flutter/material.dart';

/// Asymmetric wave clip for a hero image's bottom edge — the "editorial
/// gallery" seam between a protagonist photo and the content below, used
/// instead of a straight rectangular cut or a centered/symmetric arc.
/// Deliberately a shallow, understated trough (not a scalloped/decorative
/// shape) so it reads as an intentional curve rather than a flourish —
/// meant to be used sparingly (one hero moment per screen), same criterion
/// as the signature gradient / the overflowing badge motif elsewhere in
/// this design system.
class MemoraHeroCurve extends CustomClipper<Path> {
  const MemoraHeroCurve();

  @override
  Path getClip(Size size) {
    final path = Path()..lineTo(0, size.height * 0.88);
    path.quadraticBezierTo(
      size.width * 0.30,
      size.height,
      size.width * 0.60,
      size.height * 0.90,
    );
    path.quadraticBezierTo(
      size.width * 0.82,
      size.height * 0.82,
      size.width,
      size.height * 0.92,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  // Always `true`, not `false`: this clip only ever looked "safe" to skip
  // recomputing because a static screen never resizes after first layout.
  // A `Hero` flight (see the album-list<->album-detail transition, "pasada
  // de dinamismo" sin spec de Kiro) resizes whatever it's wrapping every
  // animation frame via an interpolated `Rect` — if the Hero's flying child
  // were ever nested *inside* this clip, a `false` here would freeze the
  // wave path at its first-computed size while the surrounding box kept
  // growing/shrinking, producing a stretched/misplaced curve mid-flight.
  // `getClip` here is cheap (a couple of quadratic Bezier segments), so
  // recomputing every layout has no measurable cost — kept `true`
  // unconditionally rather than trying to diff `oldClipper` (this class has
  // no fields to compare, and it's `const`, so identity alone tells us
  // nothing about whether the *size* changed).
  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => true;
}

/// A full-bleed hero image (or gradient) with the [MemoraHeroCurve] bottom
/// edge and an optional overlay (e.g. a bottom scrim + title) stacked on
/// top — used by the album-detail hero (Fase 2 del rediseño) and any future
/// image-led hero moment. [background] fills the whole clipped area
/// ([BoxFit.cover] is the caller's responsibility, same as any full-bleed
/// image); [overlay] renders above it and shares the same clip (there's no
/// way to exempt just the overlay from it), so keep any interactive control
/// inside [overlay] within the flat (non-curved) top ~85% of [height] —
/// anything placed lower risks being clipped away at the wavy bottom edge.
class MemoraCurvedHero extends StatelessWidget {
  const MemoraCurvedHero({
    super.key,
    required this.height,
    required this.background,
    this.overlay,
  });

  final double height;
  final Widget background;
  final Widget? overlay;

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: const MemoraHeroCurve(),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(fit: StackFit.expand, children: [background, ?overlay]),
      ),
    );
  }
}
