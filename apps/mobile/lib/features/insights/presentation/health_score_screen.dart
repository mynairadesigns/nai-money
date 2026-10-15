import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/shapes.dart';
import '../../../core/theme/spacing.dart';
import '../data/health_score_result.dart';
import '../providers/insights_providers.dart';

/// Health-score drill-down reached from the AI Coach tab (PRD §7.8 / §11.5).
/// Richer than the Home [HealthScoreCard]: shows the score hero, the full
/// per-factor breakdown, and every actionable tip (the card only previews
/// the top two). Shares [healthScoreProvider] so it doesn't burn a second
/// quota call when navigated from a screen that already loaded the card.
class HealthScoreScreen extends ConsumerWidget {
  const HealthScoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(healthScoreProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Financial Health Score')),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          // Errors are swallowed to null by the provider; treat both as empty.
          error: (_, _) => const _EmptyState(),
          data: (result) =>
              result == null ? const _EmptyState() : _Body(result: result),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.result});
  final HealthScoreResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _labelColor(theme, result.label);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        // Score hero.
        Center(
          child: Column(
            children: [
              SizedBox(
                width: 140,
                height: 140,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 140,
                      height: 140,
                      child: CircularProgressIndicator(
                        value: (result.score / 100).clamp(0.0, 1.0),
                        strokeWidth: 10,
                        backgroundColor:
                            theme.colorScheme.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation(color),
                      ),
                    ),
                    Text(
                      '${result.score}',
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                result.label.displayName,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),

        // Per-factor breakdown.
        if (result.factors.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xl),
          Text('What goes into this', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          for (final f in result.factors) _FactorTile(factor: f),
        ],

        // All actionable tips.
        if (result.actionableTips.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Text('Ways to improve', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          for (final tip in result.actionableTips)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.tips_and_updates_outlined,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(tip, style: theme.textTheme.bodyMedium)),
                ],
              ),
            ),
        ],
      ],
    );
  }

  Color _labelColor(ThemeData theme, HealthScoreLabel label) {
    switch (label) {
      case HealthScoreLabel.excellent:
      case HealthScoreLabel.good:
        return theme.colorScheme.secondary;
      case HealthScoreLabel.fair:
        return theme.colorScheme.tertiary;
      case HealthScoreLabel.poor:
        return theme.colorScheme.error;
    }
  }
}

class _FactorTile extends StatelessWidget {
  const _FactorTile({required this.factor});
  final HealthFactor factor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    factor.name,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                Text(
                  '${(factor.value * 100).round()}%',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            ClipRRect(
              borderRadius: AppBorderRadius.sm,
              child: LinearProgressIndicator(
                value: factor.value.clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
            if (factor.explanation.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                factor.explanation,
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
}

/// Shown when the score can't be computed yet (no data, offline, or the
/// monthly AI quota is spent).
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.favorite_outline,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'No score yet',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Add transactions, budgets, and goals so we can score your '
              'finances across saving, spending, and debt. Needs a connection.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
