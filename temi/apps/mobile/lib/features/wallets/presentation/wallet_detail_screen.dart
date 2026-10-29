import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/database_provider.dart';
import '../../../core/theme/shapes.dart';
import '../../../core/theme/spacing.dart';
import '../../../data/local/app_database.dart';
import '../../transactions/providers/transactions_list_provider.dart';
import '../../transactions/widgets/transaction_row.dart';
import '../providers/wallets_controller.dart';
import '../widgets/wallet_card.dart';
import 'wallets_manage_screen.dart';

/// Per-wallet view (PRD §6.2): info card header + transaction history
/// filtered to this wallet. Real transaction list lands in P2.3 — for
/// now the empty-state CTA + a placeholder banner sit below.
class WalletDetailScreen extends ConsumerWidget {
  const WalletDetailScreen({required this.id, super.key});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final walletFut = ref.watch(
      _walletByIdProvider(id),
    );

    final wallet = walletFut.value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Wallet'),
        actions: [
          if (wallet != null)
            PopupMenuButton<String>(
              onSelected: (action) => _onAction(context, ref, action, wallet),
              // Archive and Restore are mutually exclusive — showing both
              // at once let users "unarchive" an active wallet (a no-op)
              // and made the current state unreadable.
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'hide',
                  child: Text('Toggle hide balance'),
                ),
                if (wallet.isArchived)
                  const PopupMenuItem(
                    value: 'unarchive',
                    child: Text('Restore'),
                  )
                else
                  const PopupMenuItem(
                    value: 'archive',
                    child: Text('Archive'),
                  ),
              ],
            ),
        ],
      ),
      body: walletFut.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text(
            'Could not load this wallet.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ),
        data: (wallet) {
          if (wallet == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Text(
                  'This wallet no longer exists.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            );
          }
          return _DetailBody(wallet: wallet);
        },
      ),
    );
  }

  Future<void> _onAction(
    BuildContext context,
    WidgetRef ref,
    String action,
    Wallet? wallet,
  ) async {
    if (wallet == null) return;
    final ctrl = ref.read(walletsControllerProvider.notifier);
    switch (action) {
      case 'hide':
        await ctrl.setHidden(wallet.id, !wallet.isHidden);
        break;
      case 'archive':
        final archived = await confirmArchiveWallet(context, ref, wallet);
        // Only leave the screen if the wallet actually got archived —
        // a cancelled dialog or a failed write should keep the user here.
        if (archived && context.mounted) context.pop();
        break;
      case 'unarchive':
        await restoreWallet(context, ref, wallet);
        break;
    }
  }
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({required this.wallet});
  final Wallet wallet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final txAsync = ref.watch(walletTransactionsProvider(wallet.id));

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        WalletCard(
          wallet: wallet,
          variant: WalletCardVariant.compact,
        ),
        if (wallet.isArchived) ...[
          const SizedBox(height: AppSpacing.md),
          _ArchivedBanner(wallet: wallet),
        ],
        const SizedBox(height: AppSpacing.lg),
        Text('Transactions', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        txAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Text(
              'Could not load transactions.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
          data: (rows) {
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
                        'No transactions in this wallet yet.',
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
              child: Column(
                children: [
                  for (var i = 0; i < rows.length; i++) ...[
                    if (i > 0) const Divider(height: 0),
                    TransactionRow(
                      transaction: rows[i],
                      onTap: () =>
                          GoRouter.of(context).push('/transaction/${rows[i].id}'),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

/// Inline notice + one-tap restore for an archived wallet, so a user who
/// lands here (from Manage wallets or a filtered transaction) can undo the
/// archive without hunting through the overflow menu.
class _ArchivedBanner extends ConsumerWidget {
  const _ArchivedBanner({required this.wallet});
  final Wallet wallet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: AppBorderRadius.lg,
      ),
      child: Row(
        children: [
          Icon(
            Icons.archive_outlined,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'This wallet is archived. It stays out of the home carousel '
              'and wallet pickers until you restore it.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          FilledButton.tonal(
            onPressed: () => restoreWallet(context, ref, wallet),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
  }
}

/// One-shot Drift lookup keyed by wallet id; rebuilds when the DAO stream
/// emits (since [walletDaoProvider.watchAll] is the underlying source).
final _walletByIdProvider =
    StreamProvider.family<Wallet?, String>((ref, id) async* {
  final dao = ref.watch(walletDaoProvider);
  await for (final rows in dao.watchAll()) {
    yield rows.where((w) => w.id == id).firstOrNull;
  }
});
