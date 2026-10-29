import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/shapes.dart';
import '../../../core/theme/spacing.dart';
import '../../../data/local/app_database.dart';
import '../data/wallet_catalog.dart';
import '../providers/wallets_controller.dart';
import '../providers/wallets_list_provider.dart';

/// `/wallet/manage` — sectioned list of every wallet the user owns, split
/// into Active and Archived. This is the only surface that lists archived
/// wallets: the Home carousel and every picker read
/// `visibleWalletsProvider`, so without this screen an archived wallet is
/// unreachable and can never be restored.
class WalletsManageScreen extends ConsumerWidget {
  const WalletsManageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final active = ref.watch(visibleWalletsProvider);
    final archived = ref.watch(archivedWalletsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Manage wallets')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/wallet/add'),
        icon: const Icon(Icons.add),
        label: const Text('Add wallet'),
      ),
      body: SafeArea(
        child: active.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Text(
              'Could not load wallets.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
          data: (activeList) {
            final archivedList = archived.value ?? const <Wallet>[];
            if (activeList.isEmpty && archivedList.isEmpty) {
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
                if (activeList.isNotEmpty) ...[
                  const _SectionHeader(label: 'Active'),
                  const SizedBox(height: AppSpacing.sm),
                  for (final w in activeList) _WalletTile(wallet: w),
                ],
                if (archivedList.isNotEmpty) ...[
                  if (activeList.isNotEmpty)
                    const SizedBox(height: AppSpacing.lg),
                  const _SectionHeader(label: 'Archived'),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Archived wallets stay out of the carousel and pickers. '
                    'Restore one to use it again.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  for (final w in archivedList) _WalletTile(wallet: w),
                ],
              ],
            );
          },
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
              Icons.account_balance_wallet_outlined,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.md),
            Text('No wallets yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Tap "Add wallet" to create one.',
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

class _WalletTile extends ConsumerWidget {
  const _WalletTile({required this.wallet});
  final Wallet wallet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final color = Color(int.parse('FF${wallet.color}', radix: 16));
    final icon = kWalletIconCatalog[wallet.iconName] ??
        Icons.account_balance_wallet_outlined;
    final archived = wallet.isArchived;

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: InkWell(
        borderRadius: AppBorderRadius.lg,
        onTap: () => context.push('/wallet/${wallet.id}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              Opacity(
                opacity: archived ? 0.5 : 1,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: AppBorderRadius.full,
                  ),
                  child: Icon(icon, color: Colors.white, size: 22),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      wallet.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: archived
                            ? theme.colorScheme.onSurfaceVariant
                            : null,
                      ),
                    ),
                    Text(
                      wallet.isHidden
                          ? '${wallet.currency} • ••••'
                          : '${wallet.currency} '
                              '${wallet.balance.toStringAsFixed(2)}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: archived ? 'Restore' : 'Archive',
                icon: Icon(
                  archived ? Icons.unarchive_outlined : Icons.archive_outlined,
                  color: archived
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                onPressed: () => archived
                    ? restoreWallet(context, ref, wallet)
                    : confirmArchiveWallet(context, ref, wallet),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Archives [wallet] after a confirmation dialog. Shared with the wallet
/// detail screen so both entry points explain the same consequences and
/// offer the same undo. Returns true when the wallet was archived.
Future<bool> confirmArchiveWallet(
  BuildContext context,
  WidgetRef ref,
  Wallet wallet,
) async {
  // Captured before the dialog await so the snackbar doesn't need a
  // post-gap BuildContext.
  final messenger = ScaffoldMessenger.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Archive "${wallet.name}"?'),
      content: const Text(
        'It disappears from the home carousel and from wallet pickers. '
        'Its transactions are kept, and you can restore it any time from '
        'Settings → Manage wallets.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Archive'),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;

  final ctrl = ref.read(walletsControllerProvider.notifier);
  await ctrl.archive(wallet.id, archive: true);
  final failed = ref.read(walletsControllerProvider).hasError;
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        failed
            ? 'Could not archive "${wallet.name}".'
            : '"${wallet.name}" archived.',
      ),
      action: failed
          ? null
          : SnackBarAction(
              label: 'Undo',
              onPressed: () => ctrl.archive(wallet.id, archive: false),
            ),
    ),
  );
  return !failed;
}

/// Restores an archived [wallet] back into the active set.
Future<void> restoreWallet(
  BuildContext context,
  WidgetRef ref,
  Wallet wallet,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final ctrl = ref.read(walletsControllerProvider.notifier);
  await ctrl.archive(wallet.id, archive: false);
  final failed = ref.read(walletsControllerProvider).hasError;
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        failed
            ? 'Could not restore "${wallet.name}".'
            : '"${wallet.name}" restored.',
      ),
    ),
  );
}
