import 'package:flutter/material.dart';

import '../memora_colors.dart';
import '../memora_spacing.dart';

/// A centered loading state with the themed spinner and an optional label —
/// replaces bare `CircularProgressIndicator()` usages across the app.
///
/// **Light-first pivot**: [color] defaults to
/// [MemoraColors.glassBlueOnLight] (raw Glass Blue is too light to read as a
/// spinner stroke on the light canvas). The deliberate dark exception
/// (`photo_viewer_screen.dart`'s full-bleed dark viewer, and
/// `HomeScreen`'s connectivity indicator while the Welcome/hero photo is
/// showing) passes an explicit [color] override back to a light tone.
class MemoraLoadingState extends StatelessWidget {
  const MemoraLoadingState({
    super.key,
    this.label,
    this.compact = false,
    this.color,
  });

  final String? label;

  /// A small inline spinner (no padding/centering) for use next to other
  /// content, instead of taking over the whole available space.
  final bool compact;

  /// Explicit spinner-stroke color override — see the class doc.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final spinner = SizedBox(
      width: compact ? 16 : 28,
      height: compact ? 16 : 28,
      child: CircularProgressIndicator(
        strokeWidth: 2.5,
        color: color ?? MemoraColors.glassBlueOnLight,
      ),
    );

    if (compact) return spinner;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(MemoraSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            spinner,
            if (label != null) ...[
              const SizedBox(height: MemoraSpacing.md),
              Text(label!, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }
}
