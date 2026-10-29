import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/database_provider.dart';
import '../../../core/theme/shapes.dart';
import '../../../core/theme/spacing.dart';
import '../../../data/local/app_database.dart';
import '../../categories/data/category_catalog.dart';
import '../../wallets/data/wallet_catalog.dart';
import '../providers/budget_progress_provider.dart';

/// Single budget tile/card showing the linked category/wallet, progress
/// bar, spent vs total, and days-remaining. Coloured per
/// [BudgetStatus] — green / yellow / red against the warm-clay primary.
///
/// Resolves its own [BudgetProgress] via `budgetProgressProvider.family`,
/// so callers only pass the budget id. Optional `onTap` makes the card
/// tappable (routes to detail in list contexts).
class BudgetProgressCard extends ConsumerWidget {
  const BudgetProgressCard({
    required this.budgetId,
    this.onTap,
    super.key,
  });

  final String budgetId;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final progressAsync = ref.watch(budgetProgressProvider(budgetId));

    return progressAsync.when(
      loading: () => const SizedBox(
        height: 96,
        child: Card(
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      ),
      error: (e, _) => Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Text(
            'Could not load budget.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ),
      ),
      data: (progress) {
        if (progress == null) {
          return const SizedBox.shrink();
        }
        return _CardBody(progress: progress, onTap: onTap);
      },
    );
  }
}

class _CardBody extends ConsumerWidget {
  const _CardBody({required this.progress, required this.onTap});
  final BudgetProgress progress;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final b = progress.budget;
    final categoryAsync =
        b.categoryId == null ? null : ref.watch(categoryDaoProvider).watchAll();
    final walletAsync =
        b.walletId == null ? null : ref.watch(walletDaoProvider).watchAll();

    return StreamBuilder<List<Category>>(
      stream: categoryAsync,
      builder: (context, catSnap) {
        return StreamBuilder<List<Wallet>>(
          stream: walletAsync,
          builder: (context, walSnap) {
            Category? cat;
            if (b.categoryId != null && catSnap.hasData) {
              for (final c in catSnap.data!) {
                if (c.id == b.categoryId) {
                  cat = c;
                  break;
                }
              }
            }
            Wallet? wal;
            if (b.walletId != null && walSnap.hasData) {
              for (final w in walSnap.data!) {
                if (w.id == b.walletId) {
                  wal = w;
                  break;
                }
              }
            }

            final accent = _accent(cat, wal, theme);
            final iconData = _icon(cat, wal);
            final label = _label(cat, wal);

            return Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: accent,
                              borderRadius: AppBorderRadius.full,
                            ),
                            child: Icon(iconData,
                                color: Colors.white, size: 22),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall,
                                ),
                                Text(
                                  _periodLabel(b),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _StatusBadge(status: progress.status, theme: theme),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _ProgressBar(progress: progress),
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${b.currency} ${progress.spent.toStringAsFixed(0)} '
                              'of ${b.currency} ${b.amount.toStringAsFixed(0)}',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          Text(
                            progress.daysRemaining == 0
                                ? 'Ended'
                                : '${progress.daysRemaining} day${progress.daysRemaining == 1 ? '' : 's'} left',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Color _accent(Category? cat, Wallet? wal, ThemeData theme) {
    if (cat != null) return Color(int.parse('FF${cat.color}', radix: 16));
    if (wal != null) return Color(int.parse('FF${wal.color}', radix: 16));
    return theme.colorScheme.primary;
  }

  IconData _icon(Category? cat, Wallet? wal) {
    if (cat != null) return iconForCategory(cat.iconName);
    if (wal != null) {
      return kWalletIconCatalog[wal.iconName] ??
          Icons.account_balance_wallet_outlined;
    }
    return Icons.donut_small_outlined;
  }

  String _label(Category? cat, Wallet? wal) {
    if (cat != null && wal != null) return '${cat.name} · ${wal.name}';
    if (cat != null) return cat.name;
    if (wal != null) return wal.name;
    return 'Budget';
  }

  String _periodLabel(Budget b) {
    switch (b.period) {
      case 'weekly':
        return 'Weekly';
      case 'monthly':
        return 'Monthly';
      case 'custom':
        return 'Custom range';
      default:
        return b.period;
    }
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status, required this.theme});
  final BudgetStatus status;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    late final Color bg;
    late final Color fg;
    late final String label;
    switch (status) {
      case BudgetStatus.green:
        bg = theme.colorScheme.secondaryContainer;
        fg = theme.colorScheme.onSecondaryContainer;
        label = 'On track';
      case BudgetStatus.yellow:
        bg = theme.colorScheme.tertiaryContainer;
        fg = theme.colorScheme.onTertiaryContainer;
        label = 'Watch';
      case BudgetStatus.red:
        bg = theme.colorScheme.errorContainer;
        fg = theme.colorScheme.onErrorContainer;
        label = 'Over';
    }
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppBorderRadius.full,
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.progress});
  final BudgetProgress progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pct = (progress.pctUsed / 100).clamp(0.0, 1.0);
    late final Color color;
    switch (progress.status) {
      case BudgetStatus.green:
        color = theme.colorScheme.secondary;
      case BudgetStatus.yellow:
        color = theme.colorScheme.tertiary;
      case BudgetStatus.red:
        color = theme.colorScheme.error;
    }
    return ClipRRect(
      borderRadius: AppBorderRadius.full,
      child: LinearProgressIndicator(
        value: pct,
        minHeight: 8,
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        valueColor: AlwaysStoppedAnimation(color),
      ),
    );
  }
}
