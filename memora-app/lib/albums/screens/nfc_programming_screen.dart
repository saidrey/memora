import 'package:flutter/material.dart';

import '../albums_controller.dart';
import '../nfc_programming_controller.dart';
import '../nfc_programming_service.dart';
import '../sharing_models.dart';

/// spec09-programar-nfc.md: native NFC write flow for a single [NfcQrTag] —
/// opened from `AlbumDetailScreen`'s "Programar etiqueta NFC" button
/// (owner-only) right after `AlbumsController.createNfcQrTag(NfcQrTagType.nfc)`
/// creates the tag in the backend (P1). This screen never calls that API
/// itself — [tag] already exists by the time it's pushed, same as
/// `PhotoViewerScreen` receiving already-fetched data rather than fetching
/// its own.
///
/// A dedicated screen (not a dialog) because the flow has enough distinct
/// states — waiting for a tag, an overwrite confirmation that can arrive
/// mid-session, writing, verifying, success (with an optional follow-up
/// action), and five different error cases — to need its own `ChangeNotifier`
/// ([NfcProgrammingController]) driving a full-screen UI, per the checklist
/// in spec09 itself.
class NfcProgrammingScreen extends StatefulWidget {
  const NfcProgrammingScreen({
    super.key,
    required this.tag,
    required this.albumsController,
    this.service = const NfcProgrammingService(),
  });

  final NfcQrTag tag;

  /// Used ONLY for the "give up" path (P3): disabling this tag in the
  /// backend via the already-existing `AlbumsController.disableNfcQrTag`.
  /// This screen never creates or re-creates a tag itself.
  final AlbumsController albumsController;

  final NfcProgrammingService service;

  @override
  State<NfcProgrammingScreen> createState() => _NfcProgrammingScreenState();
}

class _NfcProgrammingScreenState extends State<NfcProgrammingScreen> {
  late final NfcProgrammingController _controller = NfcProgrammingController(
    widget.service,
    widget.tag,
  );

  /// Guards against showing the overwrite-confirmation dialog more than once
  /// for the same `confirmingOverwrite` state (a rebuild triggered by any
  /// other listener firing must not re-open it).
  bool _overwriteDialogShown = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
    _controller.start();
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    setState(() {});
    if (_controller.status == NfcProgrammingStatus.confirmingOverwrite) {
      if (!_overwriteDialogShown) {
        _overwriteDialogShown = true;
        _showOverwriteConfirmationDialog();
      }
    } else {
      _overwriteDialogShown = false;
    }
  }

  /// The tag already had NDEF content — spec09 requires explicit
  /// confirmation before overwriting it. Declining is treated as cancelling
  /// this attempt (see `NfcProgrammingController.resolveOverwriteConfirmation`'s
  /// doc comment).
  Future<void> _showOverwriteConfirmationDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('La etiqueta ya tiene datos'),
        content: const Text(
          'Esta etiqueta NFC ya contiene información grabada. Si continúas, '
          'se sobrescribirá y los datos anteriores se perderán.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sobrescribir'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    _controller.resolveOverwriteConfirmation(confirmed ?? false);
  }

  /// spec09's "Bloquear como solo lectura": a SEPARATE, explicit action
  /// (never automatic, never mixed with `disableNfcQrTag`'s backend
  /// soft-delete — P2) offered only after a successful write, and only where
  /// `NfcProgrammingController.supportsReadOnlyLock` is true (Android). The
  /// warning below is the "advierte que es IRREVERSIBLE" the spec requires.
  Future<void> _confirmLockReadOnly() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Bloquear como solo lectura'),
        content: const Text(
          'Esta acción es IRREVERSIBLE: la etiqueta quedará bloqueada para '
          'siempre y ninguna app (ni esta ni otra) podrá volver a escribir '
          'en ella. Seguirá abriendo el álbum normalmente al acercarla a un '
          'teléfono.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Bloquear definitivamente'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _controller.lockReadOnly();
  }

  /// P3: if the user desists after a write/verification failure (or any
  /// other error), offer to disable this tag's token in the backend — never
  /// automatic. Reuses `AlbumsController.disableNfcQrTag`, the same call
  /// spec07's "Bloquear" button on the tag card already uses; this is NOT a
  /// new endpoint or a new local action, just triggered from a different
  /// screen.
  Future<void> _giveUpAndDisable() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Deshabilitar esta etiqueta'),
        content: const Text(
          'El enlace creado para este intento dejará de funcionar. Puedes '
          'crear una etiqueta NFC nueva más tarde desde el álbum.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Deshabilitar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await widget.albumsController.disableNfcQrTag(widget.tag.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Programar etiqueta NFC')),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(child: _buildContent()),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    final controller = _controller;

    if (controller.isRunning) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.nfc, size: 64),
          const SizedBox(height: 16),
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(controller.statusMessage ?? '', textAlign: TextAlign.center),
          const SizedBox(height: 24),
          OutlinedButton(onPressed: controller.cancel, child: const Text('Cancelar')),
        ],
      );
    }

    if (controller.status == NfcProgrammingStatus.success) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 64),
          const SizedBox(height: 16),
          const Text(
            'Etiqueta programada correctamente.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          controller.supportsReadOnlyLock
              ? _buildLockSection()
              : const Text(
                  'El bloqueo a solo lectura no está disponible en iOS: '
                  'Core NFC no lo soporta de forma fiable en todos los '
                  'chips.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Listo'),
          ),
        ],
      );
    }

    // Every other terminal state is an error case or a cancellation — always
    // one of the specific messages from `statusMessage`, never a generic one
    // (spec09: "errores por caso, mensajes distintos y claros").
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.error_outline, color: Colors.red, size: 64),
        const SizedBox(height: 16),
        Text(
          controller.statusMessage ?? 'Ocurrió un error.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 12,
          alignment: WrapAlignment.center,
          children: [
            ElevatedButton(onPressed: controller.retry, child: const Text('Reintentar')),
            OutlinedButton(
              onPressed: _giveUpAndDisable,
              child: const Text('Deshabilitar etiqueta'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLockSection() {
    final controller = _controller;
    if (controller.lockedReadOnly) {
      return const Text(
        'Etiqueta bloqueada a solo lectura.',
        style: TextStyle(color: Colors.green),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (controller.lockReadOnlyErrorMessage != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              controller.lockReadOnlyErrorMessage!,
              style: const TextStyle(color: Colors.red, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
        OutlinedButton.icon(
          onPressed: controller.isLockingReadOnly ? null : _confirmLockReadOnly,
          icon: const Icon(Icons.lock_outline),
          label: Text(
            controller.isLockingReadOnly
                ? 'Bloqueando...'
                : 'Bloquear como solo lectura',
          ),
        ),
      ],
    );
  }
}
