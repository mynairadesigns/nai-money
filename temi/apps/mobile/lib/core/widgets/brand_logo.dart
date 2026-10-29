import 'package:flutter/material.dart';

/// Temi Finance brand mark: a white "T.F" monogram on a London-red rounded
/// square.
///
/// Drawn from the same 1024-unit geometry as the launcher / web icons in
/// `assets/branding/logo.svg`, so every surface matches exactly. The brand
/// red is fixed (not theme-derived) so the mark reads the same in light and
/// dark mode.
class BrandLogo extends StatelessWidget {
  const BrandLogo({this.size = 64, super.key});

  /// Edge length of the (square) mark.
  final double size;

  /// London bus red.
  static const brandRed = Color(0xFFDA291C);

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: const CustomPaint(painter: _HfPainter()),
    );
  }
}

class _HfPainter extends CustomPainter {
  const _HfPainter();

  // (left, top, right, bottom) on a 1024 grid — keep in sync with logo.svg.
  static const _rects = <List<double>>[
    [143, 309, 448, 398], // T bar
    [251, 309, 340, 715], // T stem
    [627, 309, 716, 715], // F stem
    [627, 309, 881, 398], // F top arm
    [627, 473, 834, 563], // F middle arm
  ];

  // The "." between T and F: centre x, centre y, radius.
  static const _dot = [537.0, 670.0, 45.0];

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 1024;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(size.width * 0.2),
      ),
      Paint()..color = BrandLogo.brandRed,
    );
    final white = Paint()
      ..color = Colors.white
      ..isAntiAlias = true;
    for (final r in _rects) {
      canvas.drawRect(
        Rect.fromLTRB(r[0] * k, r[1] * k, r[2] * k, r[3] * k),
        white,
      );
    }
    canvas.drawCircle(Offset(_dot[0] * k, _dot[1] * k), _dot[2] * k, white);
  }

  @override
  bool shouldRepaint(covariant _HfPainter oldDelegate) => false;
}
