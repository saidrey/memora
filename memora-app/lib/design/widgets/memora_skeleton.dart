import 'package:flutter/material.dart';

import '../memora_colors.dart';
import '../memora_motion.dart';

/// A loading-skeleton block: a rounded rectangle in a neutral surface tone
/// with a slow, subtle opacity "breathing" loop — NOT a shimmer/light-sweep
/// effect (explicitly rejected: the user asked against that look). Used in
/// place of a bare spinner for list/grid initial loading, where the shape
/// of the skeleton should roughly match the size of the real content that
/// will replace it (a card, a photo tile) so the layout doesn't jump once
/// data arrives.
///
/// Respects reduced motion ([MemoraMotion.reduceMotion]): the breathing
/// loop is skipped and the block renders at a fixed, medium opacity
/// instead — still readable as "this is a placeholder", just static.
class MemoraSkeleton extends StatefulWidget {
  const MemoraSkeleton({
    super.key,
    this.width,
    this.height,
    this.borderRadius = 16,
  });

  final double? width;
  final double? height;
  final double borderRadius;

  @override
  State<MemoraSkeleton> createState() => _MemoraSkeletonState();
}

class _MemoraSkeletonState extends State<MemoraSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  bool _startedRepeating = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _opacity = Tween<double>(
      begin: 0.55,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // MediaQuery (via MemoraMotion.reduceMotion) can only be read once this
    // widget is attached to the tree — initState runs too early for that,
    // so the reduced-motion check and the controller start happen here.
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
    final box = DecoratedBox(
      decoration: BoxDecoration(
        color: MemoraColors.surface2,
        borderRadius: BorderRadius.circular(widget.borderRadius),
      ),
    );

    final reduceMotion = MemoraMotion.reduceMotion(context);
    final content = SizedBox(
      width: widget.width,
      height: widget.height,
      child: reduceMotion
          ? Opacity(opacity: 0.75, child: box)
          : AnimatedBuilder(
              animation: _opacity,
              builder: (context, child) =>
                  Opacity(opacity: _opacity.value, child: child),
              child: box,
            ),
    );

    return RepaintBoundary(child: content);
  }
}

/// A skeleton shaped like an [AlbumsListScreen] album card (title bar +
/// montage/stat area, matching `_AlbumGridCard`'s general proportions) —
/// used for the grid's initial loading state instead of a centered spinner.
class MemoraAlbumCardSkeleton extends StatelessWidget {
  const MemoraAlbumCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: MemoraColors.surface1,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: MemoraColors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const MemoraSkeleton(height: 16, width: 96, borderRadius: 8),
              const SizedBox(height: 12),
              Expanded(
                child: MemoraSkeleton(width: double.infinity, borderRadius: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A skeleton shaped like a single photo-grid tile
/// (`album_detail_screen.dart`'s `_PhotoTile`) — a plain rounded square.
class MemoraPhotoTileSkeleton extends StatelessWidget {
  const MemoraPhotoTileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const MemoraSkeleton(width: double.infinity, borderRadius: 14);
  }
}
