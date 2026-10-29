import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/shapes.dart';
import '../../../core/theme/spacing.dart';
import '../../insights/data/health_score_result.dart';
import '../../insights/providers/insights_providers.dart';

/// PRD §11.6: AI Coach tab — health score card, insights hub, chat CTA.
class AICoachScreen extends StatelessWidget {
  const AICoachScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('AI Coach')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            _HealthScoreCard(onTap: () => context.push('/ai/health-score')),
            const SizedBox(height: AppSpacing.lg),

            Text('Insights', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            _InsightCard(
              icon: Icons.trending_up,
              title: 'Forecast',
              body: 'See where your spending lands by end of month.',
              onTap: () => context.push('/ai/insights'),
            ),
            const SizedBox(height: AppSpacing.sm),
            _InsightCard(
              icon: Icons.notifications_outlined,
              title: 'Anomalies',
              body: 'Spot unusual spending the moment it happens.',
              onTap: () => context.push('/ai/insights'),
            ),
            const SizedBox(height: AppSpacing.sm),
            _InsightCard(
              icon: Icons.subscriptions_outlined,
              title: 'Subscriptions',
              body: 'Find recurring charges you may have forgotten about.',
              onTap: () => context.push('/settings/subscriptions'),
            ),
            const SizedBox(height: AppSpacing.xl),

            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => context.push('/ai/chat'),
                icon: const Icon(Icons.chat_bubble_outline),
                label: const Text('Chat with Coach Temi'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Hero entry to the health-score drill-down. Shows the real score + label
/// once [healthScoreProvider] resolves; while loading or when empty (no
/// data / offline / quota spent) it falls back to a “—” + CTA copy. The
/// provider is shared with the Home card and the detail screen, so this
/// doesn't fire an extra quota call.
class _HealthScoreCard extends ConsumerWidget {
  const _HealthScoreCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final result = ref.watch(healthScoreProvider).value;

    return InkWell(
      onTap: onTap,
      borderRadius: AppBorderRadius.lg,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          borderRadius: AppBorderRadius.lg,
        ),
        child: Row(
          children: [
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLowest,
                shape: BoxShape.circle,
              ),
              child: Text(
                result != null ? '${result.score}' : '—',
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result != null
                        ? 'Health: ${result.label.displayName}'
                        : 'Financial health score',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    result != null && result.actionableTips.isNotEmpty
                        ? result.actionableTips.first
                        : 'Add transactions and budgets to compute your score.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                color: theme.colorScheme.onPrimaryContainer),
          ],
        ),
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: AppBorderRadius.lg,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Icon(icon, color: theme.colorScheme.primary),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      body,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
