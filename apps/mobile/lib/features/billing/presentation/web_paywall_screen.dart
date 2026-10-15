import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/providers/onboarding_state_provider.dart';
import '../../../core/theme/shapes.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/widgets/brand_logo.dart';
import '../../../data/remote/paystack_billing_service.dart';
import '../providers/paystack_providers.dart';
import '../providers/premium_providers.dart';
import 'paywall_screen.dart' show PaywallFeatureTable;

/// Web paywall — Paystack instead of RevenueCat (no app-store billing in a
/// browser). Same layout as [PaywallScreen]. The router picks this screen
/// for `/paywall` when running on web.
class WebPaywallScreen extends ConsumerStatefulWidget {
  const WebPaywallScreen({super.key});

  @override
  ConsumerState<WebPaywallScreen> createState() => _WebPaywallScreenState();
}

class _WebPaywallScreenState extends ConsumerState<WebPaywallScreen> {
  PaystackPlan? _selected;
  bool _redirecting = false;

  /// Where Paystack sends the user after paying. Paystack appends
  /// `&trxref=…&reference=…`; `main.dart` picks `reference` up on reload.
  Uri get _callbackUrl {
    final base = Uri.base;
    return Uri.parse('${base.origin}${base.path}?paystack=return');
  }

  Future<void> _checkout(PaystackPlan plan) async {
    if (_redirecting) return;
    setState(() => _redirecting = true);
    try {
      final res = await ref
          .read(paystackBillingServiceProvider)
          .startCheckout(plan: plan, callbackUrl: _callbackUrl);
      await ref
          .read(sharedPreferencesProvider)
          .setString(kPaystackPendingRefKey, res.reference);
      // Same tab: a new-tab open after an `await` is popup-blocked.
      final opened = await launchUrl(
        res.authorizationUrl,
        webOnlyWindowName: '_self',
      );
      if (!opened) throw Exception("Couldn't open Paystack checkout");
      // Keep the spinner up — the page is navigating away.
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() => _redirecting = false);
      final msg = switch (e.code) {
        'already-exists' => 'You already have Premium.',
        'failed-precondition' => e.message ?? 'Payments are not set up yet.',
        _ => 'Could not start checkout: ${e.message ?? e.code}',
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _redirecting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start checkout: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPremium = ref.watch(isPremiumProvider);
    final prices = ref.watch(paystackPricesProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
        ),
        title: const Text('Go Premium'),
      ),
      body: SafeArea(
        child: prices.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _NotConfigured(
            theme: theme,
            onRetry: () => ref.invalidate(paystackPricesProvider),
          ),
          data: (p) {
            if (p.isEmpty) return _NotConfigured(theme: theme);
            final plans = [
              for (final plan in PaystackPlan.values)
                if (p[plan] != null) plan,
            ];
            final selected = _selected ??
                (plans.contains(PaystackPlan.yearly)
                    ? PaystackPlan.yearly
                    : plans.first);
            return ListView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              children: [
                const Center(child: BrandLogo(size: 96)),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  isPremium ? "You're Premium" : 'Go Premium',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Unlock everything Homa Finance can do.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: AppSpacing.xl),
                const PaywallFeatureTable(),
                const SizedBox(height: AppSpacing.xl),
                for (final plan in plans) ...[
                  _PlanCard(
                    plan: plan,
                    price: p[plan]!,
                    badge: _badgeFor(plan, p),
                    selected: selected == plan,
                    onTap: () => setState(() => _selected = plan),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed: _redirecting ||
                            (isPremium && selected != PaystackPlan.lifetime)
                        ? null
                        : () => _checkout(selected),
                    child: _redirecting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            selected == PaystackPlan.lifetime
                                ? 'Pay once with Paystack'
                                : 'Subscribe with Paystack',
                          ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Secure payment by Paystack — card, bank transfer or USSD. '
                  'Subscriptions renew automatically; cancel anytime from '
                  'Settings → Subscription.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
            );
          },
        ),
      ),
    );
  }

  String? _badgeFor(PaystackPlan plan, PaystackPrices p) {
    if (plan == PaystackPlan.lifetime) return 'Best deal';
    if (plan == PaystackPlan.yearly && p.monthly != null && p.yearly != null) {
      final full = p.monthly!.amount * 12;
      if (full > 0 && p.yearly!.amount < full) {
        final pct = ((1 - p.yearly!.amount / full) * 100).round();
        if (pct >= 5) return 'Save $pct%';
      }
    }
    return null;
  }
}

class _NotConfigured extends StatelessWidget {
  const _NotConfigured({required this.theme, this.onRetry});
  final ThemeData theme;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.info_outline,
                    color: theme.colorScheme.primary, size: 40),
                const SizedBox(height: AppSpacing.md),
                Text(
                  "Payments aren't available right now.",
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'If you run this app, set up Paystack as described in WEB_SETUP.md.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
                if (onRetry != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  TextButton(onPressed: onRetry, child: const Text('Try again')),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.price,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final PaystackPlan plan;
  final PaystackPrice price;
  final bool selected;
  final String? badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (title, period) = switch (plan) {
      PaystackPlan.monthly => ('Monthly', 'Billed monthly'),
      PaystackPlan.yearly => ('Yearly', 'Billed once a year'),
      PaystackPlan.lifetime => ('Lifetime', 'One-time payment'),
    };
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppBorderRadius.lg,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: AppBorderRadius.lg,
            color: selected
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
                : theme.colorScheme.surfaceContainerLow,
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: AppSpacing.sm),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              borderRadius: AppBorderRadius.full,
                            ),
                            child: Text(
                              badge!,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      period,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                price.label,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
