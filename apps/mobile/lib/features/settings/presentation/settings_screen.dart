import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/spacing.dart';
import '../../billing/providers/premium_providers.dart';

/// PRD §11.7: settings root — profile, preferences, security, subscription,
/// backup, about, sign-out. Each row routes to its dedicated screen.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You can sign back in anytime.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(authServiceProvider).signOut();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isPremium = ref.watch(isPremiumProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const SizedBox(height: AppSpacing.sm),
          _SettingsTile(
            icon: Icons.person_outline,
            title: 'Profile',
            onTap: () => context.push('/settings/profile'),
          ),
          _SettingsTile(
            icon: Icons.lock_outline,
            title: 'Security',
            subtitle: 'PIN, biometric, auto-lock',
            onTap: () => context.push('/settings/security'),
          ),
          _SettingsTile(
            icon: Icons.notifications_outlined,
            title: 'Notifications',
            subtitle: 'Budgets, bills, debts, goals',
            onTap: () => context.push('/settings/notifications'),
          ),
          _SettingsTile(
            icon: Icons.workspace_premium_outlined,
            title: 'Subscription',
            premiumBadge: isPremium,
            onTap: () => context.push('/settings/subscription'),
          ),
          _SettingsTile(
            icon: Icons.cloud_outlined,
            title: 'Backup & restore',
            onTap: () => context.push('/settings/backup'),
          ),
          const Divider(),
          _SettingsTile(
            icon: Icons.account_balance_wallet_outlined,
            title: 'Manage wallets',
            subtitle: 'Archive and restore wallets',
            onTap: () => context.push('/wallet/manage'),
          ),
          _SettingsTile(
            icon: Icons.category_outlined,
            title: 'Manage categories',
            onTap: () => context.push('/category/manage'),
          ),
          _SettingsTile(
            icon: Icons.subscriptions_outlined,
            title: 'Detected subscriptions',
            onTap: () => context.push('/settings/subscriptions'),
          ),
          _SettingsTile(
            icon: Icons.donut_small_outlined,
            title: 'Budgets',
            onTap: () => context.push('/budgets'),
          ),
          _SettingsTile(
            icon: Icons.event_repeat_outlined,
            title: 'Recurring',
            onTap: () => context.push('/recurring'),
          ),
          _SettingsTile(
            icon: Icons.handshake_outlined,
            title: 'Debts',
            onTap: () => context.push('/debts'),
          ),
          _SettingsTile(
            icon: Icons.flag_outlined,
            title: 'Goals',
            onTap: () => context.push('/goals'),
          ),
          _SettingsTile(
            icon: Icons.info_outline,
            title: 'About',
            onTap: () => context.push('/settings/about'),
          ),
          const Divider(),
          ListTile(
            leading: Icon(Icons.logout, color: theme.colorScheme.error),
            title: Text(
              'Sign out',
              style: TextStyle(color: theme.colorScheme.error),
            ),
            onTap: () => _confirmSignOut(context, ref),
          ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.premiumBadge = false,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool premiumBadge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle!) : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (premiumBadge) ...[
            Icon(
              Icons.auto_awesome,
              color: theme.colorScheme.primary,
              size: 18,
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          const Icon(Icons.chevron_right),
        ],
      ),
      onTap: onTap,
    );
  }
}
