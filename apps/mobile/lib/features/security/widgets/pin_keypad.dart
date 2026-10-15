import 'package:flutter/material.dart';

import '../../../core/theme/shapes.dart';
import '../../../core/theme/spacing.dart';

/// A reusable numeric PIN keypad widget (digits 0-9 + backspace).
///
/// Fires [onDigit] when a digit is tapped and [onBackspace] when backspace is
/// tapped. The host widget owns the PIN buffer and passes it back via
/// [currentPin] to display the dot indicator.
class PinKeypad extends StatelessWidget {
  const PinKeypad({
    required this.onDigit,
    required this.onBackspace,
    super.key,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;

  static const _keys = [
    '1', '2', '3',
    '4', '5', '6',
    '7', '8', '9',
    '',  '0', 'back',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: AppSpacing.sm,
      crossAxisSpacing: AppSpacing.sm,
      childAspectRatio: 1.6,
      children: _keys.map((key) {
        if (key.isEmpty) return const SizedBox.shrink();
        if (key == 'back') {
          return _KeyButton(
            onTap: onBackspace,
            child: Icon(
              Icons.backspace_outlined,
              color: theme.colorScheme.onSurface,
              size: 22,
            ),
          );
        }
        return _KeyButton(
          onTap: () => onDigit(key),
          child: Text(
            key,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _KeyButton extends StatelessWidget {
  const _KeyButton({required this.onTap, required this.child});
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: AppBorderRadius.md,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Center(child: child),
      ),
    );
  }
}

/// Displays [length] empty / filled dot indicators representing PIN progress.
class PinDots extends StatelessWidget {
  const PinDots({
    required this.length,
    required this.filled,
    this.hasError = false,
    super.key,
  });

  final int length;
  final int filled;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dotColor = hasError
        ? theme.colorScheme.error
        : theme.colorScheme.primary;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(length, (i) {
        final isFilled = i < filled;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isFilled ? dotColor : Colors.transparent,
            border: Border.all(
              color: hasError ? theme.colorScheme.error : theme.colorScheme.outline,
              width: 1.5,
            ),
          ),
        );
      }),
    );
  }
}
