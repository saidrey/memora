import 'package:flutter/material.dart';

import '../memora_colors.dart';
import '../memora_motion.dart';
import '../memora_spacing.dart';

/// The app's primary CTA: a full pill filled with the signature gradient
/// (Glass Blue -> Aura Violet, 135°). Reserved for the single most
/// important action on a screen (e.g. "Iniciar sesión con Google",
/// "Crear álbum") — never used more than once per screen.
class MemoraPrimaryButton extends StatefulWidget {
  const MemoraPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = false,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// Whether the button should fill the width available to it.
  final bool expand;

  /// Whether an async action triggered by this button is in flight. While
  /// `true`: the [icon] (if any) is replaced by a small spinner (the label
  /// stays visible, so the button still reads as "doing X" rather than a
  /// generic busy state), and taps are blocked — the same mechanism screens
  /// already use for double-submit protection (`controller.isMutating` fed
  /// into [onPressed]), just made visible on the button itself instead of
  /// only disabling it silently.
  final bool loading;

  @override
  State<MemoraPrimaryButton> createState() => _MemoraPrimaryButtonState();
}

/// A `StatefulWidget` (not stateless) only to track [_pressed] — driving a
/// subtle scale-down while the pill is held, on top of `InkWell`'s ripple
/// (the "más dinamismo" feedback the user asked for on real device, not just
/// the default Material ripple). `InkWell` already exposes
/// `onTapDown`/`onTapUp`/`onTapCancel`, so this doesn't need a second
/// `GestureDetector` racing it for the same pointer.
class _MemoraPrimaryButtonState extends State<MemoraPrimaryButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final tapEnabled = widget.onPressed != null && !widget.loading;
    final visuallyDisabled = widget.onPressed == null && !widget.loading;
    final reduceMotion = MemoraMotion.reduceMotion(context);

    final content = Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.loading) ...[
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(MemoraColors.deepInk),
            ),
          ),
          const SizedBox(width: MemoraSpacing.sm),
        ] else if (widget.icon != null) ...[
          Icon(widget.icon, size: 18, color: MemoraColors.deepInk),
          const SizedBox(width: MemoraSpacing.sm),
        ],
        Flexible(
          child: Text(
            widget.label,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: MemoraColors.deepInk),
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
            splashColor: MemoraColors.deepInk.withValues(alpha: 0.12),
            highlightColor: MemoraColors.deepInk.withValues(alpha: 0.08),
            child: Ink(
              decoration: const BoxDecoration(
                gradient: MemoraColors.signatureGradient,
                borderRadius: BorderRadius.all(Radius.circular(999)),
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
