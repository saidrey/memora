import 'package:flutter/material.dart';

import '../../design/design.dart';
import '../albums_controller.dart';

/// Create-album screen (spec04-ui-albumes.md, decision D): asks ONLY for a
/// name (≤100 chars) — visibility is never offered here, every new album is
/// born `PRIVATE` and changing it to `PUBLIC` is a separate, conscious
/// action later via the detail screen's (owner-only) edit action.
///
/// **Light-first pivot (60-30-10, sin spec de Kiro)**: this screen used to
/// wrap its form in `MemoraCardElevation.light` (a deliberate bright
/// exception against an otherwise dark app) with a hand-rolled
/// `InputDecoration` — the app-wide `InputDecorationTheme` was tuned for
/// text-on-dark and unreadable inside that one bright card. Now the whole
/// app is light-first, so the app-wide `InputDecorationTheme` itself is
/// light-canvas-calibrated and works here unmodified — the hand-rolled
/// decoration and the explicit Deep-Ink `.copyWith`s on every `Text` are
/// gone, both genuinely redundant now (the ambient `textTheme` already
/// defaults to Deep Ink). The card stays `level2` (a bit more "raised" than
/// the plain canvas) purely for a welcoming first-run feel, same reasoning
/// `AcceptInvitationScreen` already used. "Crear álbum" is the screen's only
/// `MemoraPrimaryButton`. Same controller/validation/loading/error logic as
/// before — nothing beyond the widget tree changed.
class CreateAlbumScreen extends StatefulWidget {
  const CreateAlbumScreen({super.key, required this.controller});

  final AlbumsController controller;

  @override
  State<CreateAlbumScreen> createState() => _CreateAlbumScreenState();
}

class _CreateAlbumScreenState extends State<CreateAlbumScreen> {
  final _nameController = TextEditingController();
  static const _maxNameLength = 100;

  /// Local flag, not `widget.controller.isMutating` directly: this screen
  /// never subscribed to the controller (no `addListener`/`ListenableBuilder`
  /// here — only the button's own `setState` calls drive its rebuilds), so
  /// `isMutating` flipping true/false mid-`await` wouldn't actually trigger
  /// a rebuild on its own. Without this, "Creando..." (and now the button's
  /// spinner) would never actually render — set right before the call and
  /// cleared in every exit path (see `_submit`).
  bool _submitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    final created = await widget.controller.createAlbum(_nameController.text);
    if (!mounted) return;
    if (created != null) {
      Navigator.of(context).pop(created);
    } else {
      setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final isNameEmpty = _nameController.text.trim().isEmpty;
    final isSubmitting = _submitting || controller.isMutating;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Crear álbum')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(MemoraSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MemoraCard(
                elevation: MemoraCardElevation.level2,
                borderRadius: MemoraRadius.hero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: MemoraColors.signatureGradient,
                      ),
                      child: const Icon(
                        Icons.photo_album_outlined,
                        color: MemoraColors.deepInk,
                      ),
                    ),
                    const SizedBox(height: MemoraSpacing.md),
                    Text('Nuevo álbum', style: textTheme.headlineSmall),
                    const SizedBox(height: MemoraSpacing.xs),
                    Text(
                      'Dale un nombre y podrás empezar a sumar fotos enseguida.',
                      style: textTheme.bodyMedium,
                    ),
                    const SizedBox(height: MemoraSpacing.lg),
                    TextField(
                      controller: _nameController,
                      maxLength: _maxNameLength,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Nombre del álbum',
                      ),
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => isSubmitting ? null : _submit(),
                    ),
                    if (controller.mutationErrorMessage != null) ...[
                      const SizedBox(height: MemoraSpacing.sm),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            size: 16,
                            color: MemoraColors.semanticError,
                          ),
                          const SizedBox(width: MemoraSpacing.xs),
                          Expanded(
                            child: Text(
                              controller.mutationErrorMessage!,
                              style: textTheme.bodySmall?.copyWith(
                                color: MemoraColors.semanticError,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: MemoraSpacing.lg),
              MemoraPrimaryButton(
                label: isSubmitting ? 'Creando...' : 'Crear álbum',
                icon: Icons.add,
                expand: true,
                loading: isSubmitting,
                onPressed: isSubmitting || isNameEmpty ? null : _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
