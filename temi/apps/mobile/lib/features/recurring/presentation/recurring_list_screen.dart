import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/database_provider.dart';
import '../../../core/theme/shapes.dart';
import '../../../core/theme/spacing.dart';
import '../../../data/local/app_database.dart';
import '../../categories/data/category_catalog.dart';
import '../data/recurring_catalog.dart';
import '../providers/recurring_controller.dart';
import '../providers/recurring_list_provider.dart';

/// `/recurring` — two-section list of the user's recurring rules
/// (Active + Paused) with a FAB that opens the create form. PRD §6.6.
class RecurringListScreen extends ConsumerWidget {
  const RecurringListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final activeAsync = ref.watch(activeRecurringRulesProvider);
    final pausedAsync = ref.watch(pausedRecurringRulesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Recurring')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/recurring/add'),
        icon: const Icon(Icons.add),
        label: const Text('Add rule'),
      ),
      body: SafeArea(
        child: activeAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Text(
              'Could not load recurring rules.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
          data: (active) {
            final paused = pausedAsync.value ?? const <RecurringRule>[];
            if (active.isEmpty && paused.isEmpty) {
              return _EmptyState(theme: theme);
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.xxxl,
              ),
              children: [
                if (active.isNotEmpty) ...[
                  _SectionHeader(label: 'Active'),
                  const SizedBox(height: AppSpacing.sm),
                  for (final r in active) _RecurringListRow(rule: r),
                ],
                if (active.isNotEmpty && paused.isNotEmpty)
                  const SizedBox(height: AppSpacing.lg),
                if (paused.isNotEmpty) ...[
                  _SectionHeader(label: 'Paused'),
                  const SizedBox(height: AppSpacing.sm),
                  for (final r in paused) _RecurringListRow(rule: r),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _RecurringListRow extends ConsumerWidget {
  const _RecurringListRow({required this.rule});
  final RecurringRule rule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final template = decodeRecurringTemplate(rule.transactionTemplate);
    final amount = (template['amount'] as num?)?.toDouble() ?? 0;
    final note = template['note'] as String?;
    final categoryId = template['categoryId'] as String?;

    // Lookup the category for the leading icon/color (kept reactive
    // via the DAO stream so renames in /category/manage reflect here).
    final categories = ref.watch(categoryDaoProvider).watchAll();

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: StreamBuilder<List<Category>>(
        stream: categories,
        builder: (context, snap) {
          Category? category;
          if (snap.hasData && categoryId != null) {
            for (final c in snap.data!) {
              if (c.id == categoryId) {
                category = c;
                break;
              }
            }
          }
          final color = category != null
              ? Color(int.parse('FF${category.color}', radix: 16))
              : theme.colorScheme.surfaceContainerHighest;
          final icon = iconForCategory(category?.iconName ?? '');
          final title = (note != null && note.isNotEmpty)
              ? note
              : (category?.name ?? 'Recurring');

          return Card(
            margin: EdgeInsets.zero,
            child: InkWell(
              onTap: () => context.push('/recurring/${rule.id}'),
              borderRadius: AppBorderRadius.lg,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.md,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: AppBorderRadius.full,
                      ),
                      child: Icon(icon, color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${_formatAmount(amount)} · '
                            '${summarizeFrequency(rule.frequency, rule.interval)}'
                            ' · Next: ${_formatShortDate(rule.nextDueDate)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (rule.isPaused)
                      Padding(
                        padding: const EdgeInsets.only(left: AppSpacing.sm),
                        child: Icon(
                          Icons.pause_circle_outline,
                          color: theme.colorScheme.onSurfaceVariant,
                          size: 20,
                        ),
                      ),
                    Icon(
                      Icons.chevron_right,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      label,
      style: theme.textTheme.titleSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.event_repeat_outlined,
              size: 48,
              color: theme.colorScheme.outlineVariant,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'No recurring rules yet',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Tap Add rule to set up rent, subscriptions, or any '
              'income that repeats on a schedule.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatAmount(double n) {
  final abs = n.abs();
  return abs.toStringAsFixed(abs.truncateToDouble() == abs ? 0 : 2);
}

String _formatShortDate(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final local = d.toLocal();
  return '${local.day} ${months[local.month - 1]}';
}
