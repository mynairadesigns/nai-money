import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/shapes.dart';
import '../../../core/theme/spacing.dart';
import '../providers/wallets_list_provider.dart';
import 'wallet_card.dart';

/// Home dashboard's wallet strip. Horizontal scroller of [WalletCard]s
/// (carousel variant) with a trailing "+ Add wallet" tile.
/// PRD §6.2: "List view with balance summary across all wallets".
class WalletCarousel extends ConsumerWidget {
  const WalletCarousel({super.key});

  static const _cardHeight = 130.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final wallets = ref.watch(visibleWalletsProvider);

    return wallets.when(
      loading: () => const SizedBox(
        height: _cardHeight,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (e, _) => SizedBox(
        height: _cardHeight,
        child: Center(
          child: Text(
            'Could not load wallets',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ),
      ),
      data: (rows) {
        if (rows.isEmpty) return const _EmptyCta();
        return SizedBox(
          height: _cardHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: rows.length + 1,
            // Start-edge padding lines up the first card with surrounding
            // content; end-edge padding gives the last card breathing
            // room when fully scrolled into view.
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
            itemBuilder: (context, i) {
              if (i == rows.length) return const _AddTile();
              return WalletCard(
                wallet: rows[i],
                onTap: () => context.push('/wallet/${rows[i].id}'),
              );
            },
          ),
        );
      },
    );
  }
}

class _EmptyCta extends StatelessWidget {
  const _EmptyCta();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Card(
        child: InkWell(
          borderRadius: AppBorderRadius.lg,
          onTap: () => GoRouter.of(context).push('/wallet/add'),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: [
                Icon(
                  Icons.account_balance_wallet_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    'Add your first wallet to get started',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 130,
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: AppBorderRadius.lg,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => GoRouter.of(context).push('/wallet/add'),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.add_circle_outline,
                color: theme.colorScheme.primary,
                size: 28,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Add wallet',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
