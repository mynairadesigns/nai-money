import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../../core/theme/shapes.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/widgets/brand_logo.dart';
import '../../../data/remote/billing_service.dart';

/// Paywall (PRD §6.14). Shows the three RevenueCat packages — monthly,
/// yearly, lifetime — with the user able to tap to select one, then a
/// full-width subscribe button that drives `Purchases.purchasePackage`.
///
/// Loading / unconfigured states are handled gracefully — buyers who
/// haven't wired RevenueCat yet see a "not configured" card rather than
/// a crash.
class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key});

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  Offering? _offering;
  Package? _selected;
  bool _loading = true;
  bool _failed = false;
  bool _purchasing = false;
  bool _restoring = false;

  @override
  void initState() {
    super.initState();
    _loadOfferings();
  }

  Future<void> _loadOfferings() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    final billing = ref.read(billingServiceProvider);
    final offerings = await billing.getOfferings();
    if (!mounted) return;
    if (offerings == null || offerings.current == null) {
      setState(() {
        _loading = false;
        _failed = true;
      });
      return;
    }
    final current = offerings.current!;
    // Default selection: yearly if present, else monthly, else first.
    Package? defaultPick = current.annual ?? current.monthly;
    defaultPick ??= current.availablePackages.isNotEmpty
        ? current.availablePackages.first
        : null;
    setState(() {
      _offering = current;
      _selected = defaultPick;
      _loading = false;
    });
  }

  Future<void> _purchase() async {
    final selected = _selected;
    if (selected == null || _purchasing) return;
    setState(() => _purchasing = true);
    final billing = ref.read(billingServiceProvider);
    try {
      await billing.purchasePackage(selected);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Welcome to Premium!')),
      );
      context.pop(true);
    } on PlatformException catch (e) {
      // RevenueCat uses error codes — userCancelled silently dismisses.
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (code == PurchasesErrorCode.purchaseCancelledError) {
        // user backed out — no toast
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Purchase failed: ${e.message ?? code.name}')),
        );
      }
    } catch (e) {
      debugPrint('Paywall purchase error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Purchase failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _purchasing = false);
    }
  }

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
      if (isPrem) context.pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Restore failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
        title: const Text('Go Premium'),
      ),
      body: SafeArea(child: _buildBody(theme)),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: AppSpacing.md),
            Text('Loading offerings…'),
          ],
        ),
      );
    }
    if (_failed || _offering == null) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Center(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.info_outline,
                    color: theme.colorScheme.primary,
                    size: 40,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    "Subscriptions aren't configured yet.",
                    style: theme.textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Check the Moneymind setup guide to wire up your RevenueCat API keys.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final packages = _offering!.availablePackages;
    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      children: [
        // Hero.
        const Center(child: BrandLogo(size: 96)),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Go Premium',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Unlock everything Moneymind can do.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),

        // Feature comparison.
        const PaywallFeatureTable(),
        const SizedBox(height: AppSpacing.xl),

        // Pricing cards.
        for (final pkg in packages) ...[
          _PriceCard(
            package: pkg,
            selected: _selected?.identifier == pkg.identifier,
            badge: _badgeFor(pkg),
            highlight: _isHighlight(pkg),
            onTap: () => setState(() => _selected = pkg),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        const SizedBox(height: AppSpacing.md),

        // Subscribe CTA.
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton(
            onPressed: (_purchasing || _selected == null) ? null : _purchase,
            child: _purchasing
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_ctaLabel(_selected)),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),

        // Restore.
        Center(
          child: TextButton(
            onPressed: _restoring ? null : _restore,
            child: _restoring
                ? const Text('Restoring…')
                : const Text('Restore purchases'),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),

        // Fine print.
        Text(
          'Cancel anytime in your App Store / Google Play account settings.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }

  String _ctaLabel(Package? pkg) {
    if (pkg == null) return 'Subscribe';
    switch (pkg.packageType) {
      case PackageType.lifetime:
        return 'Buy lifetime';
      default:
        return 'Subscribe';
    }
  }

  String? _badgeFor(Package pkg) {
    switch (pkg.packageType) {
      case PackageType.annual:
        return 'Save 50%';
      case PackageType.lifetime:
        return 'Best deal';
      default:
        return null;
    }
  }

  bool _isHighlight(Package pkg) =>
      pkg.packageType == PackageType.annual ||
      pkg.packageType == PackageType.lifetime;
}

/// Free-vs-Premium comparison card. Shared with the web (Paystack) paywall.
class PaywallFeatureTable extends StatelessWidget {
  const PaywallFeatureTable({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const features = <(String, bool)>[
      ('Unlimited wallets', true),
      ('Unlimited transactions', true),
      ('Unlimited AI actions', true),
      ('All categories', true),
      ('No ads', true),
      ('Cloud backup', true),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      'Feature',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'Free',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'Premium',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            for (final f in features)
              _FeatureRow(label: f.$1, premiumOnly: f.$2),
          ],
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.label, required this.premiumOnly});
  final String label;
  final bool premiumOnly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(label, style: theme.textTheme.bodyMedium),
          ),
          Expanded(
            child: Icon(
              premiumOnly ? Icons.close : Icons.check_circle,
              size: 18,
              color: premiumOnly
                  ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6)
                  : theme.colorScheme.secondary,
            ),
          ),
          Expanded(
            child: Icon(
              Icons.check_circle,
              size: 18,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _PriceCard extends StatelessWidget {
  const _PriceCard({
    required this.package,
    required this.selected,
    required this.onTap,
    required this.highlight,
    this.badge,
  });

  final Package package;
  final bool selected;
  final bool highlight;
  final String? badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = _title(package);
    final price = package.storeProduct.priceString;
    final period = _periodLabel(package);

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
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: AppSpacing.sm),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: highlight
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.secondary,
                              borderRadius: AppBorderRadius.full,
                            ),
                            child: Text(
                              badge!,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: highlight
                                    ? theme.colorScheme.onPrimary
                                    : theme.colorScheme.onSecondary,
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
                price,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _title(Package pkg) {
    switch (pkg.packageType) {
      case PackageType.monthly:
        return 'Monthly';
      case PackageType.annual:
        return 'Yearly';
      case PackageType.lifetime:
        return 'Lifetime';
      case PackageType.weekly:
        return 'Weekly';
      default:
        return pkg.storeProduct.title;
    }
  }

  String _periodLabel(Package pkg) {
    switch (pkg.packageType) {
      case PackageType.monthly:
        return 'Billed monthly';
      case PackageType.annual:
        return 'Billed once a year';
      case PackageType.lifetime:
        return 'One-time purchase';
      case PackageType.weekly:
        return 'Billed weekly';
      default:
        return pkg.storeProduct.description;
    }
  }
}
