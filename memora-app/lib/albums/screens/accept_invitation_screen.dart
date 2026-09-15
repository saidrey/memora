import 'package:flutter/material.dart';

import '../../auth/auth_controller.dart';
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
  State<AcceptInvitationScreen> createState() =>
      _AcceptInvitationScreenState();
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
      MaterialPageRoute(
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

    return Scaffold(
      appBar: AppBar(title: const Text('Unirme a un álbum')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Pega el enlace de invitación completo, o solo su token.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _inputController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Enlace o token de invitación',
                ),
                onSubmitted: (_) => _accept(),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: controller.isAcceptingInvitation ? null : _accept,
                child: Text(
                  controller.isAcceptingInvitation ? 'Aceptando...' : 'Aceptar',
                ),
              ),
              if (controller.acceptInvitationErrorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  controller.acceptInvitationErrorMessage!,
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
