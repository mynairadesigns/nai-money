import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/spacing.dart';
import '../providers/security_providers.dart';
import 'pin_setup_screen.dart';

/// Security settings screen at `/settings/security`.
///
/// Surfaces:
///   - App lock toggle (PIN required)
///   - Change PIN (when lock enabled)
///   - Biometric unlock toggle (when lock enabled + biometric available)
///   - Auto-lock interval picker
class SecuritySettingsScreen extends ConsumerStatefulWidget {
  const SecuritySettingsScreen({super.key});

  @override
  ConsumerState<SecuritySettingsScreen> createState() =>
      _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState
    extends ConsumerState<SecuritySettingsScreen> {
  bool _biometricAvailable = false;

  @override
  void initState() {
    super.initState();
    // Load async flags on mount.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(securitySettingsProvider.notifier).refresh();
      if (!mounted) return;
      final available = await ref
          .read(securityServiceProvider)
          .isBiometricAvailable();
      if (mounted) setState(() => _biometricAvailable = available);
    });
  }

  Future<void> _toggleLock(bool value, SecuritySettings settings) async {
    if (value) {
      // Turning ON — ensure a PIN is set first.
      if (!settings.hasPin) {
        final result = await Navigator.of(context).push<bool>(
          MaterialPageRoute<bool>(
            builder: (_) => const PinSetupScreen(),
          ),
        );
        // PinSetupScreen calls setLockEnabled(true) internally on success.
        // If they cancelled, don't enable lock.
        if (result != true) return;
        // Refresh to pick up new state.
        await ref.read(securitySettingsProvider.notifier).refresh();
      } else {
        await ref.read(securitySettingsProvider.notifier).setLockEnabled(true);
      }
    } else {
      await ref.read(securitySettingsProvider.notifier).setLockEnabled(false);
    }
  }

  Future<void> _changePinFlow() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => const PinSetupScreen(),
      ),
    );
    if (!mounted) return;
    await ref.read(securitySettingsProvider.notifier).refresh();
  }

  Future<void> _showAutoLockPicker(SecuritySettings settings) async {
    const options = <({int minutes, String label})>[
      (minutes: 0, label: 'Immediately'),
      (minutes: 1, label: 'After 1 minute'),
      (minutes: 5, label: 'After 5 minutes'),
      (minutes: 15, label: 'After 15 minutes'),
      (minutes: -1, label: 'Never'),
    ];

    final picked = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: AppSpacing.sm),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Text(
                'Auto-lock',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            const Divider(),
            for (final opt in options)
              ListTile(
                title: Text(opt.label),
                trailing: settings.autoLockMinutes == opt.minutes
                    ? Icon(
                        Icons.check,
                        color: Theme.of(ctx).colorScheme.primary,
                      )
                    : null,
                onTap: () => Navigator.of(ctx).pop(opt.minutes),
              ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );

    if (picked != null) {
      await ref
          .read(securitySettingsProvider.notifier)
          .setAutoLockMinutes(picked);
    }
  }

  String _autoLockLabel(int minutes) {
    switch (minutes) {
      case 0:
        return 'Immediately';
      case 1:
        return 'After 1 minute';
      case 5:
        return 'After 5 minutes';
      case 15:
        return 'After 15 minutes';
      case -1:
        return 'Never';
      default:
        return 'After $minutes minutes';
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(securitySettingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Security')),
      body: ListView(
        children: [
          const SizedBox(height: AppSpacing.sm),
          SwitchListTile(
            secondary: const Icon(Icons.lock_outline),
            title: const Text('App lock'),
            subtitle: const Text('Require PIN to open the app'),
            value: settings.lockEnabled,
            onChanged: (v) => _toggleLock(v, settings),
          ),
          if (settings.lockEnabled) ...[
            ListTile(
              leading: const Icon(Icons.pin_outlined),
              title: const Text('Change PIN'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _changePinFlow,
            ),
            if (_biometricAvailable)
              SwitchListTile(
                secondary: const Icon(Icons.fingerprint),
                title: const Text('Unlock with biometric'),
                subtitle: const Text('Use Face ID or fingerprint'),
                value: settings.biometricEnabled,
                onChanged: (v) => ref
                    .read(securitySettingsProvider.notifier)
                    .setBiometricEnabled(v),
              ),
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: const Text('Auto-lock'),
              subtitle: Text(_autoLockLabel(settings.autoLockMinutes)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showAutoLockPicker(settings),
            ),
          ],
        ],
      ),
    );
  }
}
