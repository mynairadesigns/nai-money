import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/spacing.dart';
import '../providers/security_providers.dart';
import '../widgets/pin_keypad.dart';

const _kPinLength = 6;

/// Two-step PIN setup: enter new PIN → confirm PIN → save.
/// Used for first-time setup AND "Change PIN" flows.
///
/// Pops with `true` on success, nothing/false on cancel.
class PinSetupScreen extends ConsumerStatefulWidget {
  const PinSetupScreen({super.key});

  @override
  ConsumerState<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends ConsumerState<PinSetupScreen>
    with SingleTickerProviderStateMixin {
  String _pin = '';
  String? _firstPin;
  bool _inConfirmStep = false;
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
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  void _onDigit(String digit) {
    if (_pin.length >= _kPinLength) return;
    setState(() {
      _pin += digit;
      _hasError = false;
    });
    if (_pin.length == _kPinLength) {
      _onComplete();
    }
  }

  void _onBackspace() {
    if (_pin.isEmpty) return;
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
      _hasError = false;
    });
  }

  Future<void> _onComplete() async {
    if (!_inConfirmStep) {
      // First step: store and move to confirm.
      setState(() {
        _firstPin = _pin;
        _pin = '';
        _inConfirmStep = true;
      });
      return;
    }

    // Confirm step: compare PINs.
    if (_pin != _firstPin) {
      await _shakeController.forward(from: 0);
      setState(() {
        _pin = '';
        _hasError = true;
      });
      return;
    }

    // Save PIN.
    final service = ref.read(securityServiceProvider);
    await service.setPin(_pin);
    await ref.read(securitySettingsProvider.notifier).setLockEnabled(true);
    await ref.read(securitySettingsProvider.notifier).refreshHasPin();

    if (!mounted) return;
    context.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Set up PIN'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Column(
            children: [
              const Spacer(),
              Text(
                _inConfirmStep ? 'Confirm your PIN' : 'Choose a PIN',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                _inConfirmStep
                    ? 'Enter the same PIN again to confirm'
                    : 'You\'ll use this to unlock the app',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
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
                  'PINs don\'t match. Try again.',
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
            ],
          ),
        ),
      ),
    );
  }
}
