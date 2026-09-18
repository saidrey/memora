import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import '../design/design.dart';
import 'auth_controller.dart';

/// Reusable "reconectar Google Drive" flow (spec06-sesion-y-reauth-drive.md,
/// A1.6): explains why it's needed, runs [AuthController.reconnectDrive] on
/// confirmation with a loading state, and returns whether it succeeded.
///
/// Used from every place that detects a `DRIVE_REAUTHORIZATION_REQUIRED`
/// failure without offering an action yet — today, the photo-upload batch
/// (`PhotoUploadController`) and album thumbnails (`DriveThumbnailService`
/// via `AlbumDetailScreen`). Never touches the app session: cancelling or
/// failing leaves it completely intact (D10), same guarantee
/// `AuthController.reconnectDrive` itself makes.
///
/// No `TextField` involved, so the `autofocus: true` dialog-crash gotcha
/// (see CLAUDE.md) doesn't apply here — noted for whoever adds the next
/// dialog with one.
///
/// Restyled in Fase 2 del rediseño "Aurora" (sin spec de Kiro): all three
/// `showDialog`/`SnackBar` calls already inherit most of their look from
/// `MemoraTheme.dark`'s `dialogTheme`/`snackBarTheme` (surface-2 background,
/// themed title/content text, rounded corners) — no explicit color plumbing
/// needed there, unlike screens that build their own `Container`s from
/// scratch. What changed: a leading icon on the confirm dialog's title (the
/// system's icon-chip language, dialed down to fit a title row instead of a
/// full circle chip) and a clear weight difference between its two actions
/// (muted "Cancelar" vs. accented "Reconectar" — same "no two actions with
/// equal weight" criterion used everywhere else in this pass), plus a
/// result icon on the closing `SnackBar` instead of bare text.
Future<bool> promptDriveReconnect(
  BuildContext context,
  AuthController authController,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      // glassBlueOnLight, not raw glassBlue: this dialog now sits on the
      // light canvas (dialogTheme's surface2/Mist background) — see
      // MemoraColors.glassBlueOnLight's doc comment.
      title: const Row(
        children: [
          Icon(
            Icons.cloud_sync_outlined,
            size: 20,
            color: MemoraColors.glassBlueOnLight,
          ),
          SizedBox(width: MemoraSpacing.sm),
          Flexible(child: Text('Reconectar Google Drive')),
        ],
      ),
      content: const Text(
        'Hace falta volver a autorizar el acceso a Google Drive para '
        'continuar. Se abrirá el selector de cuentas de Google; tu sesión '
        'en Memora no se cierra en ningún momento de este proceso.',
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(
            foregroundColor: MemoraColors.textSecondary,
          ),
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancelar'),
        ),
        TextButton(
          style: TextButton.styleFrom(
            foregroundColor: MemoraColors.glassBlueOnLight,
          ),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Reconectar'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return false;

  // Non-dismissible: reconnecting is a short, single interactive step (the
  // Google account picker) — letting the user dismiss this mid-flight would
  // leave no way to observe the result.
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            MemoraLoadingState(compact: true),
            SizedBox(width: MemoraSpacing.md),
            Text('Reconectando Google Drive...'),
          ],
        ),
      ),
    ),
  );

  final succeeded = await authController.reconnectDrive();

  if (!context.mounted) return succeeded;
  Navigator.of(context, rootNavigator: true).pop();

  final message = succeeded
      ? 'Google Drive reconectado.'
      : authController.driveReconnectErrorMessage ??
            'No se pudo reconectar Google Drive.';
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Icon(
            succeeded ? Icons.check_circle_outline : Icons.error_outline,
            size: 20,
            color: succeeded
                ? MemoraColors.semanticSuccess
                : MemoraColors.semanticError,
          ),
          const SizedBox(width: MemoraSpacing.sm),
          Expanded(child: Text(message)),
        ],
      ),
    ),
  );

  return succeeded;
}
