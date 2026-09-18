import 'package:flutter/material.dart';

import '../memora_colors.dart';
import '../memora_motion.dart';
import '../memora_spacing.dart';

/// Which layered surface tone a [MemoraCard] sits on.
///
/// **Light-first pivot**: under the old dark-first system, `level1`/`level2`
/// were dark surfaces and `light` (Paper) was the rare "light island"
/// exception. Now the canvas itself is Paper, so a bright card is no longer
/// special — `level1`/`level2` ARE the light surfaces, and the roles flip:
/// the rare, deliberate exception is now a DARK card (`ink`), reserved for
/// the handful of protagonist accent moments the 60-30-10 pivot calls for
/// (e.g. a "reward" state screen wants a bold black card instead of yet
/// another light one — see `nfc_programming_screen.dart`'s success state).
enum MemoraCardElevation {
  /// [MemoraColors.surface1] — the default, most common card surface (a
  /// soft, barely-tinted off-white).
  level1,

  /// [MemoraColors.surface2] — a card that should read as raised further
  /// (e.g. a bigger section container, or a standout summary tile).
  level2,

  /// [MemoraColors.deepInk] background with content defaulting to
  /// [MemoraColors.paper] — the 10% dark-accent "protagonist" surface the
  /// 60-30-10 pivot calls for. Use it sparingly, for the one or two
  /// moments on a screen that should read as a bold, deliberate dark
  /// accent — never as a second default alongside level1/level2, and never
  /// as a full-screen background.
  ink,
}

/// The base card used across the app: a rounded, softly-bordered surface.
/// Screens compose their own content inside it rather than styling
/// `Container`s ad hoc.
///
/// `StatefulWidget` only to drive a subtle press-scale when [onTap] is set
/// (a tappable card should feel pressed, not just show the default Material
/// ripple).
class MemoraCard extends StatefulWidget {
  const MemoraCard({
    super.key,
    required this.child,
    this.elevation = MemoraCardElevation.level1,
    this.padding = const EdgeInsets.all(MemoraSpacing.md),
    this.borderRadius = 20,
    this.onTap,
    this.gradient,
  });

  final Widget child;
  final MemoraCardElevation elevation;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final VoidCallback? onTap;

  /// Optional flat-fill override — overrides the elevation's surface color
  /// when set. Kept for flexibility even though no current screen uses a
  /// full-gradient-fill card anymore (the album-list cards moved to a
  /// gradient BORDER instead — see `album_card_style.dart` and
  /// `albums_list_screen.dart`'s `_AlbumGridCard`).
  final Gradient? gradient;

  @override
  State<MemoraCard> createState() => _MemoraCardState();
}

class _MemoraCardState extends State<MemoraCard> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final isInk = widget.elevation == MemoraCardElevation.ink;
    final color = switch (widget.elevation) {
      MemoraCardElevation.level1 => MemoraColors.surface1,
      MemoraCardElevation.level2 => MemoraColors.surface2,
      MemoraCardElevation.ink => MemoraColors.deepInk,
    };

    final decoration = BoxDecoration(
      color: widget.gradient == null ? color : null,
      gradient: widget.gradient,
      borderRadius: BorderRadius.circular(widget.borderRadius),
      // `MemoraColors.border` (Deep Ink at low opacity) is calibrated for
      // the light canvas — nearly invisible against a dark `ink` card, which
      // needs its own light-on-dark border tone instead.
      border: Border.all(
        color: isInk
            ? MemoraColors.paper.withValues(alpha: 0.14)
            : MemoraColors.border,
      ),
    );

    Widget content = Container(
      padding: widget.padding,
      decoration: decoration,
      child: widget.child,
    );

    if (isInk) {
      // Fallback default for style-less Text/bare Icon children — matches
      // the contrast this surface exists for (Paper on Deep Ink is ~19:1,
      // comfortably AA/AAA). NOTE: every `MemoraTypography`/`textTheme.*`
      // style already hardcodes its own color (tuned for the light canvas,
      // which is the vast majority of the app now), and
      // `TextStyle.merge`/`Text.style` lets an explicit color win over this
      // ambient default — so a `Text(x, style: textTheme.bodyMedium)` child
      // still needs `?.copyWith(color: MemoraColors.paper)` at the call
      // site. This only saves that for children that pass no style/color at
      // all. Same mechanic as the old `MemoraCardElevation.light`'s gotcha,
      // just mirrored.
      content = DefaultTextStyle.merge(
        style: const TextStyle(color: MemoraColors.paper),
        child: IconTheme.merge(
          data: const IconThemeData(color: MemoraColors.paper),
          child: content,
        ),
      );
    }

    if (widget.onTap == null) return content;

    final reduceMotion = MemoraMotion.reduceMotion(context);

    return AnimatedScale(
      scale: (!reduceMotion && _pressed) ? 0.97 : 1,
      duration: MemoraMotion.quick,
      curve: MemoraMotion.enterCurve,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: InkWell(
          onTap: widget.onTap,
          onTapDown: (_) => _setPressed(true),
          onTapUp: (_) => _setPressed(false),
          onTapCancel: () => _setPressed(false),
          borderRadius: BorderRadius.circular(widget.borderRadius),
          child: content,
        ),
      ),
    );
  }
}
