import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/database_provider.dart';
import '../../../core/theme/shapes.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/utils/validators.dart';
import '../../../data/local/app_database.dart';
import '../data/debt_status.dart';
import '../providers/debts_controller.dart';

/// `/debt/:id` — per-debt detail view. Header summarises the debt;
/// body lists payment history and exposes Add payment / Mark settled
/// / Delete.
class DebtDetailScreen extends ConsumerWidget {
  const DebtDetailScreen({required this.id, super.key});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final debtAsync = ref.watch(_debtByIdProvider(id));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Debt'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (action) =>
                _onAction(context, ref, action, debtAsync.value),
            itemBuilder: (_) {
              final debt = debtAsync.value;
              final isSettled =
                  debt != null && debtStatus(debt) == DebtStatus.settled;
              return [
                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                if (!isSettled)
                  const PopupMenuItem(
                      value: 'settle', child: Text('Mark settled')),
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ];
            },
          ),
        ],
      ),
      body: debtAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text(
            'Could not load this debt.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ),
        data: (debt) {
          if (debt == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Text(
                  'This debt no longer exists.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            );
          }
          return _DetailBody(debt: debt);
        },
      ),
    );
  }

  Future<void> _onAction(
    BuildContext context,
    WidgetRef ref,
    String action,
    Debt? debt,
  ) async {
    if (debt == null) return;
    switch (action) {
      case 'edit':
        context.push('/debt/add', extra: debt);
        break;
      case 'settle':
        await _confirmSettle(context, ref, debt);
        break;
      case 'delete':
        await _confirmDelete(context, ref, debt);
        break;
    }
  }

  Future<void> _confirmSettle(
    BuildContext context,
    WidgetRef ref,
    Debt debt,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark settled?'),
        content: const Text(
          'This zeros out the remaining balance. Past payment history '
          'is preserved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Mark settled'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await ref.read(debtsControllerProvider.notifier).markSettled(debt.id);
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Debt debt,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this debt?'),
        content: const Text(
          'The debt and its payment history will be removed.',
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
    await ref.read(debtsControllerProvider.notifier).delete(debt.id);
    if (!context.mounted) return;
    final result = ref.read(debtsControllerProvider);
    if (result.hasError) return;
    context.pop();
  }
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({required this.debt});
  final Debt debt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final status = debtStatus(debt);
    final isSettled = status == DebtStatus.settled;
    final initial = debt.contactName.isNotEmpty
        ? debt.contactName.trim()[0].toUpperCase()
        : '?';

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        // --- Header card ---------------------------------------------
        Card(
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
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: AppBorderRadius.full,
                      ),
                      child: Text(
                        initial,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
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
                            style: theme.textTheme.titleLarge,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Row(
                            children: [
                              _TypeChip(type: debt.type),
                              const SizedBox(width: AppSpacing.sm),
                              _StatusBadge(status: status),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Original: ${debt.currency} ${_format(debt.originalAmount)}'
                  '   ·   '
                  'Remaining: ${debt.currency} ${_format(debt.remainingAmount)}',
                  style: theme.textTheme.titleSmall,
                ),
                if (debt.dueDate != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Icon(
                        Icons.event_outlined,
                        size: 18,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        'Due ${_formatDate(debt.dueDate!)}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
                if ((debt.notes ?? '').isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    debt.notes!,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        // --- Add payment --------------------------------------------
        if (!isSettled)
          FilledButton.icon(
            onPressed: () => _openAddPaymentSheet(context, ref, debt),
            icon: const Icon(Icons.payments_outlined),
            label: const Text('Add payment'),
          ),
        if (!isSettled) const SizedBox(height: AppSpacing.lg),

        // --- Payment history ----------------------------------------
        Text('Payment history', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        _PaymentHistory(debtId: debt.id, currency: debt.currency),
      ],
    );
  }

  Future<void> _openAddPaymentSheet(
    BuildContext context,
    WidgetRef ref,
    Debt debt,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useRootNavigator: true,
      builder: (_) => _AddPaymentSheet(debt: debt),
    );
  }

  String _format(double n) {
    final abs = n.abs();
    return abs.toStringAsFixed(abs.truncateToDouble() == abs ? 0 : 2);
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.type});
  final String type;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLent = type == 'lent';
    final bg = isLent
        ? theme.colorScheme.secondaryContainer
        : theme.colorScheme.tertiaryContainer;
    final fg = isLent
        ? theme.colorScheme.onSecondaryContainer
        : theme.colorScheme.onTertiaryContainer;
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
        isLent ? 'Lent' : 'Borrowed',
        style: theme.textTheme.labelSmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
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

class _PaymentHistory extends ConsumerWidget {
  const _PaymentHistory({required this.debtId, required this.currency});
  final String debtId;
  final String currency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final stream = ref.watch(debtDaoProvider).watchPaymentsForDebt(debtId);
    return StreamBuilder<List<DebtPayment>>(
      stream: stream,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        final rows = [...snap.data!]
          ..sort((a, b) => b.paidAt.compareTo(a.paidAt));
        if (rows.isEmpty) {
          return Container(
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
                    'No payments yet.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          );
        }
        return Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const Divider(height: 0),
                _PaymentRow(payment: rows[i], currency: currency),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({required this.payment, required this.currency});
  final DebtPayment payment;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final note = payment.note;
    return Padding(
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
              color: theme.colorScheme.secondaryContainer,
              borderRadius: AppBorderRadius.full,
            ),
            child: Icon(
              Icons.south_west,
              color: theme.colorScheme.onSecondaryContainer,
              size: 22,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatDate(payment.paidAt),
                  style: theme.textTheme.titleSmall,
                ),
                if (note != null && note.isNotEmpty)
                  Text(
                    note,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            '$currency ${_format(payment.amount)}',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _format(double n) {
    final abs = n.abs();
    return abs.toStringAsFixed(abs.truncateToDouble() == abs ? 0 : 2);
  }
}

class _AddPaymentSheet extends ConsumerStatefulWidget {
  const _AddPaymentSheet({required this.debt});
  final Debt debt;

  @override
  ConsumerState<_AddPaymentSheet> createState() => _AddPaymentSheetState();
}

class _AddPaymentSheetState extends ConsumerState<_AddPaymentSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  DateTime _paidAt = DateTime.now();

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    // A payment can't predate the debt, and "paid in 2087" is a typo.
    // `createdAt` is stored UTC, so convert before comparing with local
    // now — and clamp, since a just-created debt can otherwise land a few
    // hours "ahead" of local time and trip the picker's range assertion.
    final now = DateTime.now();
    final created = widget.debt.createdAt.toLocal();
    final first = created.isBefore(now) ? created : now;
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(first.year, first.month, first.day),
      lastDate: now,
      initialDate: _paidAt.isBefore(first) ? now : _paidAt,
    );
    if (picked != null && mounted) {
      setState(() => _paidAt = picked);
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final amount = double.parse(_amountCtrl.text.trim());
    await ref.read(debtsControllerProvider.notifier).addPayment(
          debtId: widget.debt.id,
          amount: amount,
          paidAt: _paidAt,
          note: _noteCtrl.text,
        );
    if (!mounted) return;
    final result = ref.read(debtsControllerProvider);
    if (result.hasError) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save payment. Try again.')),
      );
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewInsets = MediaQuery.of(context).viewInsets;
    final commitState = ref.watch(debtsControllerProvider);

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          shrinkWrap: true,
          children: [
            Text('Add payment', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _amountCtrl,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Amount',
                prefixText: '${widget.debt.currency}  ',
              ),
              validator: (v) {
                final base = Validators.amount(v, label: 'Payment');
                if (base != null) return base;
                // Over-payment would drive `remainingAmount` negative;
                // the controller clamps to settled, so the extra silently
                // vanishes. Better to catch it here.
                final d = double.parse(v!.trim());
                if (d > widget.debt.remainingAmount) {
                  return 'More than the remaining '
                      '${widget.debt.currency} '
                      '${widget.debt.remainingAmount.toStringAsFixed(2)}';
                }
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Paid on',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Material(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: AppBorderRadius.md,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: _pickDate,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.event_outlined,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          _formatDate(_paidAt),
                          style: theme.textTheme.bodyMedium,
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
            ),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _noteCtrl,
              maxLines: 2,
              maxLength: Validators.noteMaxLength,
              textCapitalization: TextCapitalization.sentences,
              validator: (v) => Validators.optionalText(v, label: 'Note'),
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton(
              onPressed: commitState.isLoading ? null : _submit,
              child: commitState.isLoading
                  ? SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.onPrimary,
                      ),
                    )
                  : const Text('Save payment'),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDate(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final local = d.toLocal();
  return '${local.day} ${months[local.month - 1]} ${local.year}';
}

/// One-shot Drift lookup keyed by debt id; rebuilds when the DAO stream
/// emits (since [debtDaoProvider.watchAll] is the underlying source).
final _debtByIdProvider =
    StreamProvider.family<Debt?, String>((ref, id) async* {
  final dao = ref.watch(debtDaoProvider);
  await for (final rows in dao.watchAll()) {
    yield rows.where((d) => d.id == id).firstOrNull;
  }
});
