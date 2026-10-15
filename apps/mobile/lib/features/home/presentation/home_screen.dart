import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/shapes.dart';
import '../../../core/theme/spacing.dart';
import '../../ads/widgets/home_banner_ad.dart';
import '../../budgets/widgets/budget_progress_home.dart';
import '../../insights/presentation/insights_section.dart';
import '../../transactions/providers/transactions_list_provider.dart';
import '../../transactions/widgets/transaction_row.dart';
import '../../wallets/widgets/wallet_carousel.dart';
import '../providers/month_summary_provider.dart';

/// PRD §11.1: dashboard with greeting + AI insight, wallet carousel,
/// month summary card, budget progress, recent transactions, AI insights.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // Vertical padding only on the parent so the wallet carousel can run
    // past the right edge of the screen. Per-section horizontal padding
    // is applied by `_HPad` below.
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
          children: [
            _HPad(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Good morning',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Your week looks strong 👍',
                          style: theme.textTheme.headlineMedium,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings_outlined),
                    onPressed: () => context.push('/settings'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            const _HPad(child: _MonthSummaryCard()),
            const SizedBox(height: AppSpacing.md),

            _HPad(
              child: _SectionHeader(
                title: 'Wallets',
                actionLabel: 'Add',
                onAction: () => context.push('/wallet/add'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            // Intentionally NOT wrapped in _HPad — the carousel owns its
            // own start-edge padding so cards scroll past the right edge.
            const WalletCarousel(),
            const SizedBox(height: AppSpacing.md),

            _HPad(
              child: _SectionHeader(
                title: 'Budgets',
                actionLabel: 'View all',
                onAction: () => context.push('/budgets'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            const _HPad(child: BudgetProgressHome()),
            const SizedBox(height: AppSpacing.md),

            const _HPad(child: InsightsSection()),
            const SizedBox(height: AppSpacing.md),

            _HPad(
              child: _SectionHeader(
                title: 'Recent transactions',
                actionLabel: 'View all',
                onAction: () => context.go('/transactions'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            const _RecentTransactions(),
            const SizedBox(height: AppSpacing.lg),

            // Bottom-of-Home banner ad (free users only — the widget
            // renders SizedBox.shrink() when ads are disabled, so no
            // outer `if (adsEnabled)` guard is needed).
            const _HPad(child: HomeBannerAd()),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }
}

/// "This month" totals. Live-derived from Drift via [monthSummaryProvider],
/// so adding, editing, or deleting a transaction updates it immediately.
class _MonthSummaryCard extends ConsumerWidget {
  const _MonthSummaryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(monthSummaryProvider);
    final summary = async.value;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('This month', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.md),
            if (async.hasError)
              Text(
                'Could not load this month.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              )
            else
              Row(
                children: [
                  _Stat(
                    label: 'Income',
                    amount: _money(summary?.income, summary),
                    color: theme.colorScheme.secondary,
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  _Stat(
                    label: 'Expenses',
                    amount: _money(summary?.expenses, summary),
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  _Stat(
                    label: 'Net',
                    amount: _money(summary?.net, summary),
                    // Net going negative is the one number worth calling
                    // out — you outspent what came in.
                    color: (summary?.net ?? 0) < 0
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurface,
                  ),
                ],
              ),
            if (summary != null && summary.isMixedCurrency) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Mixed currencies — totals are a raw sum.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Matches the Reports summary formatting: currency code prefix when a
  /// single currency applies, bare number when the month is mixed.
  String _money(double? value, MonthSummary? summary) {
    if (value == null || summary == null) return '—';
    final code = summary.currencyCode;
    final text = value.toStringAsFixed(2);
    return code == null ? text : '$code $text';
  }
}

class _RecentTransactions extends ConsumerWidget {
  const _RecentTransactions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(recentTransactionsProvider);
    return async.when(
      loading: () => const SizedBox(
        height: 96,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (e, _) => _HPad(
        child: Text(
          'Could not load recent transactions.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return _HPad(
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: AppBorderRadius.lg,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.receipt_long_outlined,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      'No transactions yet. Tap + to add one.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return _HPad(
          child: Card(
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) const Divider(height: 0),
                  TransactionRow(
                    transaction: rows[i],
                    onTap: () => context.push('/transaction/${rows[i].id}'),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HPad extends StatelessWidget {
  const _HPad({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: child,
      );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.amount, required this.color});
  final String label;
  final String amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          )),
          const SizedBox(height: 2),
          Text(amount, style: theme.textTheme.titleLarge?.copyWith(color: color)),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.actionLabel,
    required this.onAction,
  });
  final String title;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: theme.textTheme.titleLarge),
        TextButton(onPressed: onAction, child: Text(actionLabel)),
      ],
    );
  }
}
