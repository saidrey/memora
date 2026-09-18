import 'package:flutter/material.dart';

import '../memora_colors.dart';
import '../memora_motion.dart';
import '../memora_spacing.dart';

/// One pill of a [MemoraSegmentedTabs] row: an icon + a short label.
class MemoraSegmentedTab {
  const MemoraSegmentedTab({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

/// A row of equal-width pill tabs, the active one filled with
/// [MemoraColors.signatureGradient] and the rest neutral — first built for
/// `AlbumDetailScreen`'s "Fotos"/"Colaboradores"/"Compartir" segmented
/// control (mockup redesign, sin spec de Kiro), extracted here since a
/// 3(ish)-pill segmented control reads as generically reusable rather than
/// specific to that one screen. Not a `TabBar`/`TabController` (no
/// `PageView`/swipe behind it — the host screen owns what "active" means and
/// just swaps its own content) — this widget is purely the row of pills.
class MemoraSegmentedTabs extends StatelessWidget {
  const MemoraSegmentedTabs({
    super.key,
    required this.tabs,
    required this.activeIndex,
    required this.onChanged,
  });

  final List<MemoraSegmentedTab> tabs;
  final int activeIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MemoraMotion.reduceMotion(context);

    return Row(
      children: [
        for (final (index, tab) in tabs.indexed) ...[
          if (index > 0) const SizedBox(width: MemoraSpacing.sm),
          Expanded(
            child: _SegmentedTabPill(
              tab: tab,
              active: index == activeIndex,
              reduceMotion: reduceMotion,
              onTap: () => onChanged(index),
            ),
          ),
        ],
      ],
    );
  }
}

class _SegmentedTabPill extends StatelessWidget {
  const _SegmentedTabPill({
    required this.tab,
    required this.active,
    required this.reduceMotion,
    required this.onTap,
  });

  final MemoraSegmentedTab tab;
  final bool active;
  final bool reduceMotion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final foreground = active ? MemoraColors.paper : MemoraColors.textSecondary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(MemoraRadius.pill),
        child: AnimatedContainer(
          duration: reduceMotion ? Duration.zero : MemoraMotion.quick,
          curve: MemoraMotion.enterCurve,
          padding: const EdgeInsets.symmetric(
            vertical: MemoraSpacing.sm,
            horizontal: MemoraSpacing.sm,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(MemoraRadius.pill),
            gradient: active ? MemoraColors.signatureGradient : null,
            color: active ? null : MemoraColors.surface1,
            border: active ? null : Border.all(color: MemoraColors.border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(tab.icon, size: 16, color: foreground),
              const SizedBox(width: MemoraSpacing.xs),
              Flexible(
                child: Text(
                  tab.label,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.labelMedium?.copyWith(
                    color: foreground,
                    fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
