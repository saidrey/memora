import 'dart:async' show unawaited;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../auth/auth_controller.dart';
import '../../design/design.dart';
import '../../photos/photo_models.dart';
import '../../photos/photo_upload_controller.dart';
import '../album_models.dart';
import '../albums_controller.dart';
import '../drive_thumbnail_service.dart';
import 'album_detail_screen.dart';
import 'create_album_screen.dart';

/// Extra bottom clearance reserved for the floating [AuroraBottomNav] (see
/// `Scaffold.extendBody` in this screen's `build`) — same value/reasoning as
/// `home_screen.dart`'s own `_bottomNavClearance` (kept as a separate local
/// const rather than a shared export: a single numeric convention isn't
/// worth a cross-file dependency).
const double _bottomNavClearance = 104;

/// Albums-list screen (spec04-ui-albumes.md; rebuilt to match an exact
/// reference the user shared directly, sin spec de Kiro — see CLAUDE.md):
/// own albums + albums the user collaborates on, each with its role and
/// photo count, plus the entry point to create a new one. Same
/// `AlbumsController`/navigation as before — a header with the album/photo
/// totals and two action circles (search placeholder, create), a 2-column
/// grid of real-cover-photo cards, and a promo card inviting to create
/// another album, all above the same [AuroraBottomNav] `HomeScreen` uses
/// ("Álbumes" marked active).
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
  /// Ids of albums whose entrance animation has already played — a rebuild
  /// (any `notifyListeners()` from the controller: pull-to-refresh, a cover
  /// photo arriving, a new album created) must NOT re-trigger
  /// `MemoraFadeSlideIn` for cards that were already on screen, or the
  /// whole grid would visibly flash/re-animate on every unrelated update.
  /// Only an id that's genuinely new (not yet in this set) gets the
  /// entrance treatment; everything else renders directly. See point 9 of
  /// the motion pass in CLAUDE.md for the "why" in more detail.
  final Set<String> _animatedAlbumIds = {};

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

  void _showComingSoon(String label) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$label: muy pronto.')));
  }

  void _showConfirmationSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              Icons.check_circle_outline,
              size: 20,
              color: MemoraColors.semanticSuccess,
            ),
            const SizedBox(width: MemoraSpacing.sm),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              Icons.error_outline,
              size: 20,
              color: MemoraColors.semanticError,
            ),
            const SizedBox(width: MemoraSpacing.sm),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }

  Future<void> _openCreateAlbum() async {
    final created = await Navigator.of(context).push<AlbumSummary?>(
      MemoraPageRoute(
        builder: (_) => CreateAlbumScreen(controller: widget.controller),
      ),
    );
    if (created != null && mounted) {
      _showConfirmationSnackBar('"${created.name}" creado.');
    }
  }

  Future<void> _openAlbum(AlbumListItem item) async {
    final deleted = await Navigator.of(context).push<bool?>(
      MemoraPageRoute(
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
    if (!mounted) return;
    // The album may have been renamed/deleted while its detail screen was
    // open — AlbumsController already refreshes the list itself after
    // those mutations, but a plain reload here is cheap and keeps this
    // screen correct even if that ever changes.
    widget.controller.loadAlbums();
    if (deleted == true) {
      _showConfirmationSnackBar('"${item.name}" eliminado.');
    }
  }

  /// Loads [item] as the controller's "current album" (the mechanism
  /// `renameCurrentAlbum`/`deleteCurrentAlbum` operate on — see
  /// `AlbumsController.loadAlbumDetail`, same one `album_detail_screen.dart`
  /// uses on entry) so the overflow menu's "Renombrar"/"Eliminar" can call
  /// those existing methods without a second/new controller API. Shows a
  /// short non-dismissible loading dialog (same pattern as
  /// `promptDriveReconnect`) while the detail request is in flight. Returns
  /// whether it succeeded.
  Future<bool> _loadAsCurrentAlbum(AlbumListItem item) async {
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
              Text('Cargando álbum...'),
            ],
          ),
        ),
      ),
    );
    await widget.controller.loadAlbumDetail(item.id, role: item.role);
    if (!mounted) return false;
    Navigator.of(context, rootNavigator: true).pop();
    final error = widget.controller.detailErrorMessage;
    if (error != null) {
      _showErrorSnackBar(error);
      return false;
    }
    return true;
  }

  /// The "···" overflow menu. "Abrir álbum" is always offered; "Renombrar"/
  /// "Eliminar" only for an owner (same owner-only visibility rule as every
  /// other admin action in the app — hidden, not just disabled, for a
  /// `collaborator`).
  Future<void> _openAlbumOptions(AlbumListItem item) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(MemoraRadius.card),
        ),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: const Text('Abrir álbum'),
              onTap: () => Navigator.of(sheetContext).pop('open'),
            ),
            if (item.role == AlbumRole.owner) ...[
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Renombrar álbum'),
                onTap: () => Navigator.of(sheetContext).pop('rename'),
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline,
                  color: MemoraColors.semanticError,
                ),
                title: const Text(
                  'Eliminar álbum',
                  style: TextStyle(color: MemoraColors.semanticError),
                ),
                onTap: () => Navigator.of(sheetContext).pop('delete'),
              ),
            ],
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'open':
        await _openAlbum(item);
      case 'rename':
        await _renameAlbumFromList(item);
      case 'delete':
        await _deleteAlbumFromList(item);
    }
  }

  /// Same rename dialog/copy as `AlbumDetailScreen._renameAlbum` (NOT
  /// `autofocus: true` — see CLAUDE.md's `showDialog`/`TextField` crash
  /// gotcha). `renameCurrentAlbum` only refreshes the open detail, not the
  /// list (`AlbumsController._updateCurrentAlbum`'s doc), so a successful
  /// rename here explicitly reloads the list too — otherwise this grid
  /// would keep showing the old name until some unrelated refresh.
  Future<void> _renameAlbumFromList(AlbumListItem item) async {
    final loaded = await _loadAsCurrentAlbum(item);
    if (!loaded || !mounted) return;

    final nameController = TextEditingController(text: item.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Renombrar álbum'),
        content: TextField(
          controller: nameController,
          maxLength: 100,
          decoration: const InputDecoration(labelText: 'Nombre'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(nameController.text),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    nameController.dispose();
    if (newName == null || newName.trim().isEmpty || !mounted) return;

    final renamed = await widget.controller.renameCurrentAlbum(newName);
    if (!mounted) return;
    if (renamed) {
      await widget.controller.loadAlbums();
      if (mounted) _showConfirmationSnackBar('Álbum renombrado.');
    } else {
      final error = widget.controller.mutationErrorMessage;
      if (error != null) _showErrorSnackBar(error);
    }
  }

  /// Same confirmation copy (D16: photos aren't deleted) as
  /// `AlbumDetailScreen._deleteAlbum`. `deleteCurrentAlbum` already
  /// refreshes the list on success, so no extra reload is needed here.
  Future<void> _deleteAlbumFromList(AlbumListItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar álbum'),
        content: const Text(
          'Se eliminará este álbum y se quitarán sus fotos de él, pero '
          'las fotografías NO se borrarán: siguen existiendo en tu '
          'biblioteca de Memora y en tu Google Drive.',
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
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final loaded = await _loadAsCurrentAlbum(item);
    if (!loaded || !mounted) return;

    final deleted = await widget.controller.deleteCurrentAlbum();
    if (!mounted) return;
    if (deleted) {
      _showConfirmationSnackBar('"${item.name}" eliminado.');
    } else {
      final error = widget.controller.mutationErrorMessage;
      if (error != null) _showErrorSnackBar(error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final totalPhotos = controller.albums.fold<int>(
      0,
      (sum, album) => sum + album.photoCount,
    );

    return Scaffold(
      backgroundColor: MemoraColors.paper,
      extendBody: true,
      bottomNavigationBar: AuroraBottomNav(
        activeTab: AuroraNavTab.albums,
        onTapHome: () => Navigator.of(context).maybePop(),
        onAddPhotos: () => widget.photoUploadController.pickAndUploadPhotos(),
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _AlbumsListHeader(
              totalAlbums: controller.albums.length,
              totalPhotos: totalPhotos,
              onSearch: () => _showComingSoon('Buscar'),
              onCreate: _openCreateAlbum,
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: MemoraMotion.moderate,
                switchInCurve: MemoraMotion.enterCurve,
                switchOutCurve: MemoraMotion.exitCurve,
                child: _buildBody(controller),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(AlbumsController controller) {
    if (controller.isLoadingList && controller.albums.isEmpty) {
      return const _AlbumsGridSkeleton(key: ValueKey('loading'));
    }
    if (controller.listErrorMessage != null) {
      return MemoraEmptyState(
        key: const ValueKey('error'),
        icon: Icons.wifi_off_outlined,
        title: 'No se pudieron cargar tus álbumes',
        subtitle:
            '${controller.listErrorMessage}\n\nRevisa tu conexión e '
            'intenta de nuevo.',
        actionLabel: 'Reintentar',
        onAction: () => controller.loadAlbums(),
      );
    }
    if (controller.albums.isEmpty) {
      // Illustration instead of the generic icon (ajuste post-feedback, sin
      // spec de Kiro) — `assets/images/empty.png`, provided by the user.
      return _FloatingEmptyIllustration(
        key: const ValueKey('empty'),
        onCreate: _openCreateAlbum,
      );
    }
    return RefreshIndicator(
      key: const ValueKey('content'),
      onRefresh: controller.loadAlbums,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              MemoraSpacing.lg,
              MemoraSpacing.sm,
              MemoraSpacing.lg,
              0,
            ),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: MemoraSpacing.md,
                crossAxisSpacing: MemoraSpacing.md,
                childAspectRatio: 0.72,
              ),
              delegate: SliverChildBuilderDelegate((context, index) {
                final item = controller.albums[index];
                final card = RepaintBoundary(
                  child: _AlbumGridCard(
                    item: item,
                    onTap: () => _openAlbum(item),
                    onOptions: () => _openAlbumOptions(item),
                    coverPhotos: controller.coverPhotosFor(item.id),
                    thumbnailService: widget.driveThumbnailService,
                  ),
                );
                // Only animate an id the very first time it's ever built
                // here — a rebuild triggered by something unrelated (a
                // cover photo arriving for a DIFFERENT album, pull-to
                // -refresh returning the exact same list) must not replay
                // every card's entrance.
                if (_animatedAlbumIds.contains(item.id)) return card;
                _animatedAlbumIds.add(item.id);
                return MemoraFadeSlideIn(
                  delay: MemoraMotion.stagger(index),
                  child: card,
                );
              }, childCount: controller.albums.length),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              MemoraSpacing.lg,
              MemoraSpacing.lg,
              MemoraSpacing.lg,
              MemoraSpacing.xxl + _bottomNavClearance,
            ),
            sliver: SliverToBoxAdapter(
              child: _CreateAlbumPromoCard(onCreate: _openCreateAlbum),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Mis álbumes" + "{N} álbumes · {M} recuerdos" on the left, a search
/// placeholder circle + a gradient "create album" circle on the right — the
/// exact header the user's reference shows. [onSearch] always surfaces a
/// "muy pronto" `SnackBar` (same pattern/copy as `AuroraBottomNav`'s
/// Compartidos/Ajustes): search isn't a real feature of this app.
class _AlbumsListHeader extends StatelessWidget {
  const _AlbumsListHeader({
    required this.totalAlbums,
    required this.totalPhotos,
    required this.onSearch,
    required this.onCreate,
  });

  final int totalAlbums;
  final int totalPhotos;
  final VoidCallback onSearch;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        MemoraSpacing.lg,
        MemoraSpacing.sm,
        MemoraSpacing.lg,
        MemoraSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Mis álbumes',
                  style: textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$totalAlbums álbumes · $totalPhotos recuerdos',
                  style: textTheme.bodyMedium?.copyWith(
                    color: MemoraColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: MemoraSpacing.sm),
          _HeaderCircleButton(
            icon: Icons.search,
            tooltip: 'Buscar',
            onTap: onSearch,
          ),
          const SizedBox(width: MemoraSpacing.sm),
          _HeaderCircleButton(
            icon: Icons.add,
            tooltip: 'Crear álbum',
            gradient: true,
            onTap: onCreate,
          ),
        ],
      ),
    );
  }
}

/// A 40px circular action button — a plain neutral surface for [gradient] =
/// false (search), or the app's signature gradient fill for `true` (create),
/// matching `_InitialsAvatar`/the (former) create-album FAB's visual
/// language.
class _HeaderCircleButton extends StatelessWidget {
  const _HeaderCircleButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.gradient = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool gradient;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: gradient ? Colors.transparent : MemoraColors.surface1,
        shape: const CircleBorder(
          side: BorderSide(color: MemoraColors.border),
        ),
        child: Ink(
          decoration: gradient
              ? const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: MemoraColors.signatureGradient,
                )
              : null,
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: 40,
              height: 40,
              child: Icon(
                icon,
                size: 20,
                color: gradient
                    ? MemoraColors.paper
                    : MemoraColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Initial-load placeholder for the grid: a handful of card-shaped
/// skeletons (see `memora_skeleton.dart`) instead of a centered spinner —
/// the shape roughly matches the real cards so the layout doesn't jump once
/// data arrives.
class _AlbumsGridSkeleton extends StatelessWidget {
  const _AlbumsGridSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(
        MemoraSpacing.lg,
        MemoraSpacing.sm,
        MemoraSpacing.lg,
        MemoraSpacing.xxl,
      ),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: MemoraSpacing.md,
        crossAxisSpacing: MemoraSpacing.md,
        childAspectRatio: 0.72,
      ),
      itemCount: 6,
      itemBuilder: (context, index) => const MemoraAlbumCardSkeleton(),
    );
  }
}

/// The empty-state illustration with a very subtle, slow floating loop
/// (translate + a hair of scale) — deliberately understated, not a bouncy
/// demo animation. Respects reduced motion (no loop at all, image renders
/// still).
class _FloatingEmptyIllustration extends StatefulWidget {
  const _FloatingEmptyIllustration({super.key, required this.onCreate});

  final VoidCallback onCreate;

  @override
  State<_FloatingEmptyIllustration> createState() =>
      _FloatingEmptyIllustrationState();
}

class _FloatingEmptyIllustrationState extends State<_FloatingEmptyIllustration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  );
  late final Animation<double> _float = Tween<double>(
    begin: -4,
    end: 4,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  bool _startedRepeating = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // MediaQuery (via MemoraMotion.reduceMotion) can only be read once this
    // widget is attached to the tree — initState runs too early for that,
    // so the reduced-motion check and the controller start happen here
    // (same fix as `_MemoraSkeletonState`, see `memora_skeleton.dart`).
    if (!_startedRepeating && !MemoraMotion.reduceMotion(context)) {
      _startedRepeating = true;
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MemoraMotion.reduceMotion(context);

    Widget illustration = MemoraEmptyState(
      imageAsset: 'assets/images/empty.png',
      title: 'Todo empieza con un álbum',
      subtitle:
          'Todavía no creaste ni te uniste a ningún álbum. Creá el '
          'primero para empezar a guardar tus recuerdos junto a quien '
          'quieras.',
      actionLabel: 'Crear álbum',
      onAction: widget.onCreate,
    );

    if (reduceMotion) return illustration;

    return AnimatedBuilder(
      animation: _float,
      builder: (context, child) =>
          Transform.translate(offset: Offset(0, _float.value), child: child),
      child: illustration,
    );
  }
}

/// One album card: a full-bleed real cover photo (the album's FIRST photo
/// only — no montage/fan of multiple photos, matching the exact reference
/// the user shared) with an overflow "···" circle over its top-right
/// corner, then the album name + role badge, then the photo count + a
/// double-chevron affordance — all tappable (opens the album), consistent
/// with the whole card being one tap target.
///
/// The `Hero` is intentionally kept around the complete card so the
/// selected memory retains its shape while opening the detail screen (tag
/// matched by `AlbumDetailScreen._AlbumHero`'s background).
///
/// Cover states:
/// - `item.photoCount == 0`: [_NoPhotosCoverArea] — a dark illustrated
///   "sin fotos" block. This is a DIFFERENT case from below (no photos AT
///   ALL vs. a cover that hasn't arrived yet) and must not be confused with
///   it.
/// - `item.photoCount > 0` and [coverPhotos] has arrived (via
///   `AlbumsController.coverPhotosFor`, populated lazily/non-blocking after
///   `loadAlbums()` — see its doc comment on the accepted N+1 cost): the
///   real first photo, full-bleed (`_AlbumCoverImage`).
/// - `item.photoCount > 0` but no cover cached yet (fetch still in flight):
///   a plain skeleton block — never the "sin fotos" empty state, which
///   would misrepresent an album that does have photos.
class _AlbumGridCard extends StatelessWidget {
  const _AlbumGridCard({
    required this.item,
    required this.onTap,
    required this.onOptions,
    required this.coverPhotos,
    required this.thumbnailService,
  });

  final AlbumListItem item;
  final VoidCallback onTap;
  final VoidCallback onOptions;
  final List<Photo>? coverPhotos;
  final DriveThumbnailService thumbnailService;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final roleLabel = item.role == AlbumRole.owner ? 'Owner' : 'Colaborador';
    final covers = coverPhotos;
    final hasCover = covers != null && covers.isNotEmpty;

    final Widget coverArea;
    if (item.photoCount == 0) {
      coverArea = const _NoPhotosCoverArea();
    } else if (hasCover) {
      coverArea = _AlbumCoverImage(
        key: ValueKey(covers.first.id),
        photo: covers.first,
        thumbnailService: thumbnailService,
      );
    } else {
      coverArea = const MemoraSkeleton(
        width: double.infinity,
        height: double.infinity,
        borderRadius: 0,
      );
    }

    return Hero(
      tag: 'album-hero-${item.id}',
      child: Material(
        color: MemoraColors.surface1,
        borderRadius: BorderRadius.circular(MemoraRadius.hero),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 150,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    coverArea,
                    Positioned(
                      top: MemoraSpacing.xs,
                      right: MemoraSpacing.xs,
                      child: _OverflowCircleButton(onTap: onOptions),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(MemoraSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            item.name,
                            style: textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: MemoraSpacing.xs),
                        MemoraBadge(label: roleLabel),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.collections_outlined,
                          size: 14,
                          color: MemoraColors.textTertiary,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '${item.photoCount} recuerdos',
                            style: textTheme.bodySmall?.copyWith(
                              color: MemoraColors.textTertiary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Icon(
                          Icons.keyboard_double_arrow_right,
                          size: 16,
                          color: MemoraColors.textTertiary,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small translucent circle for the "···" overflow action, readable over
/// either a photo or the dark [_NoPhotosCoverArea] alike.
class _OverflowCircleButton extends StatelessWidget {
  const _OverflowCircleButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MemoraColors.deepInk.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: const SizedBox(
          width: 30,
          height: 30,
          child: Icon(Icons.more_horiz, color: MemoraColors.paper, size: 18),
        ),
      ),
    );
  }
}

/// Illustrated "sin fotos" cover state — replaces the abstract
/// gradient-border fallback this card used to show for EVERY album without
/// a resolved cover; now reserved only for an album that genuinely has zero
/// photos (`item.photoCount == 0`). A loading cover (photos exist, just not
/// fetched yet) uses a plain skeleton instead — see `_AlbumGridCard`'s class
/// doc.
class _NoPhotosCoverArea extends StatelessWidget {
  const _NoPhotosCoverArea();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return ColoredBox(
      color: MemoraColors.deepInk,
      child: Padding(
        padding: const EdgeInsets.all(MemoraSpacing.sm),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const _GradientIconChip(
              icon: Icons.photo_library_outlined,
              size: 40,
            ),
            const SizedBox(height: MemoraSpacing.sm),
            Text(
              'Aún no hay fotos',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.titleSmall?.copyWith(color: MemoraColors.paper),
            ),
            const SizedBox(height: 2),
            Text(
              'Agrega recuerdos para que este álbum cobre vida.',
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodySmall?.copyWith(
                color: MemoraColors.paper.withValues(alpha: 0.68),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A circular chip with the signature gradient behind an icon — the same
/// visual language `_InitialsAvatar`/role badges/the create-album circle
/// already use, reused here for [_NoPhotosCoverArea] and
/// [_CreateAlbumPromoCard].
class _GradientIconChip extends StatelessWidget {
  const _GradientIconChip({required this.icon, this.size = 44});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: MemoraColors.signatureGradient,
      ),
      child: Icon(icon, color: MemoraColors.deepInk, size: size * 0.45),
    );
  }
}

/// One card's real cover photo, fetched through the SAME
/// [DriveThumbnailService] (and its in-memory byte cache) already used by
/// `album_detail_screen.dart`'s `_PhotoTile`/`_HeroPhotoImage` — no second
/// thumbnail pipeline, no new caching. Follows that same widget's
/// `late final` Future + `initState`-then-synchronous-`build` pattern (see
/// CLAUDE.md's `Future.ignore()` gotcha for why this is safe without it: the
/// Future is created and immediately observed by `FutureBuilder` in the same
/// frame). `key: ValueKey(photo.id)` at the call site is what makes this
/// safe to reorder/replace across rebuilds — same key-per-id rule as every
/// other async-stateful list item in this app.
class _AlbumCoverImage extends StatefulWidget {
  const _AlbumCoverImage({
    super.key,
    required this.photo,
    required this.thumbnailService,
  });

  final Photo photo;
  final DriveThumbnailService thumbnailService;

  @override
  State<_AlbumCoverImage> createState() => _AlbumCoverImageState();
}

class _AlbumCoverImageState extends State<_AlbumCoverImage> {
  late final Future<Uint8List> _thumbnailFuture;

  @override
  void initState() {
    super.initState();
    _thumbnailFuture = widget.thumbnailService.getThumbnail(
      widget.photo.storageRef.fileId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _thumbnailFuture,
      builder: (context, snapshot) {
        final Widget child;
        if (snapshot.connectionState != ConnectionState.done) {
          child = const MemoraSkeleton(
            key: ValueKey('loading'),
            width: double.infinity,
            height: double.infinity,
            borderRadius: 0,
          );
        } else if (snapshot.hasError || snapshot.data == null) {
          child = const ColoredBox(
            key: ValueKey('error'),
            color: MemoraColors.surface2,
            child: Icon(
              Icons.image_not_supported_outlined,
              color: MemoraColors.textTertiary,
            ),
          );
        } else {
          child = Image.memory(
            snapshot.data!,
            key: const ValueKey('image'),
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
          );
        }
        return AnimatedSwitcher(
          duration: MemoraMotion.moderate,
          switchInCurve: MemoraMotion.enterCurve,
          switchOutCurve: MemoraMotion.exitCurve,
          child: child,
        );
      },
    );
  }
}

/// Full-width promo card at the end of the grid, inviting to create another
/// album — a subtle signature-gradient tint on Paper (same
/// blend-onto-Paper pattern `album_detail_screen.dart`'s `_sectionTint`
/// uses for its sharing-sheet sections, re-implemented locally here rather
/// than importing that file's private helper), a gradient icon chip, title
/// + subtitle, and a light pill button — same destination
/// (`CreateAlbumScreen`) as the header's "+" circle, not a duplicated flow.
class _CreateAlbumPromoCard extends StatelessWidget {
  const _CreateAlbumPromoCard({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return MemoraCard(
      onTap: onCreate,
      gradient: _promoTint(MemoraColors.auraViolet),
      child: Row(
        children: [
          const _GradientIconChip(icon: Icons.add_photo_alternate_outlined),
          const SizedBox(width: MemoraSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Crea tu próximo álbum',
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Organiza y comparte más recuerdos.',
                  style: textTheme.bodySmall?.copyWith(
                    color: MemoraColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: MemoraSpacing.sm),
          _LightPillButton(label: 'Crear álbum', onTap: onCreate),
        ],
      ),
    );
  }
}

/// Subtle background tint for [_CreateAlbumPromoCard]: blends [accent] onto
/// [MemoraColors.paper] at a low, deliberately restrained alpha — same
/// formula as `album_detail_screen.dart`'s private `_sectionTint` (not
/// imported: that helper is private to that file, and this is a small
/// enough function not to be worth promoting to a shared one for a single
/// extra call site). Not `const` (`Color.alphaBlend` isn't a const
/// function).
LinearGradient _promoTint(Color accent) {
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color.alphaBlend(accent.withValues(alpha: 0.08), MemoraColors.paper),
      Color.alphaBlend(accent.withValues(alpha: 0.03), MemoraColors.paper),
    ],
  );
}

/// A light pill button — solid Paper fill with a border, Deep Ink label —
/// distinct from `MemoraPrimaryButton` (reserved for a screen's single main
/// CTA elsewhere) and from a plain `TextButton`: this needs to read as a
/// tappable pill sitting on top of the tinted promo card.
class _LightPillButton extends StatelessWidget {
  const _LightPillButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MemoraColors.paper,
      shape: const StadiumBorder(side: BorderSide(color: MemoraColors.border)),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: MemoraSpacing.md,
            vertical: MemoraSpacing.sm,
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: MemoraColors.deepInk,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
