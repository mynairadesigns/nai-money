import 'package:flutter/material.dart';

import '../theme/shapes.dart';
import '../theme/spacing.dart';

/// One item for the [PickGrid] — a multi-select card.
///
/// Identity is `key`. Label, icon, and the color hex (no `#`) drive the
/// rendering. Selection state is computed from the `Set<String> selected`
/// the parent owns.
class PickItem {
  const PickItem({
    required this.key,
    required this.label,
    required this.iconData,
    required this.colorHex,
  });
  final String key;
  final String label;
  final IconData iconData;
  final String colorHex;
}

/// 2-column responsive multi-select grid. Used originally by the
/// transactions filter sheet, lifted here so every P3 feature (budget
/// scope picker, recurring template picker, debt category multi-select)
/// shares the same look.
///
/// Each tile = colored icon avatar + label, with a primary border + check
/// badge when selected. Pattern matches the setup wizard's category step.
class PickGrid extends StatelessWidget {
  const PickGrid({
    required this.items,
    required this.selected,
    required this.onToggle,
    super.key,
  });
  final List<PickItem> items;
  final Set<String> selected;
  final void Function(String key, bool selected) onToggle;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = (constraints.maxWidth - AppSpacing.md) / 2;
        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            for (final item in items)
              SizedBox(
                width: cardWidth,
                child: PickCard(
                  item: item,
                  selected: selected.contains(item.key),
                  onTap: () =>
                      onToggle(item.key, !selected.contains(item.key)),
                ),
              ),
          ],
        );
      },
    );
  }
}

class PickCard extends StatelessWidget {
  const PickCard({
    required this.item,
    required this.selected,
    required this.onTap,
    super.key,
  });
  final PickItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = Color(int.parse('FF${item.colorHex}', radix: 16));

    final bg = selected
        ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
        : theme.colorScheme.surface;
    final borderColor = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.outlineVariant;
    final borderWidth = selected ? 1.5 : 1.0;

    return Material(
      color: bg,
      borderRadius: AppBorderRadius.lg,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.md,
            horizontal: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            border: Border.all(color: borderColor, width: borderWidth),
            borderRadius: AppBorderRadius.lg,
          ),
          child: Stack(
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: AppBorderRadius.full,
                    ),
                    child: Icon(item.iconData, color: Colors.white, size: 20),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: selected
                          ? theme.colorScheme.onPrimaryContainer
                          : theme.colorScheme.onSurface,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
              if (selected)
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.check,
                      size: 12,
                      color: theme.colorScheme.onPrimary,
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
