import 'package:flutter/material.dart';

import '../memora_colors.dart';
import '../memora_motion.dart';
import '../memora_spacing.dart';

/// A secondary/outlined pill action — used for every action that isn't the
/// single primary CTA of a screen (e.g. "Cerrar sesión", "Reintentar").
///
/// **Light-first pivot**: the non-destructive default foreground flipped
/// from [MemoraColors.paper] to [MemoraColors.deepInk] — the app's canvas is
/// Paper now, so a paper-colored label/border would be invisible almost
/// everywhere. The one deliberate dark exception
/// (`photo_viewer_screen.dart`'s full-bleed dark viewer) passes an explicit
/// [color] override back to Paper — same mechanic as the rest of this
/// system's dark-exception overrides. The mirror of the old gotcha applies
/// now: never nest this button inside a `MemoraCardElevation.ink` card
/// without an explicit `color: MemoraColors.paper` override (its default
/// Deep Ink would be invisible on that dark background).
class MemoraSecondaryButton extends StatefulWidget {
  const MemoraSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = false,
    this.destructive = false,
    this.color,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;

  /// Same meaning as `MemoraPrimaryButton.loading` — see its doc comment.
  /// While `true`, [icon] (if any) is replaced by a small spinner in the
  /// button's own foreground color and taps are blocked.
  final bool loading;

  /// Renders the border/label in the semantic error color, for actions like
  /// "Eliminar álbum". Ignored when [color] is set.
  final bool destructive;

  /// Explicit foreground override — for the deliberate dark-canvas
  /// exceptions (pass [MemoraColors.paper]). Leave null everywhere else;
  /// the default (Deep Ink, or the semantic error color when [destructive])
  /// is correct for the light canvas.
  final Color? color;

  @override
  State<MemoraSecondaryButton> createState() => _MemoraSecondaryButtonState();
}

/// Same "scale down while held" micro-interaction as `MemoraPrimaryButton`
/// (see its doc comment) — `StatefulWidget` only to track [_pressed] via
/// `InkWell`'s own `onTapDown`/`onTapUp`/`onTapCancel`.
class _MemoraSecondaryButtonState extends State<MemoraSecondaryButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final tapEnabled = widget.onPressed != null && !widget.loading;
    final visuallyDisabled = widget.onPressed == null && !widget.loading;
    final color =
        widget.color ??
        (widget.destructive
            ? MemoraColors.semanticError
            : MemoraColors.deepInk);
    final reduceMotion = MemoraMotion.reduceMotion(context);

    final content = Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.loading) ...[
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(width: MemoraSpacing.sm),
        ] else if (widget.icon != null) ...[
          Icon(widget.icon, size: 18, color: color),
          const SizedBox(width: MemoraSpacing.sm),
        ],
        Flexible(
          child: Text(
            widget.label,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: color),
          ),
        ),
      ],
    );

    return Opacity(
      opacity: visuallyDisabled ? 0.45 : 1,
      child: AnimatedScale(
        scale: (!reduceMotion && _pressed) ? 0.96 : 1,
        duration: MemoraMotion.quick,
        curve: MemoraMotion.enterCurve,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            onTap: tapEnabled ? widget.onPressed : null,
            onTapDown: tapEnabled ? (_) => _setPressed(true) : null,
            onTapUp: tapEnabled ? (_) => _setPressed(false) : null,
            onTapCancel: tapEnabled ? () => _setPressed(false) : null,
            borderRadius: BorderRadius.circular(999),
            splashColor: color.withValues(alpha: 0.12),
            highlightColor: color.withValues(alpha: 0.08),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: widget.destructive
                      ? MemoraColors.semanticError.withValues(alpha: 0.5)
                      // An explicit `color` override means a dark-canvas
                      // exception (see the class doc) — `MemoraColors.border`
                      // (Deep Ink at low opacity) would be invisible there,
                      // so derive the border from the override color itself
                      // instead.
                      : (widget.color?.withValues(alpha: 0.5) ??
                            MemoraColors.border),
                ),
                borderRadius: BorderRadius.circular(999),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: MemoraSpacing.lg,
                vertical: MemoraSpacing.md,
              ),
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}
