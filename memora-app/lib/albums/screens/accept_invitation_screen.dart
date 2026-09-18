import 'package:flutter/material.dart';

import '../../auth/auth_controller.dart';
import '../../design/design.dart';
import '../../photos/photo_upload_controller.dart';
import '../albums_controller.dart';
import '../drive_thumbnail_service.dart';
import 'albums_list_screen.dart';

/// Full screen (spec05-ui-colaboradores.md) to accept an album invitation by
/// pasting either the full invitation URL or just its token — deep-linking
/// is deliberately deferred (spec's own recommendation: "validar el flujo
/// de aceptar primero"), so this manual-entry screen is the whole "invitado
/// abre el enlace" flow for this corte. Reached only from `HomeScreen` when
/// the user is already authenticated (accepting requires a session).
///
/// A real `Navigator.push` screen, not a `showDialog` — so, unlike the
/// rename-album dialog, `autofocus: true` on the `TextField` below is safe
/// here (the crash documented in CLAUDE.md is specific to a `TextField`
/// living inside `showDialog`, where a dismissed barrier/immediate pop can
/// outlive a pending focus request).
///
/// Restyled in Fase 2 del rediseño "Aurora" (sin spec de Kiro): the
/// instructions/input live inside a `MemoraCard` (level2, no light-card
/// moment on this screen — unlike `create_album_screen.dart` there's no
/// obvious "reward" beat here to justify one, joining an album is a
/// single-step utility action), with the app-wide `InputDecorationTheme`
/// used as-is (unlike the create-album field, this card stays on the dark
/// surfaces the theme is already tuned for). "Aceptar" is the screen's one
/// `MemoraPrimaryButton`. Same controller wiring/logic as before.
class AcceptInvitationScreen extends StatefulWidget {
  const AcceptInvitationScreen({
    super.key,
    required this.controller,
    required this.photoUploadController,
    required this.driveThumbnailService,
    required this.authController,
  });

  final AlbumsController controller;
  final PhotoUploadController photoUploadController;
  final DriveThumbnailService driveThumbnailService;
  final AuthController authController;

  @override
  State<AcceptInvitationScreen> createState() => _AcceptInvitationScreenState();
}

class _AcceptInvitationScreenState extends State<AcceptInvitationScreen> {
  final _inputController = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _inputController.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  Future<void> _accept() async {
    final input = _inputController.text.trim();
    if (input.isEmpty) return;

    final succeeded = await widget.controller.acceptInvitation(input);
    if (!mounted || !succeeded) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Te uniste al álbum.')));
    // Replace this screen with the (freshly reloaded) albums list so the
    // user immediately sees the album they just joined, per spec05's
    // "verlo en su lista" requirement.
    Navigator.of(context).pushReplacement(
      MemoraPageRoute(
        builder: (_) => AlbumsListScreen(
          controller: widget.controller,
          photoUploadController: widget.photoUploadController,
          driveThumbnailService: widget.driveThumbnailService,
          authController: widget.authController,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Unirme a un álbum')),
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
                        Icons.group_add_outlined,
                        color: MemoraColors.deepInk,
                      ),
                    ),
                    const SizedBox(height: MemoraSpacing.md),
                    Text('Unirme a un álbum', style: textTheme.headlineSmall),
                    const SizedBox(height: MemoraSpacing.xs),
                    Text(
                      'Pega el enlace de invitación completo, o solo su token.',
                      style: textTheme.bodyMedium,
                    ),
                    const SizedBox(height: MemoraSpacing.lg),
                    TextField(
                      controller: _inputController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Enlace o token de invitación',
                      ),
                      onSubmitted: (_) => _accept(),
                    ),
                    if (controller.acceptInvitationErrorMessage != null) ...[
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
                              controller.acceptInvitationErrorMessage!,
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
                label: controller.isAcceptingInvitation
                    ? 'Aceptando...'
                    : 'Aceptar',
                icon: Icons.check,
                expand: true,
                loading: controller.isAcceptingInvitation,
                onPressed: controller.isAcceptingInvitation ? null : _accept,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
