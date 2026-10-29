import 'package:flutter/material.dart';

import '../../../core/theme/shapes.dart';
import '../../../core/theme/spacing.dart';
import '../../../data/local/app_database.dart';
import '../data/wallet_catalog.dart';

/// Reusable card showing a wallet's icon, name, type, and balance.
/// Used by the Home carousel and the wallet detail header.
///
/// Sizes:
/// - [WalletCardVariant.carousel] — fixed-width chunky card for horizontal
///   scrollers (Home)
/// - [WalletCardVariant.compact] — full-width row card for lists (Settings,
///   wallet picker on Add Transaction)
class WalletCard extends StatelessWidget {
  const WalletCard({
    required this.wallet,
    this.variant = WalletCardVariant.carousel,
    this.onTap,
    super.key,
  });

  final Wallet wallet;
  final WalletCardVariant variant;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = Color(int.parse('FF${wallet.color}', radix: 16));
    final onBg = _readableOn(bg);
    final icon = kWalletIconCatalog[wallet.iconName] ??
        Icons.account_balance_wallet_outlined;

    final card = Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppBorderRadius.lg,
      ),
      padding: EdgeInsets.all(
        variant == WalletCardVariant.carousel
            ? AppSpacing.md
            : AppSpacing.lg,
      ),
      child: switch (variant) {
        WalletCardVariant.carousel => _carouselBody(theme, icon, onBg),
        WalletCardVariant.compact => _compactBody(theme, icon, onBg),
      },
    );

    return SizedBox(
      width: variant == WalletCardVariant.carousel ? 200 : double.infinity,
      child: Material(
        color: Colors.transparent,
        borderRadius: AppBorderRadius.lg,
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: card),
      ),
    );
  }

  Widget _carouselBody(ThemeData theme, IconData icon, Color onBg) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: onBg.withValues(alpha: 0.15),
                borderRadius: AppBorderRadius.full,
              ),
              child: Icon(icon, color: onBg, size: 18),
            ),
            const Spacer(),
            if (wallet.isArchived)
              Icon(Icons.archive_outlined, size: 16, color: onBg),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              wallet.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(color: onBg),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              _formatBalance(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                color: onBg,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _compactBody(ThemeData theme, IconData icon, Color onBg) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: onBg.withValues(alpha: 0.15),
            borderRadius: AppBorderRadius.full,
          ),
          child: Icon(icon, color: onBg, size: 22),
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
                style: theme.textTheme.titleSmall?.copyWith(color: onBg),
              ),
              Text(
                wallet.currency,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: onBg.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
        Text(
          _formatBalance(),
          style: theme.textTheme.titleMedium?.copyWith(
            color: onBg,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  String _formatBalance() {
    if (wallet.isHidden) return '••••';
    final n = wallet.balance;
    final negative = n < 0;
    final abs = n.abs();
    final fixed = abs.toStringAsFixed(abs.truncateToDouble() == abs ? 0 : 2);
    return '${negative ? '-' : ''}${wallet.currency} $fixed';
  }

  /// Picks black or white text based on the perceived luminance of [bg],
  /// so the card stays readable across the warm palette.
  Color _readableOn(Color bg) {
    final lum = bg.computeLuminance();
    return lum > 0.55 ? Colors.black87 : Colors.white;
  }
}

enum WalletCardVariant { carousel, compact }
