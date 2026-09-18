import 'package:flutter/material.dart';

import 'memora_motion.dart';

/// The app's standard screen transition: a directional slide + fade,
/// forward on push. Flutter mirrors this automatically on pop (the same
/// `transitionsBuilder` runs with the animation running in reverse), so
/// there's no separate "reverse transition" to author.
///
/// The app doesn't use `go_router` (or any routing package) — navigation is
/// plain `Navigator.of(context).push`/`pushReplacement` with
/// `MaterialPageRoute` builders throughout. This is a drop-in replacement
/// for `MaterialPageRoute` for exactly that reason: same constructor shape
/// (`builder`, plus the handful of `PageRoute` knobs screens already rely on
/// — `settings`, `fullscreenDialog`), so every existing call site only needs
/// its `MaterialPageRoute(builder: ...)` swapped for
/// `MemoraPageRoute(builder: ...)`.
///
/// Respects reduced motion ([MemoraMotion.reduceMotion]): when active, the
/// transition collapses to an instant cut (zero-duration, no slide/fade) —
/// same policy every other animation in `lib/design/` follows.
class MemoraPageRoute<T> extends PageRouteBuilder<T> {
  MemoraPageRoute({
    required WidgetBuilder builder,
    super.settings,
    super.fullscreenDialog,
  }) : super(
         pageBuilder: (context, animation, secondaryAnimation) =>
             builder(context),
         transitionDuration: MemoraMotion.moderate,
         reverseTransitionDuration: MemoraMotion.moderate,
         transitionsBuilder: (context, animation, secondaryAnimation, child) {
           if (MemoraMotion.reduceMotion(context)) return child;

           // Incoming route: slides up from ~4% of the screen height while
           // fading in, eased with the shared enter curve.
           final enter = CurvedAnimation(
             parent: animation,
             curve: MemoraMotion.enterCurve,
             reverseCurve: MemoraMotion.exitCurve,
           );
           // Outgoing route (the screen being pushed away from, when a new
           // one is pushed on top): a very subtle fade + settle, so the
           // incoming screen reads as the thing in motion, not a swap of
           // two equally-animated layers.
           final exit = CurvedAnimation(
             parent: secondaryAnimation,
             curve: MemoraMotion.enterCurve,
             reverseCurve: MemoraMotion.exitCurve,
           );

           return FadeTransition(
             opacity: Tween<double>(begin: 0, end: 1).animate(enter),
             child: SlideTransition(
               position: Tween<Offset>(
                 begin: const Offset(0, 0.04),
                 end: Offset.zero,
               ).animate(enter),
               child: FadeTransition(
                 opacity: Tween<double>(begin: 1, end: 0.92).animate(exit),
                 child: child,
               ),
             ),
           );
         },
       );
}
