import 'package:flutter/material.dart';

import '../memora_colors.dart';
import '../memora_spacing.dart';

/// Which of the app's two navigable tabs currently owns the screen this bar
/// is attached to. "Compartidos"/"Ajustes" aren't real destinations yet (see
/// [AuroraBottomNav]'s class doc), so they're not modeled here.
enum AuroraNavTab { home, albums }

/// The shared floating bottom navigation bar — originally built inline in
/// `home_screen.dart` (mockup addition, decided directly with the user, see
/// CLAUDE.md), extracted here so `AlbumsListScreen` can reuse it verbatim
/// (post-feedback redesign, sin spec de Kiro) instead of duplicating the
/// widget. 4 items (Inicio/Álbumes/Compartidos/Ajustes) + a floating central
/// "+" that reuses whatever photo-upload action the host screen wires up via
/// [onAddPhotos] — never a second/independent upload flow.
///
/// [activeTab] decides which of Inicio/Álbumes renders as active (no
/// `onTap`, just the highlighted style) — the other one gets [onTapHome]/
/// [onTapAlbums] as its tap handler. `HomeScreen` passes `activeTab: home`
/// and `onTapAlbums: _openAlbums` (`onTapHome` stays null: tapping "Inicio"
/// while already on Home is a no-op); `AlbumsListScreen` passes
/// `activeTab: albums` and `onTapHome: () => Navigator.pop(context)` (pops
/// back to the `HomeScreen` already underneath it on the stack, since this
/// screen has no traditional `AppBar`/back button of its own) with
/// `onTapAlbums` left null.
///
/// - **Compartidos/Ajustes**: no screens exist for these yet (explicit
///   product decision, not an oversight — see CLAUDE.md/README.md). Tapping
///   either only shows a brief "muy pronto" `SnackBar` (via the app's
///   already-configured `snackBarTheme`) — never a crash, a navigation to
///   nothing, or a blank screen. **Marked for a future Kiro spec**:
///   whether/when these two sections exist for real.
class AuroraBottomNav extends StatelessWidget {
  const AuroraBottomNav({
    super.key,
    required this.activeTab,
    required this.onAddPhotos,
    this.onTapHome,
    this.onTapAlbums,
  });

  final AuroraNavTab activeTab;
  final VoidCallback onAddPhotos;

  /// Tap handler for "Inicio" — only used when [activeTab] is NOT `home`
  /// (the item renders inert/active otherwise).
  final VoidCallback? onTapHome;

  /// Tap handler for "Álbumes" — only used when [activeTab] is NOT `albums`.
  final VoidCallback? onTapAlbums;

  void _showComingSoon(BuildContext context, String label) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$label: muy pronto.')));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(
        MemoraSpacing.lg,
        0,
        MemoraSpacing.lg,
        MemoraSpacing.sm,
      ),
      child: SizedBox(
        height: 78,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: [
            Container(
              height: 64,
              decoration: BoxDecoration(
                color: MemoraColors.paper,
                borderRadius: BorderRadius.circular(MemoraRadius.pill),
                boxShadow: [
                  BoxShadow(
                    color: MemoraColors.deepInk.withValues(alpha: 0.14),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _NavBarItem(
                          icon: Icons.home_rounded,
                          label: 'Inicio',
                          active: activeTab == AuroraNavTab.home,
                          onTap: activeTab == AuroraNavTab.home
                              ? null
                              : onTapHome,
                        ),
                        _NavBarItem(
                          icon: Icons.photo_album_outlined,
                          label: 'Álbumes',
                          active: activeTab == AuroraNavTab.albums,
                          onTap: activeTab == AuroraNavTab.albums
                              ? null
                              : onTapAlbums,
                        ),
                      ],
                    ),
                  ),
                  // Reserves the room the floating central "+" overlaps.
                  const SizedBox(width: 64),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _NavBarItem(
                          icon: Icons.groups_outlined,
                          label: 'Compartidos',
                          active: false,
                          onTap: () => _showComingSoon(context, 'Compartidos'),
                        ),
                        _NavBarItem(
                          icon: Icons.settings_outlined,
                          label: 'Ajustes',
                          active: false,
                          onTap: () => _showComingSoon(context, 'Ajustes'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Positioned(top: 0, child: _CentralAddButton(onTap: onAddPhotos)),
          ],
        ),
      ),
    );
  }
}

class _NavBarItem extends StatelessWidget {
  const _NavBarItem({
    required this.icon,
    required this.label,
    required this.active,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // `auraVioletOnLight` (not raw `auraViolet`): this bar sits on the
    // light Paper canvas, where the raw signature colors read as too low
    // contrast for a foreground icon/label (see memora_colors.dart).
    final color = active
        ? MemoraColors.auraVioletOnLight
        : MemoraColors.textTertiary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(MemoraRadius.pill),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: MemoraSpacing.xs,
          vertical: MemoraSpacing.xs,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 2),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The floating central "+", same visual language as `MemoraPrimaryButton`/
/// the (former) `AlbumsListScreen` FAB: a solid `signatureGradient` fill
/// (never a glass/blur effect here — CLAUDE.md documents that glass over the
/// flat Paper canvas reads as nearly invisible; this button floats over
/// Paper too, so it deliberately follows the same solid-gradient lesson
/// instead of repeating that mistake).
class _CentralAddButton extends StatelessWidget {
  const _CentralAddButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: MemoraColors.signatureGradient,
            boxShadow: [
              BoxShadow(
                color: MemoraColors.deepInk.withValues(alpha: 0.28),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Icon(Icons.add, color: MemoraColors.paper, size: 28),
        ),
      ),
    );
  }
}
