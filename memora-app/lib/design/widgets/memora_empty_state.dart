import 'package:flutter/material.dart';

import '../memora_colors.dart';
import '../memora_spacing.dart';
import 'memora_primary_button.dart';

/// A centered empty state: either an icon in a soft gradient-tinted circle,
/// or a custom illustration ([imageAsset]) — a title, an optional subtitle,
/// and an optional primary call to action (e.g. "todavía no tienes álbumes"
/// -> "Crear álbum").
///
/// **Ajuste post-feedback (sin spec de Kiro)**: `AlbumsListScreen`'s empty
/// state moved from the generic icon to a real illustration
/// (`assets/images/empty.png`, provided by the user) — `imageAsset` was
/// added as an alternative to [icon] rather than replacing it, since every
/// other call site (`album_detail_screen.dart`'s two empty states) still
/// wants the lightweight icon-in-a-circle treatment. Exactly one of
/// [icon]/[imageAsset] should be passed; if both are, [imageAsset] wins
/// (kept permissive — an assert would be one more way for an unrelated
/// future change to crash a screen it didn't touch).
class MemoraEmptyState extends StatelessWidget {
  const MemoraEmptyState({
    super.key,
    this.icon,
    this.imageAsset,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  }) : assert(
         icon != null || imageAsset != null,
         'MemoraEmptyState needs either an icon or an imageAsset.',
       );

  /// Shown inside a soft gradient-tinted circle when [imageAsset] is null.
  final IconData? icon;

  /// A custom illustration asset path (e.g. `assets/images/empty.png`) shown
  /// instead of [icon] when set — sized moderately (not full-bleed: this is
  /// an illustration, not a hero), with air around it.
  final String? imageAsset;

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(MemoraSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (imageAsset != null)
              Image.asset(imageAsset!, width: 220, fit: BoxFit.contain)
            else
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      MemoraColors.glassBlue.withValues(alpha: 0.18),
                      MemoraColors.auraViolet.withValues(alpha: 0.18),
                    ],
                  ),
                ),
                // Raw glassBlue is too light against this soft tinted circle
                // on the light canvas — see MemoraColors.glassBlueOnLight.
                child: Icon(icon, size: 32, color: MemoraColors.glassBlueOnLight),
              ),
            const SizedBox(height: MemoraSpacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: textTheme.headlineSmall,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: MemoraSpacing.sm),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium,
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: MemoraSpacing.lg),
              MemoraPrimaryButton(label: actionLabel!, onPressed: onAction),
            ],
          ],
        ),
      ),
    );
  }
}
