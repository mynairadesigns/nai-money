import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/database_provider.dart';
import '../../../core/theme/shapes.dart';
import '../../../core/theme/spacing.dart';
import '../../../data/local/app_database.dart';
import '../../categories/data/category_catalog.dart';
import '../../transactions/widgets/transaction_row.dart';
import '../../wallets/data/wallet_catalog.dart';
import '../data/recurring_catalog.dart';
import '../providers/recurring_controller.dart';

/// `/recurring/:id` — per-rule detail. Header summarizes the template;
/// the body lists locally-known transactions stamped with this rule's id.
///
/// Note: server-generated transactions only appear here after the next
/// pull-direction Firestore sync — see the empty-state subtitle below.
class RecurringDetailScreen extends ConsumerWidget {
  const RecurringDetailScreen({required this.id, super.key});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final ruleAsync = ref.watch(_recurringRuleByIdProvider(id));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recurring rule'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (action) =>
                _onAction(context, ref, action, ruleAsync.value),
            itemBuilder: (_) {
              final rule = ruleAsync.value;
              return [
                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                if (rule != null)
                  PopupMenuItem(
                    value: rule.isPaused ? 'resume' : 'pause',
                    child: Text(rule.isPaused ? 'Resume' : 'Pause'),
                  ),
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ];
            },
          ),
        ],
      ),
      body: ruleAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text(
            'Could not load this rule.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ),
        data: (rule) {
          if (rule == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Text(
                  'This rule no longer exists.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            );
          }
          return _DetailBody(rule: rule);
        },
      ),
    );
  }

  Future<void> _onAction(
    BuildContext context,
    WidgetRef ref,
    String action,
    RecurringRule? rule,
  ) async {
    if (rule == null) return;
    final ctrl = ref.read(recurringControllerProvider.notifier);
    switch (action) {
      case 'edit':
        context.push('/recurring/add', extra: rule);
        break;
      case 'pause':
        await ctrl.pause(rule.id);
        break;
      case 'resume':
        await ctrl.resume(rule.id);
        break;
      case 'delete':
        await _confirmDelete(context, ref, rule);
        break;
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    RecurringRule rule,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this rule?'),
        content: const Text(
          'Future occurrences will stop. Past transactions are not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await ref.read(recurringControllerProvider.notifier).delete(rule.id);
    if (!context.mounted) return;
    final result = ref.read(recurringControllerProvider);
    if (result.hasError) return;
    context.pop();
  }
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({required this.rule});
  final RecurringRule rule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final template = decodeRecurringTemplate(rule.transactionTemplate);
    final amount = (template['amount'] as num?)?.toDouble() ?? 0;
    final note = template['note'] as String?;
    final walletId = template['walletId'] as String?;
    final categoryId = template['categoryId'] as String?;
    final type = (template['type'] as String?) ?? 'expense';

    final categoriesStream = ref.watch(categoryDaoProvider).watchAll();
    final walletsStream = ref.watch(walletDaoProvider).watchAll();
    final txStream = ref.watch(transactionDaoProvider).watchAll();

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        StreamBuilder<List<Category>>(
          stream: categoriesStream,
          builder: (context, catSnap) {
            return StreamBuilder<List<Wallet>>(
              stream: walletsStream,
              builder: (context, walSnap) {
                Category? category;
                if (catSnap.hasData && categoryId != null) {
                  for (final c in catSnap.data!) {
                    if (c.id == categoryId) {
                      category = c;
                      break;
                    }
                  }
                }
                Wallet? wallet;
                if (walSnap.hasData && walletId != null) {
                  for (final w in walSnap.data!) {
                    if (w.id == walletId) {
                      wallet = w;
                      break;
                    }
                  }
                }
                return _HeaderCard(
                  rule: rule,
                  amount: amount,
                  note: note,
                  type: type,
                  category: category,
                  wallet: wallet,
                );
              },
            );
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Generated transactions',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.sm),
        StreamBuilder<List<Transaction>>(
          stream: txStream,
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              );
            }
            final matching = snap.data!
                .where((t) => t.recurringRuleId == rule.id)
                .toList()
              ..sort((a, b) => b.date.compareTo(a.date));

            if (matching.isEmpty) return _EmptyTxRow(theme: theme);
            return _GroupedTxList(transactions: matching);
          },
        ),
      ],
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.rule,
    required this.amount,
    required this.note,
    required this.type,
    required this.category,
    required this.wallet,
  });

  final RecurringRule rule;
  final double amount;
  final String? note;
  final String type;
  final Category? category;
  final Wallet? wallet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isIncome = type == 'income';
    final categoryColor = category != null
        ? Color(int.parse('FF${category!.color}', radix: 16))
        : theme.colorScheme.surfaceContainerHighest;
    final categoryIcon = iconForCategory(category?.iconName ?? '');
    final walletIcon = wallet == null
        ? Icons.account_balance_wallet_outlined
        : (kWalletIconCatalog[wallet!.iconName] ??
            Icons.account_balance_wallet_outlined);
    final currency = wallet?.currency ?? '';
    final amountColor = isIncome
        ? theme.colorScheme.secondary
        : theme.colorScheme.primary;
    final sign = isIncome ? '+' : '−';

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: categoryColor,
                    borderRadius: AppBorderRadius.full,
                  ),
                  child: Icon(categoryIcon, color: Colors.white, size: 24),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (note != null && note!.isNotEmpty)
                            ? note!
                            : (category?.name ?? 'Recurring'),
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        category?.name ?? (isIncome ? 'Income' : 'Expense'),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '$sign${currency.isEmpty ? '' : '$currency '}'
                  '${_formatAmount(amount)}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: amountColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.md),
            _MetaRow(
              icon: walletIcon,
              label: 'Wallet',
              value: wallet?.name ?? '—',
            ),
            const SizedBox(height: AppSpacing.sm),
            _MetaRow(
              icon: Icons.event_repeat_outlined,
              label: 'Cadence',
              value: summarizeFrequency(rule.frequency, rule.interval),
            ),
            const SizedBox(height: AppSpacing.sm),
            _MetaRow(
              icon: Icons.schedule_outlined,
              label: rule.isPaused ? 'Paused — next would be' : 'Next due',
              value: _formatDate(rule.nextDueDate),
            ),
            const SizedBox(height: AppSpacing.sm),
            _MetaRow(
              icon: Icons.tune_outlined,
              label: 'Mode',
              value: labelForRecurringMode(rule.mode),
            ),
            if (rule.endDate != null) ...[
              const SizedBox(height: AppSpacing.sm),
              _MetaRow(
                icon: Icons.event_busy_outlined,
                label: 'Ends',
                value: _formatDate(rule.endDate!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Text(value, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}

class _GroupedTxList extends StatelessWidget {
  const _GroupedTxList({required this.transactions});
  final List<Transaction> transactions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groups = <DateTime, List<Transaction>>{};
    for (final t in transactions) {
      final d = t.date.toLocal();
      final key = DateTime(d.year, d.month, d.day);
      (groups[key] ??= []).add(t);
    }
    final orderedDays = groups.keys.toList()..sort((a, b) => b.compareTo(a));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final day in orderedDays) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.sm,
            ),
            child: Text(
              formatTransactionDayHeader(day),
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < groups[day]!.length; i++) ...[
                  if (i > 0) const Divider(height: 0),
                  TransactionRow(
                    transaction: groups[day]![i],
                    onTap: () => GoRouter.of(context)
                        .push('/transaction/${groups[day]![i].id}'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _EmptyTxRow extends StatelessWidget {
  const _EmptyTxRow({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: AppBorderRadius.lg,
      ),
      child: Row(
        children: [
          Icon(
            Icons.cloud_sync_outlined,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'Server-generated transactions appear here after the next '
              'pull-sync slice.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatAmount(double n) {
  final abs = n.abs();
  return abs.toStringAsFixed(abs.truncateToDouble() == abs ? 0 : 2);
}

String _formatDate(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final local = d.toLocal();
  return '${local.day} ${months[local.month - 1]} ${local.year}';
}

/// One-shot Drift lookup keyed by rule id; rebuilds when the DAO stream
/// emits. Mirrors the `_budgetByIdProvider` pattern.
final _recurringRuleByIdProvider =
    StreamProvider.family<RecurringRule?, String>((ref, id) async* {
  final dao = ref.watch(recurringRuleDaoProvider);
  await for (final rows in dao.watchAll()) {
    yield rows.where((r) => r.id == id).firstOrNull;
  }
});
