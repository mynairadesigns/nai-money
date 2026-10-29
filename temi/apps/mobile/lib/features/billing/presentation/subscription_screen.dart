import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/shapes.dart';
import '../../../core/theme/spacing.dart';
import '../../../data/remote/billing_service.dart';
import '../../../data/remote/paystack_billing_service.dart';
import '../providers/premium_providers.dart';

/// Settings → Subscription. Two faces:
///   - Premium users see their tier, renewal date (or "Lifetime
///     access"), and a "Manage subscription" entry that opens the
///     platform's native subscription management UI.
///   - Free users see a paywall CTA.
/// Both always get a "Restore purchases" tile so they can recover
/// purchases on a new device / reinstall.
class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  ConsumerState<SubscriptionScreen> createState() =>
      _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  bool _restoring = false;

  Future<void> _restore() async {
    if (_restoring) return;
    setState(() => _restoring = true);
    final billing = ref.read(billingServiceProvider);
    try {
      final info = await billing.restorePurchases();
      if (!mounted) return;
      final isPrem = billing.isPremium(info);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isPrem ? 'Purchases restored.' : 'No purchases to restore.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Restore failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  /// Web: subscriptions bought here are Paystack subscriptions, managed on
  /// a Paystack-hosted page (cancel / change card).
  Future<void> _manageWeb() async {
    final uid = ref.read(authStateProvider).value?.uid;
    final source = uid == null
        ? null
        : ref.read(userDocProvider(uid)).value?['premiumSource'] as String?;
    if (source == 'revenuecat') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This plan was bought in the mobile app — manage it in the '
            'App Store / Google Play on your phone.',
          ),
        ),
      );
      return;
    }
    try {
      final link = await ref.read(paystackBillingServiceProvider).manageLink();
      if (!mounted) return;
      if (link == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No renewing subscription to manage.'),
          ),
        );
        return;
      }
      // Same tab: a new-tab open after an `await` is popup-blocked in Safari.
      await launchUrl(link, webOnlyWindowName: '_self');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't open subscription manager: $e")),
      );
    }
  }

  Future<void> _manage() async {
    if (kIsWeb) return _manageWeb();
    try {
      final info = await Purchases.getCustomerInfo();
      final url = info.managementURL;
      if (url == null || url.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No active subscription to manage.'),
          ),
        );
        return;
      }
      final uri = Uri.parse(url);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Couldn't open: $url")),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't open subscription manager: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPremium = ref.watch(isPremiumProvider);
    final expiry = ref.watch(premiumExpiryProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: const Text('Subscription'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          if (isPremium)
            _PremiumCard(expiry: expiry, theme: theme)
          else
            _FreeCard(theme: theme),
          const SizedBox(height: AppSpacing.lg),
          if (isPremium)
            Card(
              child: ListTile(
                leading: const Icon(Icons.tune),
                title: const Text('Manage subscription'),
                subtitle: const Text(
                  kIsWeb
                      ? 'Cancel or change card on Paystack'
                      : 'Cancel or change plan in the App Store / Google Play',
                ),
                trailing: const Icon(Icons.open_in_new, size: 18),
                onTap: _manage,
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          // App-store restore has no meaning on web — Paystack purchases are
          // tied to the account and sync automatically.
          if (!kIsWeb)
          Card(
            child: ListTile(
              leading: const Icon(Icons.restore),
              title: const Text('Restore purchases'),
              trailing: _restoring
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
              onTap: _restoring ? null : _restore,
            ),
          ),
        ],
      ),
    );
  }
}

class _PremiumCard extends StatelessWidget {
  const _PremiumCard({required this.expiry, required this.theme});
  final DateTime? expiry;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    // Heuristic: an expiry more than 50 years out is effectively
    // "lifetime" (lifetimes can come through as null too).
    final isLifetime = expiry == null ||
        expiry!.isAfter(DateTime.now().add(const Duration(days: 365 * 50)));
    final subtitle = isLifetime
        ? 'Lifetime access.'
        : 'Renews on ${_formatDate(expiry!)}.';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: AppBorderRadius.full,
              ),
              child: Icon(
                Icons.auto_awesome,
                color: theme.colorScheme.primary,
                size: 28,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Premium',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }
}

class _FreeCard extends StatelessWidget {
  const _FreeCard({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: AppBorderRadius.full,
                  ),
                  child: Icon(
                    Icons.workspace_premium_outlined,
                    color: theme.colorScheme.onSurfaceVariant,
                    size: 28,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Free plan',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Limited features.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              height: 48,
              child: FilledButton.icon(
                onPressed: () => context.push('/paywall'),
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Upgrade to Premium'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
