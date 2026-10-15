import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/shapes.dart';
import '../../../core/theme/spacing.dart';
import '../../../data/local/app_database.dart';
import '../../categories/providers/categories_list_provider.dart';
import '../../wallets/providers/wallets_list_provider.dart';
import '../data/subscription_candidate.dart';
import '../data/subscriptions_service.dart';
import '../providers/subscriptions_provider.dart';

/// Detected subscriptions screen (PRD §6.4.3). Calls `detectSubscriptions`
/// on mount; per-row "Confirm" opens a wallet+category picker and POSTs
/// to `confirmSubscription`. The server creates the recurringRules doc;
/// the next pull-direction sync brings it into Drift.
class SubscriptionsScreen extends ConsumerWidget {
  const SubscriptionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(subscriptionCandidatesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Detected subscriptions')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Text(
              "Couldn't run the detector right now.",
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        data: (list) {
          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Text(
                  "Nothing detected — keep using Moneymind for a few weeks "
                  "and we'll spot recurring patterns.",
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: list.length,
            separatorBuilder: (_, _) =>
                const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, i) => _CandidateRow(candidate: list[i]),
          );
        },
      ),
    );
  }
}

class _CandidateRow extends ConsumerWidget {
  const _CandidateRow({required this.candidate});
  final SubscriptionCandidate candidate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          candidate.merchant,
                          style: theme.textTheme.titleSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      _FrequencyBadge(frequency: candidate.frequency),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '${candidate.currency} '
                    '${candidate.amount.toStringAsFixed(2)} · '
                    '${candidate.occurrences}× seen',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            OutlinedButton(
              onPressed: () => _confirm(context, ref),
              child: const Text('Confirm'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirm(BuildContext context, WidgetRef ref) async {
    final picked = await showDialog<_ConfirmResult>(
      context: context,
      builder: (_) => _ConfirmSubscriptionDialog(candidate: candidate),
    );
    if (picked == null || !context.mounted) return;

    final service = ref.read(subscriptionsServiceProvider);
    try {
      await service.confirm(
        candidateId: candidate.candidateId,
        merchant: candidate.merchant,
        amount: candidate.amount,
        currency: candidate.currency,
        frequency: candidate.frequency,
        walletId: picked.walletId,
        categoryId: picked.categoryId,
        startDate: DateTime.now().toUtc(),
      );
      if (!context.mounted) return;
      // Refresh the list — the confirmed candidate should drop out.
      ref.invalidate(subscriptionCandidatesProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Added as recurring rule')),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not confirm. Try again.')),
      );
    }
  }
}

class _FrequencyBadge extends StatelessWidget {
  const _FrequencyBadge({required this.frequency});
  final String frequency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: AppBorderRadius.full,
      ),
      child: Text(
        frequency,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

class _ConfirmResult {
  const _ConfirmResult({required this.walletId, required this.categoryId});
  final String walletId;
  final String categoryId;
}

class _ConfirmSubscriptionDialog extends ConsumerStatefulWidget {
  const _ConfirmSubscriptionDialog({required this.candidate});
  final SubscriptionCandidate candidate;

  @override
  ConsumerState<_ConfirmSubscriptionDialog> createState() =>
      _ConfirmSubscriptionDialogState();
}

class _ConfirmSubscriptionDialogState
    extends ConsumerState<_ConfirmSubscriptionDialog> {
  String? _walletId;
  String? _categoryId;

  @override
  Widget build(BuildContext context) {
    final wallets = ref.watch(walletsListProvider).value ?? const <Wallet>[];
    final categories =
        (ref.watch(categoriesListProvider).value ?? const <Category>[])
            .where((c) => c.type == 'expense')
            .toList();

    return AlertDialog(
      title: Text(widget.candidate.merchant),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _walletId,
            decoration: const InputDecoration(labelText: 'Wallet'),
            items: [
              for (final w in wallets)
                DropdownMenuItem(value: w.id, child: Text(w.name)),
            ],
            onChanged: (v) => setState(() => _walletId = v),
          ),
          const SizedBox(height: AppSpacing.md),
          DropdownButtonFormField<String>(
            initialValue: _categoryId,
            decoration: const InputDecoration(labelText: 'Category'),
            items: [
              for (final c in categories)
                DropdownMenuItem(value: c.id, child: Text(c.name)),
            ],
            onChanged: (v) => setState(() => _categoryId = v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: (_walletId == null || _categoryId == null)
              ? null
              : () => Navigator.of(context).pop(
                    _ConfirmResult(
                      walletId: _walletId!,
                      categoryId: _categoryId!,
                    ),
                  ),
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}
