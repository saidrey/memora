import 'package:flutter/material.dart';

import '../memora_motion.dart';

/// A subtle fade + slide-up entrance, used for list/grid items appearing
/// on load (e.g. album cards). Respects [MemoraMotion.reduceMotion] (the
/// "reduce motion" accessibility setting): when set, the child appears
/// instantly with no animation at all.
///
/// Deliberately short ([MemoraMotion.moderate]) and small (12px slide) — an
/// entrance cue, not a demo animation.
class MemoraFadeSlideIn extends StatefulWidget {
  const MemoraFadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
  });

  final Widget child;

  /// Stagger delay before this item starts animating in — lets a list of
  /// these cascade in instead of all appearing at once.
  final Duration delay;

  @override
  State<MemoraFadeSlideIn> createState() => _MemoraFadeSlideInState();
}

class _MemoraFadeSlideInState extends State<MemoraFadeSlideIn> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      // Still defer to the next frame so the initial (invisible) frame has
      // a chance to render before animating in.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _visible = true);
      });
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) setState(() => _visible = true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (MemoraMotion.reduceMotion(context)) return widget.child;

    return AnimatedOpacity(
      opacity: _visible ? 1 : 0,
      duration: MemoraMotion.moderate,
      curve: MemoraMotion.enterCurve,
      child: AnimatedSlide(
        offset: _visible ? Offset.zero : const Offset(0, 0.04),
        duration: MemoraMotion.moderate,
        curve: MemoraMotion.enterCurve,
        child: widget.child,
      ),
    );
  }
}
