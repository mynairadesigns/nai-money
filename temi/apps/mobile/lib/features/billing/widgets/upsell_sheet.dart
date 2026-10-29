import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/shapes.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/widgets/brand_logo.dart';

/// Reasons a user might hit a free-tier boundary. Drives the headline +
/// body copy of the upsell sheet.
enum UpsellReason { wallets, transactions, ai, categories }

Future<void> showUpsellSheet(BuildContext context, UpsellReason reason) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    builder: (_) => _UpsellSheet(reason: reason),
  );
}

class _UpsellSheet extends StatelessWidget {
  const _UpsellSheet({required this.reason});
  final UpsellReason reason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (title, body) = _copy(reason);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BrandLogo(size: 64),
            const SizedBox(height: AppSpacing.md),
            Text(title, style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            Text(
              body,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  // Grab the router before the sheet's context is torn down.
                  final router = GoRouter.of(context);
                  Navigator.of(context).pop();
                  router.push('/paywall');
                },
                style: FilledButton.styleFrom(
                  shape: const RoundedRectangleBorder(
                    borderRadius: AppBorderRadius.lg,
                  ),
                  padding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.md,
                  ),
                ),
                child: const Text('Upgrade to Premium'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Not now'),
            ),
          ],
        ),
      ),
    );
  }

  (String, String) _copy(UpsellReason r) {
    switch (r) {
      case UpsellReason.wallets:
        return (
          'Add unlimited wallets',
          'The free plan includes 1 wallet. Upgrade to track every account, card, and savings pot side by side.',
        );
      case UpsellReason.transactions:
        return (
          'Unlimited transactions',
          "You've hit the free plan's monthly limit. Upgrade for unlimited tracking, plus the rest of Premium.",
        );
      case UpsellReason.ai:
        return (
          "You've used this month's free AI",
          'The free plan includes 10 uses of each AI feature per month. Upgrade to Premium for unlimited Coach Tems chats, receipt scans and insights.',
        );
      case UpsellReason.categories:
        return (
          'All categories',
          'Upgrade to unlock the full category library, including custom categories of your own.',
        );
    }
  }
}
