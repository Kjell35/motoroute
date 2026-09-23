import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../domain/tour_entities.dart';

/// Statische Miniaturkarte einer GPX-Spur: der Track wird in den
/// verfügbaren Raum eingepasst und als Linie gezeichnet - bewusst OHNE
/// Karten-Tiles, damit das Tagebuch auch offline vollständig wirkt.
/// Orange Spur auf dunklem Grund, wie die Navigationslinie.
class TrackThumbnail extends StatelessWidget {
  final List<TrackPoint> track;
  final bool large;

  const TrackThumbnail({super.key, required this.track, this.large = false});

  @override
  Widget build(BuildContext context) {
    if (track.length < 2) {
      return Container(
        decoration: BoxDecoration(
          color: AppColors.bgSurfaceRaisedDark,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.borderHairlineDark),
        ),
        child: const Icon(Icons.route_outlined, color: AppColors.textMutedDark),
      );
    }
    return CustomPaint(
      painter: _TrackPainter(track: track),
      size: Size.infinite,
    );
  }
}

class _TrackPainter extends CustomPainter {
  final List<TrackPoint> track;
  _TrackPainter({required this.track});

  @override
  void paint(Canvas canvas, Size size) {
    // Equirectangular-Projektion um den Track-Mittelpunkt - für eine
    // Miniatur reicht das völlig und bleibt linear/billig.
    double minLat = track.first.lat, maxLat = track.first.lat;
    double minLng = track.first.lng, maxLng = track.first.lng;
    for (final p in track) {
      minLat = math.min(minLat, p.lat);
      maxLat = math.max(maxLat, p.lat);
      minLng = math.min(minLng, p.lng);
      maxLng = math.max(maxLng, p.lng);
    }
    final midLat = (minLat + maxLat) / 2;
    const kx = 111320.0; // Meter pro Grad Länge am Äquator
    const ky = 111320.0;
    final cosMid = math.cos(midLat * math.pi / 180);

    final mx = (double x) => x * kx * cosMid;
    final my = (double y) => y * ky;

    final minX = mx(minLng);
    final minY = my(minLat);
    final spanX = (mx(maxLng) - minX).abs().clamp(1.0, double.infinity);
    final spanY = (my(maxLat) - minY).abs().clamp(1.0, double.infinity);

    final pad = size.width * 0.08;
    final scaleX = (size.width - 2 * pad) / spanX;
    final scaleY = (size.height - 2 * pad) / spanY;
    final scale = math.min(scaleX, scaleY);

    final offsetX = (size.width - spanX * scale) / 2;
    final offsetY = (size.height - spanY * scale) / 2;

    Offset toPoint(TrackPoint p) => Offset(
          offsetX + (mx(p.lng) - minX) * scale,
          size.height - (offsetY + (my(p.lat) - minY) * scale),
        );

    // Sanfter Glow hinter der Linie.
    final glow = Paint()
      ..color = AppColors.accentPrimaryDark.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final line = Paint()
      ..color = AppColors.accentPrimaryDark
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path()..moveTo(toPoint(track.first).dx, toPoint(track.first).dy);
    for (var i = 1; i < track.length; i++) {
      final pt = toPoint(track[i]);
      path.lineTo(pt.dx, pt.dy);
    }

    canvas.drawPath(path, glow);

    // Start (türkis) und Ziel (orange) markieren.
    final startP = toPoint(track.first);
    final endP = toPoint(track.last);
    canvas.drawCircle(startP, 4, Paint()..color = AppColors.accentSecondary);
    canvas.drawCircle(endP, 4, Paint()..color = AppColors.accentPrimaryDark);
    canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(covariant _TrackPainter oldDelegate) => oldDelegate.track != track;
}
