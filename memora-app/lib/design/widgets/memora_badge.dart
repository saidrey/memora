import 'package:flutter/material.dart';

import '../memora_colors.dart';
import '../memora_spacing.dart';

/// Visual variant of [MemoraBadge].
enum MemoraBadgeVariant {
  /// Muted surface-2 pill — the default, used for most metadata chips.
  neutral,

  /// Filled with the signature gradient — reserved for a badge meant to
  /// stand out (e.g. the "Owner" role badge that overflows an album card).
  gradient,
}

/// A small pill chip/badge — used for the album role ("Owner"/
/// "Colaborador"), the backend-connectivity indicator (with [dotColor]), and
/// a tag's status ("Activa"/"Bloqueada").
///
/// **Light-first pivot**: both variants now default to
/// [MemoraColors.deepInk] text (previously Paper, tuned for the dark
/// canvas). The one deliberate dark exception — the connectivity badge shown
/// over `HomeScreen`'s Welcome/hero photo — passes explicit
/// [backgroundColor]/[textColor]/[borderColor] overrides rather than
/// changing this widget's light-canvas default.
class MemoraBadge extends StatelessWidget {
  const MemoraBadge({
    super.key,
    required this.label,
    this.variant = MemoraBadgeVariant.neutral,
    this.dotColor,
    this.icon,
    this.backgroundColor,
    this.textColor,
    this.borderColor,
  });

  final String label;
  final MemoraBadgeVariant variant;

  /// An optional small status dot rendered before the label (e.g. green for
  /// "connected", red for "unavailable").
  final Color? dotColor;

  final IconData? icon;

  /// Overrides for the deliberate dark-canvas exception (a badge composited
  /// over a photo/scrim) — leave null everywhere else. Ignored for
  /// [MemoraBadgeVariant.gradient] (its gradient fill/Deep Ink text is
  /// unaffected by canvas brightness).
  final Color? backgroundColor;
  final Color? textColor;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final isGradient = variant == MemoraBadgeVariant.gradient;
    final resolvedTextColor =
        textColor ?? MemoraColors.deepInk;
    final style = Theme.of(
      context,
    ).textTheme.labelMedium?.copyWith(color: resolvedTextColor, height: 1);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: MemoraSpacing.sm + 2,
        vertical: MemoraSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: isGradient ? null : (backgroundColor ?? MemoraColors.mist),
        gradient: isGradient ? MemoraColors.signatureGradient : null,
        borderRadius: BorderRadius.circular(999),
        border: isGradient
            ? null
            : Border.all(color: borderColor ?? MemoraColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dotColor != null) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dotColor,
              ),
            ),
            const SizedBox(width: MemoraSpacing.xs),
          ],
          if (icon != null) ...[
            Icon(icon, size: 12, color: resolvedTextColor),
            const SizedBox(width: MemoraSpacing.xs),
          ],
          Text(label, style: style),
        ],
      ),
    );
  }
}
