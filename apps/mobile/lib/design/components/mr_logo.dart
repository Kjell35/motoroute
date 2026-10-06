import 'dart:ui';

import 'package:flutter/material.dart';

import '../tokens/mr_colors.dart';

/// Wortmarken-Logo „Midnight Asphalt“: gerundetes Hex mit Route-Schwung.
/// Bewusst CustomPaint statt Bilddatei – skaliert verlustfrei und bleibt editierbar.
class MrLogo extends StatelessWidget {
  const MrLogo({super.key, this.size = 64});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _MrLogoPainter(),
    );
  }
}

class _MrLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final r = Radius.circular(s * 0.24);
    final box = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, s, s),
      r,
    );

    canvas.drawRRect(box, Paint()..color = MrColors.card);
    canvas.drawRRect(
      box,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.02
        ..color = MrColors.stroke,
    );

    // Route: geschwungener Pfad mit Wendepunkt („kurvig“)
    final path = Path()
      ..moveTo(s * 0.22, s * 0.78)
      ..cubicTo(s * 0.10, s * 0.58, s * 0.34, s * 0.52, s * 0.44, s * 0.56)
      ..cubicTo(s * 0.56, s * 0.61, s * 0.52, s * 0.40, s * 0.62, s * 0.34)
      ..cubicTo(s * 0.70, s * 0.29, s * 0.76, s * 0.30, s * 0.80, s * 0.24);

    final routePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.075
      ..strokeCap = StrokeCap.round
      ..color = MrColors.accentPrimary;

    // Dunkles Casing unter der Route für Kontrast (Design-System §2)
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.115
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF12151A),
    );
    canvas.drawPath(path, routePaint);

    // Zielpunkt
    canvas.drawCircle(
      Offset(s * 0.80, s * 0.24),
      s * 0.055,
      Paint()..color = MrColors.accentSecondary,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
