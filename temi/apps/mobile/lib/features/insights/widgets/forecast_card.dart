import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/shapes.dart';
import '../../../core/theme/spacing.dart';
import '../../wallets/providers/wallets_list_provider.dart';
import '../data/forecast_result.dart';
import '../providers/insights_providers.dart';

/// Forecast card — projected end-of-month spending + per-category trend
/// chips (PRD §7.4 / §11.5).
class ForecastCard extends ConsumerWidget {
  const ForecastCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(forecastProvider);
    return async.when(
      loading: () => const _Skeleton(),
      error: (_, _) => const SizedBox.shrink(),
      data: (forecast) {
        if (forecast == null) return const SizedBox.shrink();
        return _Body(forecast: forecast);
      },
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.forecast});
  final ForecastResult forecast;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // Currency: first visible wallet's currency, falling back to USD.
    // Mirrors the pattern used in receipt_scanner_screen.dart.
    final wallets = ref.watch(visibleWalletsProvider).value ?? const [];
    final currency = wallets.isNotEmpty ? wallets.first.currency : 'NGN';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {},
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$currency ${forecast.projectedTotal.toStringAsFixed(0)}',
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                forecast.headline,
                style: theme.textTheme.bodyMedium,
              ),
              if (forecast.breakdown.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final b in forecast.breakdown.take(4))
                      _TrendChip(item: b),
                  ],
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              Text(
                'Projected end-of-month — AI',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrendChip extends StatelessWidget {
  const _TrendChip({required this.item});
  final ForecastBreakdownItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    late final IconData icon;
    late final Color color;
    switch (item.trend) {
      case ForecastTrend.up:
        icon = Icons.trending_up;
        color = theme.colorScheme.error;
      case ForecastTrend.down:
        icon = Icons.trending_down;
        color = theme.colorScheme.secondary;
      case ForecastTrend.flat:
        icon = Icons.trending_flat;
        color = theme.colorScheme.onSurfaceVariant;
    }
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: AppBorderRadius.full,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: AppSpacing.xs),
          Text(
            item.categoryName,
            style: theme.textTheme.labelMedium,
          ),
        ],
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 96,
      child: Card(
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: AppBorderRadius.lg,
          ),
        ),
      ),
    );
  }
}
