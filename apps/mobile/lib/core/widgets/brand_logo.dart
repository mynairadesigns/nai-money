import 'package:flutter/material.dart';

import '../theme/shapes.dart';

/// In-app brand mark — three ascending Sand bars on a Warm Clay rounded
/// square. Mirrors the launcher icon authored by `tool/generate_logo.dart`
/// so the splash + onboarding + sign-in surfaces stay visually aligned
/// with the device launcher icon.
///
/// Theme-aware: resolves to `colorScheme.primary` background + `surface`
/// bars, so dark mode adapts without a second asset.
class BrandLogo extends StatelessWidget {
  const BrandLogo({this.size = 64, super.key});

  /// Edge length of the (square) outer container. Bars are proportional.
  final double size;

  // Heights / widths / gap mirror the launcher icon's ratios so the device
  // home screen and the in-app surfaces read identically.
  static const _barWidthRatio = 0.09;
  static const _barGapRatio = 0.06;
  static const _barHeightRatios = [0.35, 0.55, 0.75];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final barWidth = size * _barWidthRatio;
    final gap = size * _barGapRatio;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.all(
          Radius.circular(size * 0.176), // matches iOS 17.6% radius
        ),
      ),
      child: Padding(
        // Tallest bar = 0.75 * size, so symmetric vertical padding = 0.125
        // each side to vertically center the mark on the container.
        padding: EdgeInsets.symmetric(vertical: size * 0.125),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < _barHeightRatios.length; i++) ...[
              if (i > 0) SizedBox(width: gap),
              Container(
                width: barWidth,
                height: size * _barHeightRatios[i],
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: AppBorderRadius.full,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
