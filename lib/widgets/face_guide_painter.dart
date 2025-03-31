import 'package:flutter/material.dart';
import 'dart:math' as math;

class FaceGuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.2)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final ovalRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: size.width * 0.65,
      height: size.height * 0.45,
    );
    _drawDashedOval(canvas, ovalRect, paint);

    final guidelinePaint = Paint()
      ..color = Colors.white.withOpacity(0.1)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;

    _drawDashedLine(
      canvas,
      Offset(size.width / 2, size.height * 0.25),
      Offset(size.width / 2, size.height * 0.75),
      guidelinePaint,
    );

    _drawDashedLine(
      canvas,
      Offset(size.width * 0.35, size.height / 2),
      Offset(size.width * 0.65, size.height / 2),
      guidelinePaint,
    );

    _drawCornerMarkers(canvas, size, paint);
  }

  void _drawDashedOval(Canvas canvas, Rect rect, Paint paint) {
    const int dashCount = 60;
    const double dashGap = 0.1;

    for (int i = 0; i < dashCount; i++) {
      final double startAngle = 2 * math.pi * i / dashCount;
      final double endAngle = 2 * math.pi * (i + (1 - dashGap)) / dashCount;

      canvas.drawArc(
        rect,
        startAngle,
        endAngle - startAngle,
        false,
        paint,
      );
    }
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    const int dashCount = 10;
    final double dx = (end.dx - start.dx) / dashCount;
    final double dy = (end.dy - start.dy) / dashCount;

    for (int i = 0; i < dashCount; i += 2) {
      canvas.drawLine(
        Offset(start.dx + i * dx, start.dy + i * dy),
        Offset(start.dx + (i + 1) * dx, start.dy + (i + 1) * dy),
        paint,
      );
    }
  }

  void _drawCornerMarkers(Canvas canvas, Size size, Paint paint) {
    final cornerPaint = Paint()
      ..color = Colors.white.withOpacity(0.3)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final cornerSize = size.width * 0.06;

    _drawCorner(canvas, Offset(size.width * 0.25, size.height * 0.30), cornerSize, cornerPaint, 0);
    _drawCorner(canvas, Offset(size.width * 0.75, size.height * 0.30), cornerSize, cornerPaint, 1);
    _drawCorner(canvas, Offset(size.width * 0.75, size.height * 0.70), cornerSize, cornerPaint, 2);
    _drawCorner(canvas, Offset(size.width * 0.25, size.height * 0.70), cornerSize, cornerPaint, 3);
  }

  void _drawCorner(Canvas canvas, Offset center, double size, Paint paint, int position) {
    final startX = position == 0 || position == 3 ? center.dx : center.dx - size;
    final startY = position == 0 || position == 1 ? center.dy : center.dy - size;
    final endX = position == 1 || position == 2 ? center.dx : center.dx + size;
    final endY = position == 2 || position == 3 ? center.dy : center.dy + size;

    if (position == 0) { // Top left
      canvas.drawLine(Offset(startX, startY + size), Offset(startX, startY), paint);
      canvas.drawLine(Offset(startX, startY), Offset(startX + size, startY), paint);
    } else if (position == 1) { // Top right
      canvas.drawLine(Offset(endX, startY + size), Offset(endX, startY), paint);
      canvas.drawLine(Offset(endX, startY), Offset(endX - size, startY), paint);
    } else if (position == 2) { // Bottom right
      canvas.drawLine(Offset(endX, endY - size), Offset(endX, endY), paint);
      canvas.drawLine(Offset(endX, endY), Offset(endX - size, endY), paint);
    } else { // Bottom left
      canvas.drawLine(Offset(startX, endY - size), Offset(startX, endY), paint);
      canvas.drawLine(Offset(startX, endY), Offset(startX + size, endY), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
