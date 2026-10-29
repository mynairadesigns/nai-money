// ignore_for_file: avoid_print
// Generates assets/branding/logo.png and logo_foreground.png from DESIGN.md
// tokens. Run via: `dart run tool/generate_logo.dart` from `apps/mobile/`.
//
// Why this exists: we author the brand mark programmatically so the source
// of truth for the placeholder is code, not a binary blob. When a real brand
// asset lands, drop a PNG into `assets/branding/` and delete this file.
import 'dart:io';

import 'package:image/image.dart' as img;

const int canvas = 1024;

// DESIGN.md tokens
final warmClay = img.ColorRgba8(0x8a, 0x4f, 0x37, 0xff); // primary
final sand = img.ColorRgba8(0xff, 0xf8, 0xf5, 0xff); // surface

// Three ascending bars: heights 35% / 55% / 75%, width ~9%, gap ~6%.
// Centered vertically on the canvas — tallest bar's bounding box is the
// reference, so all bars share a baseline at (canvas + tallest)/2.
void drawBars(
  img.Image image, {
  required int startX,
  required int baselineY,
  required int barWidth,
  required int gap,
  required List<int> heights,
  required int radius,
  required img.Color color,
}) {
  for (var i = 0; i < heights.length; i++) {
    final h = heights[i];
    final x1 = startX + i * (barWidth + gap);
    final y1 = baselineY - h;
    img.fillRect(
      image,
      x1: x1,
      y1: y1,
      x2: x1 + barWidth - 1,
      y2: baselineY - 1,
      color: color,
      radius: radius,
    );
  }
}

void main() {
  // ---- logo.png — full bleed, iOS + single-image source ----
  // No rounded corners on the source; iOS applies its own mask.
  // (We round our own corners in `BrandLogo` widget for in-app use.)
  final full = img.Image(width: canvas, height: canvas);
  img.fillRect(
    full,
    x1: 0,
    y1: 0,
    x2: canvas - 1,
    y2: canvas - 1,
    color: warmClay,
  );
  drawBars(
    full,
    startX: 313,
    baselineY: 896, // (1024 + 768) / 2 — tallest bar centered vertically
    barWidth: 92,
    gap: 61,
    heights: [358, 563, 768],
    radius: 46,
    color: sand,
  );
  File('assets/branding/logo.png').writeAsBytesSync(img.encodePng(full));
  print('Wrote assets/branding/logo.png (1024x1024, opaque)');

  // ---- logo_foreground.png — Android adaptive icon foreground layer ----
  // Transparent background; bars sized to fit inside the inner 66.7% safe
  // zone (170..854 in each axis).
  final fg = img.Image(
    width: canvas,
    height: canvas,
    numChannels: 4,
  );
  // Image() initializes to opaque black; clear to transparent.
  img.fill(fg, color: img.ColorRgba8(0, 0, 0, 0));
  drawBars(
    fg,
    startX: 379,
    baselineY: 768, // 170 + (684 + 512)/2 — centered within safe zone
    barWidth: 61,
    gap: 41,
    heights: [239, 376, 512],
    radius: 30,
    color: sand,
  );
  File('assets/branding/logo_foreground.png')
      .writeAsBytesSync(img.encodePng(fg));
  print('Wrote assets/branding/logo_foreground.png (1024x1024, transparent)');
}
