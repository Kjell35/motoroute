// Generiert tool/motoroute_icon.png (1024x1024): Der MotoRoute-Launcher.
//
// Design passend zum App-Theme (AppColors aus Phase 3 Teil B.1):
// Dunkler abgerundeter Hintergrund (bgSurfaceDark ~ #14181C), orange
// Route (accentPrimaryDark ~ #FF5A1F) als geschwungene Straße, weißer
// Startpunkt, Zielpin am Ende. Bewusst flach, damit es in allen
// Launcher-Dichten liest - Details sterben auf 48 dp.
//
// Ausführen:  dart run tool/generate_icon.dart
import 'dart:io';
import 'dart:math' show sin, pi;

import 'package:image/image.dart' as img;

const int size = 1024;
const double radiusRatio = 0.2257; // Android Adaptive-Icon-Safe-Zone
final bg = img.ColorRgba8(20, 24, 28, 255); // #14181C
final route = img.ColorRgba8(255, 90, 31, 255); // #FF5A1F
final routeGlow = img.ColorRgba8(255, 90, 31, 90);
final white = img.ColorRgba8(245, 246, 244, 255);

void main() {
  var image = img.Image(width: size, height: size);
  img.fillRect(image, x1: 0, y1: 0, x2: size - 1, y2: size - 1, color: bg);

  // Route: S-förmige Kurve von unten links nach oben rechts, als dicke
  // Punktfolge (Glow-Layer darunter, Kern darüber).
  final curve = <img.Point>[];
  for (double t = 0; t <= 1.0; t += 0.004) {
    final x = 0.16 + 0.62 * t;
    final y = 0.86 - 0.64 * t - 0.14 * sin(t * pi) * (1 - t * 0.4);
    curve.add(img.Point((x * size).round(), (y * size).round()));
  }

  void drawCurve(int width, img.ColorRgba8 color) {
    for (final p in curve) {
      image = img.fillCircle(
        image,
        x: p.x as int,
        y: p.y as int,
        radius: width ~/ 2,
        color: color,
      );
    }
  }

  drawCurve(96, routeGlow);
  drawCurve(64, route);

  // Startpunkt: weißer Punkt am Kurvenanfang.
  final start = curve.first;
  image = img.fillCircle(
    image,
    x: (start.x as int) + 24,
    y: (start.y as int) - 12,
    radius: 26,
    color: white,
  );

  // Zielpin: Kreis + Dreieck nach unten (Marker-Silhouette) mit dunklem
  // Kern-Loch.
  const pinCx = 812;
  const pinCy = 200;
  image = img.fillCircle(image, x: pinCx, y: pinCy, radius: 88, color: route);
  image = img.fillPolygon(
    image,
    vertices: [
      img.Point(pinCx - 58, pinCy + 46),
      img.Point(pinCx + 58, pinCy + 46),
      img.Point(pinCx, pinCy + 195),
    ],
    color: route,
  );
  image = img.fillCircle(image, x: pinCx, y: pinCy, radius: 36, color: bg);

  File('tool/motoroute_icon.png').writeAsBytesSync(img.encodePng(image));
  stdout.writeln('tool/motoroute_icon.png geschrieben (${size}x$size)');
}
