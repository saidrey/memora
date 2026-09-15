import 'package:flutter/material.dart';

import '../../auth/auth_controller.dart';
import '../../photos/photo_upload_controller.dart';
import '../album_models.dart';
import '../albums_controller.dart';
import '../drive_thumbnail_service.dart';
import 'album_detail_screen.dart';
import 'create_album_screen.dart';

/// Albums-list screen (spec04-ui-albumes.md): own albums + albums the user
/// collaborates on, each with its role and photo count, plus the entry
/// point to create a new one. First screen of the app's first `Navigator`
/// stack (decision E). Not a designed screen (UI mínima funcional).
class AlbumsListScreen extends StatefulWidget {
  const AlbumsListScreen({
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
  State<AlbumsListScreen> createState() => _AlbumsListScreenState();
}

class _AlbumsListScreenState extends State<AlbumsListScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    widget.controller.loadAlbums();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => setState(() {});

  Future<void> _openCreateAlbum() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => CreateAlbumScreen(controller: widget.controller),
      ),
    );
  }

  Future<void> _openAlbum(AlbumListItem item) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => AlbumDetailScreen(
          controller: widget.controller,
          photoUploadController: widget.photoUploadController,
          driveThumbnailService: widget.driveThumbnailService,
          authController: widget.authController,
          albumId: item.id,
          role: item.role,
        ),
      ),
    );
    // The album may have been renamed/deleted while its detail screen was
    // open — AlbumsController already refreshes the list itself after
    // those mutations, but a plain reload here is cheap and keeps this
    // screen correct even if that ever changes.
    if (mounted) widget.controller.loadAlbums();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Álbumes'),
        actions: [
          IconButton(
            onPressed: _openCreateAlbum,
            icon: const Icon(Icons.add),
            tooltip: 'Crear álbum',
          ),
        ],
      ),
      body: SafeArea(child: _buildBody(controller)),
    );
  }

  Widget _buildBody(AlbumsController controller) {
    if (controller.isLoadingList && controller.albums.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.listErrorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            controller.listErrorMessage!,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (controller.albums.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Todavía no tienes álbumes. Crea el primero.'),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: controller.loadAlbums,
      child: ListView.separated(
        itemCount: controller.albums.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final item = controller.albums[index];
          return ListTile(
            title: Text(item.name),
            subtitle: Text('${item.photoCount} foto(s)'),
            trailing: Chip(
              label: Text(
                item.role == AlbumRole.owner ? 'Owner' : 'Colaborador',
              ),
            ),
            onTap: () => _openAlbum(item),
          );
        },
      ),
    );
  }
}
