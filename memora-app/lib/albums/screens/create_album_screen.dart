import 'package:flutter/material.dart';

import '../albums_controller.dart';

/// Create-album screen (spec04-ui-albumes.md, decision D): asks ONLY for a
/// name (≤100 chars) — visibility is never offered here, every new album is
/// born `PRIVATE` and changing it to `PUBLIC` is a separate, conscious
/// action later via the detail screen's (owner-only) edit action. Not a
/// designed screen (UI mínima funcional).
class CreateAlbumScreen extends StatefulWidget {
  const CreateAlbumScreen({super.key, required this.controller});

  final AlbumsController controller;

  @override
  State<CreateAlbumScreen> createState() => _CreateAlbumScreenState();
}

class _CreateAlbumScreenState extends State<CreateAlbumScreen> {
  final _nameController = TextEditingController();
  static const _maxNameLength = 100;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final created = await widget.controller.createAlbum(_nameController.text);
    if (!mounted) return;
    if (created != null) {
      Navigator.of(context).pop(created);
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final isNameEmpty = _nameController.text.trim().isEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Crear álbum')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _nameController,
                maxLength: _maxNameLength,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Nombre del álbum',
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => controller.isMutating ? null : _submit(),
              ),
              if (controller.mutationErrorMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  controller.mutationErrorMessage!,
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              ],
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: controller.isMutating || isNameEmpty
                    ? null
                    : _submit,
                child: controller.isMutating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Crear'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
