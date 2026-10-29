import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../../core/theme/shapes.dart';
import '../../../core/theme/spacing.dart';
import '../providers/auth_controller.dart';

class SocialSignInButtons extends ConsumerWidget {
  const SocialSignInButtons({super.key});

  // iOS-only: Apple's "Sign in with Apple" button. The `kIsWeb` guard must
  // come first — `Platform.isIOS` touches `dart:io`, which is unsupported on
  // web (&& short-circuits before it's reached).
  bool get _showAppleButton => !kIsWeb && Platform.isIOS;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final controller = ref.watch(authControllerProvider.notifier);
    final isLoading = ref.watch(authControllerProvider).isLoading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Text(
                'or',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        OutlinedButton.icon(
          onPressed: isLoading ? null : controller.signInWithGoogle,
          icon: const Icon(Icons.g_mobiledata, size: 28),
          label: const Text('Continue with Google'),
        ),
        if (_showAppleButton) ...[
          const SizedBox(height: AppSpacing.sm),
          SignInWithAppleButton(
            onPressed: isLoading ? () {} : controller.signInWithApple,
            style: theme.brightness == Brightness.dark
                ? SignInWithAppleButtonStyle.white
                : SignInWithAppleButtonStyle.black,
            borderRadius: AppBorderRadius.base,
            height: 48,
          ),
        ],
      ],
    );
  }
}
