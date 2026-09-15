import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

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
Future<bool> promptDriveReconnect(
  BuildContext context,
  AuthController authController,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Reconectar Google Drive'),
      content: const Text(
        'Hace falta volver a autorizar el acceso a Google Drive para '
        'continuar. Se abrirá el selector de cuentas de Google; tu sesión '
        'en Memora no se cierra en ningún momento de este proceso.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancelar'),
        ),
        TextButton(
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
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 16),
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
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  return succeeded;
}
