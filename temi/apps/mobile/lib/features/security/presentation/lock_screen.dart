import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/spacing.dart';
import '../../../core/widgets/brand_logo.dart';
import '../providers/security_providers.dart';
import '../widgets/pin_keypad.dart';

const _kPinLength = 6; // supports both 4 and 6 — we default to 6

/// Full-screen lock gate presented when [appLockProvider] reports locked.
/// Has no back button — the user must authenticate to proceed.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen>
    with SingleTickerProviderStateMixin {
  String _pin = '';
  bool _hasError = false;
  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -8.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -8.0, end: 8.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8.0, end: -8.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -8.0, end: 8.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8.0, end: 0.0), weight: 1),
    ]).animate(_shakeController);

    // Auto-prompt biometric on mount if enabled.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryBiometric();
    });
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  Future<void> _tryBiometric() async {
    final settings = ref.read(securitySettingsProvider);
    if (!settings.biometricEnabled) return;
    final service = ref.read(securityServiceProvider);
    final ok = await service.authenticateBiometric(
      'Authenticate to unlock Temi Finance',
    );
    if (ok && mounted) {
      ref.read(appLockProvider.notifier).unlock();
    }
  }

  void _onDigit(String digit) {
    if (_pin.length >= _kPinLength) return;
    setState(() {
      _pin += digit;
      _hasError = false;
    });
    if (_pin.length == _kPinLength) {
      _verifyPin();
    }
  }

  void _onBackspace() {
    if (_pin.isEmpty) return;
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
      _hasError = false;
    });
  }

  Future<void> _verifyPin() async {
    final service = ref.read(securityServiceProvider);
    final ok = await service.verifyPin(_pin);
    if (!mounted) return;
    if (ok) {
      ref.read(appLockProvider.notifier).unlock();
    } else {
      await _shakeController.forward(from: 0);
      setState(() {
        _pin = '';
        _hasError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(securitySettingsProvider);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Column(
            children: [
              const Spacer(),
              const BrandLogo(size: 72),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Enter your PIN',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.xl),
              AnimatedBuilder(
                animation: _shakeAnimation,
                builder: (context, child) => Transform.translate(
                  offset: Offset(_shakeAnimation.value, 0),
                  child: child,
                ),
                child: PinDots(
                  length: _kPinLength,
                  filled: _pin.length,
                  hasError: _hasError,
                ),
              ),
              if (_hasError) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Incorrect PIN. Try again.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              const Spacer(),
              PinKeypad(
                onDigit: _onDigit,
                onBackspace: _onBackspace,
              ),
              const SizedBox(height: AppSpacing.lg),
              if (settings.biometricEnabled)
                TextButton.icon(
                  onPressed: _tryBiometric,
                  icon: const Icon(Icons.fingerprint),
                  label: const Text('Use biometric'),
                ),
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }
}
