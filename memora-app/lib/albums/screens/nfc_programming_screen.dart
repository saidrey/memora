import 'package:flutter/material.dart';

import '../../design/design.dart';
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
///
/// Restyled in Fase 2 del rediseño "Aurora" (sin spec de Kiro), then
/// revisited in the light-first pivot (60-30-10): every state keeps its own
/// distinct icon/message exactly as before (no state was dropped), now built
/// from the system's components — [_StateIconChip]/`MemoraLoadingState`
/// while running, [_StateIconChip]/`MemoraSecondaryButton` for
/// cancelled/error, and — this screen's one deliberate dark-accent moment —
/// the success state wrapped in a `MemoraCardElevation.ink` card, the
/// "reward" beat for finishing the physical write. Under the old dark-first
/// system this was the bright `.light` exception against an otherwise dark
/// app; under light-first it flips to a bold black card against the
/// otherwise-light screen — same "protagonist accent" idea, mirrored.
/// `NfcProgrammingController`'s states/transitions are untouched.
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

  /// Local double-submit guard + spinner flag for "Deshabilitar etiqueta"
  /// (`_giveUpAndDisable`) — this screen never subscribes to
  /// `widget.albumsController`, so its `isMutating` alone wouldn't trigger a
  /// rebuild here (same reasoning as `CreateAlbumScreen._submitting`).
  bool _disabling = false;

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
            style: TextButton.styleFrom(
              foregroundColor: MemoraColors.semanticError,
            ),
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
            style: TextButton.styleFrom(
              foregroundColor: MemoraColors.semanticError,
            ),
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
            style: TextButton.styleFrom(
              foregroundColor: MemoraColors.semanticError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Deshabilitar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _disabling = true);
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
            padding: const EdgeInsets.all(MemoraSpacing.lg),
            child: SingleChildScrollView(child: _buildContent()),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    final controller = _controller;
    final textTheme = Theme.of(context).textTheme;

    if (controller.isRunning) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _StateIconChip(icon: Icons.nfc),
          const SizedBox(height: MemoraSpacing.xl),
          MemoraLoadingState(label: controller.statusMessage),
          const SizedBox(height: MemoraSpacing.xl),
          MemoraSecondaryButton(
            label: 'Cancelar',
            icon: Icons.close,
            onPressed: controller.cancel,
          ),
        ],
      );
    }

    if (controller.status == NfcProgrammingStatus.success) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MemoraCard(
            elevation: MemoraCardElevation.ink,
            borderRadius: MemoraRadius.hero,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: MemoraColors.signatureGradient,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    size: 32,
                    color: MemoraColors.deepInk,
                  ),
                ),
                const SizedBox(height: MemoraSpacing.md),
                // Explicit Paper: `.ink`'s dark background needs light text,
                // and every `textTheme.*` style already hardcodes its own
                // (now Deep-Ink-family) color that wins over `.ink`'s
                // ambient `DefaultTextStyle` fallback — same gotcha as the
                // old `.light` variant, mirrored.
                Text(
                  'Etiqueta programada',
                  textAlign: TextAlign.center,
                  style: textTheme.headlineSmall?.copyWith(
                    color: MemoraColors.paper,
                  ),
                ),
                const SizedBox(height: MemoraSpacing.xs),
                Text(
                  'Se escribió y verificó correctamente.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(
                    color: MemoraColors.paper.withValues(alpha: 0.7),
                  ),
                ),
                if (!controller.supportsReadOnlyLock) ...[
                  const SizedBox(height: MemoraSpacing.lg),
                  Text(
                    'El bloqueo a solo lectura no está disponible en '
                    'iOS: Core NFC no lo soporta de forma fiable en '
                    'todos los chips.',
                    textAlign: TextAlign.center,
                    style: textTheme.bodySmall?.copyWith(
                      color: MemoraColors.paper.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // `_buildLockSection` renders a `MemoraSecondaryButton` — its
          // foreground now defaults to `MemoraColors.deepInk` (the
          // light-canvas default, see the widget's own doc comment), which
          // would be unreadable nested inside the dark `.ink` card above.
          // Kept below the card, on the screen's normal light canvas, where
          // that default reads correctly — same reason
          // `MemoraPrimaryButton`/`MemoraSecondaryButton` never appear
          // inside `create_album_screen.dart`'s card either (there for a
          // different reason: the "one CTA per screen" rule).
          if (controller.supportsReadOnlyLock) ...[
            const SizedBox(height: MemoraSpacing.lg),
            _buildLockSection(),
          ],
          const SizedBox(height: MemoraSpacing.lg),
          MemoraPrimaryButton(
            label: 'Listo',
            expand: true,
            onPressed: () => Navigator.of(context).pop(),
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
        const _StateIconChip(
          icon: Icons.error_outline,
          color: MemoraColors.semanticError,
        ),
        const SizedBox(height: MemoraSpacing.lg),
        Text(
          controller.statusMessage ?? 'Ocurrió un error.',
          textAlign: TextAlign.center,
          style: textTheme.bodyMedium,
        ),
        const SizedBox(height: MemoraSpacing.xl),
        MemoraPrimaryButton(
          label: 'Reintentar',
          icon: Icons.refresh,
          expand: true,
          onPressed: controller.retry,
        ),
        const SizedBox(height: MemoraSpacing.sm),
        MemoraSecondaryButton(
          label: 'Deshabilitar etiqueta',
          icon: Icons.block,
          destructive: true,
          expand: true,
          loading: _disabling,
          onPressed: _disabling ? null : _giveUpAndDisable,
        ),
      ],
    );
  }

  Widget _buildLockSection() {
    final controller = _controller;
    final textTheme = Theme.of(context).textTheme;

    if (controller.lockedReadOnly) {
      return MemoraBadge(
        label: 'Bloqueada a solo lectura',
        dotColor: MemoraColors.semanticSuccess,
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (controller.lockReadOnlyErrorMessage != null)
          Padding(
            padding: const EdgeInsets.only(bottom: MemoraSpacing.sm),
            child: Text(
              controller.lockReadOnlyErrorMessage!,
              style: textTheme.bodySmall?.copyWith(
                color: MemoraColors.semanticError,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        MemoraSecondaryButton(
          label: controller.isLockingReadOnly
              ? 'Bloqueando...'
              : 'Bloquear como solo lectura',
          icon: Icons.lock_outline,
          loading: controller.isLockingReadOnly,
          onPressed: controller.isLockingReadOnly ? null : _confirmLockReadOnly,
        ),
      ],
    );
  }
}

/// A circular icon chip echoing the same motif already used elsewhere in the
/// design system (`_QuickAccessCard`'s icon chip, `_InitialsAvatar`, the
/// FAB) — a tinted circle around a single icon — reused here for this
/// screen's waiting/running state ([color] defaults to the signature
/// gradient's blue) and its error/cancelled state ([color] passed as
/// [MemoraColors.semanticError]), instead of a bare, un-styled `Icon`.
class _StateIconChip extends StatelessWidget {
  const _StateIconChip({
    required this.icon,
    // Raw glassBlue is too light against this tinted circle on the light
    // canvas — see MemoraColors.glassBlueOnLight.
    this.color = MemoraColors.glassBlueOnLight,
  });

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      height: 88,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.14),
      ),
      child: Icon(icon, size: 40, color: color),
    );
  }
}
