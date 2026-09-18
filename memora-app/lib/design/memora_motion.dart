import 'package:flutter/material.dart';

/// Centralized motion system (durations, curves, stagger, and the single
/// "reduced motion" resolver) for every animation/transition in the app.
///
/// Before this file, `MemoraFadeSlideIn`, `MemoraCard`/`MemoraPrimaryButton`/
/// `MemoraSecondaryButton`'s press-scale, and every `flutter_animate` call
/// site each picked their own duration/curve constants and each re-derived
/// `MediaQuery.of(context).disableAnimations` on their own — consistent in
/// practice (all landed on similar numbers by feel) but with no single
/// source of truth, and any new screen had to guess. From now on: no bare
/// millisecond literal for an animation duration or a fresh
/// `MediaQuery...disableAnimations` check anywhere in `lib/` — reach for
/// [MemoraMotion] instead.
abstract final class MemoraMotion {
  /// Microinteractions: press-scale feedback, icon/label swaps inside a
  /// button, small state-to-state crossfades (e.g. a photo tile's
  /// loading -> error/image swap). Short enough to read as instantaneous
  /// feedback rather than a deliberate animation.
  static const quick = Duration(milliseconds: 150);

  /// Screen transitions, list/grid entrances, sheet content stagger,
  /// loading/error/content swaps at the screen level. Long enough to read
  /// as a deliberate motion without feeling sluggish.
  static const moderate = Duration(milliseconds: 300);

  /// Entrances — content arriving on screen (a route pushing in, a card
  /// fading/sliding into a list, a skeleton dissolving into real content).
  /// Starts slow, ends fast: reads as material settling into place.
  static const enterCurve = Curves.easeOutCubic;

  /// Exits — content leaving the screen (a route popping out, a state
  /// being swapped away by `AnimatedSwitcher`). Starts fast, ends slow: the
  /// mirror of [enterCurve], so a push/pop pair reads as one continuous
  /// motion rather than two unrelated animations.
  static const exitCurve = Curves.easeInCubic;

  /// Per-item delay for staggering a list/grid's entrance — item at
  /// [index] starts [step] after item `index - 1`, clamped to [maxIndex] so
  /// a long list doesn't force the last rows to wait through an
  /// ever-growing stagger before they even start animating in.
  static Duration stagger(
    int index, {
    Duration step = const Duration(milliseconds: 45),
    int maxIndex = 11,
  }) {
    return step * index.clamp(0, maxIndex).toDouble();
  }

  /// The single place that resolves the "reduce motion" accessibility
  /// setting. Every animation in `lib/` should gate itself through this
  /// (or through a widget — [MemoraFadeSlideIn], `MemoraCard`, etc. — that
  /// already does) instead of calling
  /// `MediaQuery.of(context).disableAnimations` directly, so the policy for
  /// "what counts as reduced motion" lives in exactly one place.
  static bool reduceMotion(BuildContext context) {
    return MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  }
}
