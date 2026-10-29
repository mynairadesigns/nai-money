import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/shapes.dart';
import '../../../core/theme/spacing.dart';
import '../../../data/local/app_database.dart';
import '../data/debt_status.dart';
import '../providers/debts_list_provider.dart';

/// `/debts` route — two top-level sections (Lent / Borrowed). Within
/// each, rows split into Active vs Settled buckets so settled debts
/// stay visible for receipts but don't clutter the live ledger.
class DebtsListScreen extends ConsumerWidget {
  const DebtsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final asyncRows = ref.watch(debtsListProvider);
    final lent = ref.watch(lentDebtsProvider).value ?? const <Debt>[];
    final borrowed = ref.watch(borrowedDebtsProvider).value ?? const <Debt>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Debts')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/debt/add'),
        icon: const Icon(Icons.add),
        label: const Text('Add debt'),
      ),
      body: SafeArea(
        child: asyncRows.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Text(
              'Could not load debts.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
          data: (_) {
            if (lent.isEmpty && borrowed.isEmpty) {
              return _EmptyState(theme: theme);
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.xxxl, // leave room for the FAB
              ),
              children: [
                if (lent.isNotEmpty) ...[
                  _SectionHeader(label: 'Lent (owed to you)'),
                  const SizedBox(height: AppSpacing.sm),
                  ..._buildBuckets(lent),
                ],
                if (lent.isNotEmpty && borrowed.isNotEmpty)
                  const SizedBox(height: AppSpacing.lg),
                if (borrowed.isNotEmpty) ...[
                  _SectionHeader(label: 'Borrowed (you owe)'),
                  const SizedBox(height: AppSpacing.sm),
                  ..._buildBuckets(borrowed),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  List<Widget> _buildBuckets(List<Debt> rows) {
    final active = <Debt>[];
    final settled = <Debt>[];
    for (final d in rows) {
      if (debtStatus(d) == DebtStatus.settled) {
        settled.add(d);
      } else {
        active.add(d);
      }
    }
    return [
      if (active.isNotEmpty) ...[
        _SubHeader(label: 'Active'),
        const SizedBox(height: AppSpacing.sm),
        for (final d in active) _DebtTile(debt: d),
      ],
      if (active.isNotEmpty && settled.isNotEmpty)
        const SizedBox(height: AppSpacing.md),
      if (settled.isNotEmpty) ...[
        _SubHeader(label: 'Settled'),
        const SizedBox(height: AppSpacing.sm),
        for (final d in settled) _DebtTile(debt: d),
      ],
    ];
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

class _SubHeader extends StatelessWidget {
  const _SubHeader({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      label,
      style: theme.textTheme.labelMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _DebtTile extends StatelessWidget {
  const _DebtTile({required this.debt});
  final Debt debt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = debtStatus(debt);
    final initial = debt.contactName.isNotEmpty
        ? debt.contactName.trim()[0].toUpperCase()
        : '?';

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: InkWell(
        borderRadius: AppBorderRadius.lg,
        onTap: () => context.push('/debt/${debt.id}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: AppBorderRadius.full,
                ),
                child: Text(
                  initial,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      debt.contactName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    Text(
                      '${debt.currency} ${_format(debt.remainingAmount)} '
                      'of ${debt.currency} ${_format(debt.originalAmount)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _StatusBadge(status: status),
            ],
          ),
        ),
      ),
    );
  }

  String _format(double n) {
    final abs = n.abs();
    return abs.toStringAsFixed(abs.truncateToDouble() == abs ? 0 : 2);
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final DebtStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (bg, fg) = switch (status) {
      DebtStatus.settled => (
          theme.colorScheme.secondaryContainer,
          theme.colorScheme.onSecondaryContainer,
        ),
      DebtStatus.overdue => (
          theme.colorScheme.errorContainer,
          theme.colorScheme.onErrorContainer,
        ),
      DebtStatus.dueSoon => (
          theme.colorScheme.tertiaryContainer,
          theme.colorScheme.onTertiaryContainer,
        ),
      DebtStatus.open => (
          theme.colorScheme.surfaceContainerHighest,
          theme.colorScheme.onSurfaceVariant,
        ),
    };
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
        debtStatusLabel(status),
        style: theme.textTheme.labelSmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.w600,
        ),
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
              Icons.handshake_outlined,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.md),
            Text('No debts tracked', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Tap Add debt to record money you lent or borrowed.',
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
