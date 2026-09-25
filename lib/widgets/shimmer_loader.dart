import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Loader circular con efecto shimmer (brillo que recorre el borde).
/// Inspirado en el Shimmer Loader de Aceternity UI.
///
/// Uso:
///   ShimmerLoader(size: 44, strokeWidth: 3, color: Colors.green)
class ShimmerLoader extends StatefulWidget {
  const ShimmerLoader({
    super.key,
    this.size = 44,
    this.strokeWidth = 3,
    this.color,
    this.duration = const Duration(milliseconds: 1200),
  });

  final double size;
  final double strokeWidth;
  final Color? color;
  final Duration duration;

  @override
  State<ShimmerLoader> createState() => _ShimmerLoaderState();
}

class _ShimmerLoaderState extends State<ShimmerLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: widget.duration,
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return CustomPaint(
          size: Size(widget.size, widget.size),
          painter: _ShimmerPainter(
            progress: _ctrl.value,
            color: color,
            strokeWidth: widget.strokeWidth,
          ),
        );
      },
    );
  }
}

class _ShimmerPainter extends CustomPainter {
  _ShimmerPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
  });

  final double progress;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // 1. Base arc (track tenue)
    final basePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: 0.15);
    canvas.drawArc(rect, 0, 2 * math.pi, false, basePaint);

    // 2. Shimmer: un arco brillante que rota, con gradiente que se desvanece
    //    en las puntas para dar efecto de "cola".
    final shimmerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // El ángulo de rotación (en radianes).
    final angle = progress * 2 * math.pi;

    // Creamos un SweepGradient con el color brillante en el centro
    // y transparente en los extremos.
    shimmerPaint.shader = SweepGradient(
      startAngle: angle - 0.8,
      endAngle: angle + 0.8,
      colors: [
        Colors.transparent,
        color.withValues(alpha: 0.05),
        color.withValues(alpha: 0.4),
        color,
        color.withValues(alpha: 0.4),
        color.withValues(alpha: 0.05),
        Colors.transparent,
      ],
      stops: const [0.0, 0.2, 0.35, 0.5, 0.65, 0.8, 1.0],
      transform: _SweepRotation(angle),
    ).createShader(rect);

    canvas.drawArc(rect, 0, 2 * math.pi, false, shimmerPaint);

    // 3. Punto brillante en la cabeza del shimmer (efecto glow).
    final headAngle = angle + 0.8;
    final headX = center.dx + radius * math.cos(headAngle);
    final headY = center.dy + radius * math.sin(headAngle);

    final glowPaint = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6)
      ..color = color.withValues(alpha: 0.6);
    canvas.drawCircle(Offset(headX, headY), strokeWidth * 0.8, glowPaint);
  }

  @override
  bool shouldRepaint(_ShimmerPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.strokeWidth != strokeWidth;
}

/// Rotación personalizada para el SweepGradient.
class _SweepRotation extends GradientTransform {
  const _SweepRotation(this.angle);
  final double angle;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    final cx = bounds.center.dx;
    final cy = bounds.center.dy;
    return Matrix4.identity()
      ..translateByDouble(cx, cy, 0.0, 1.0)
      ..rotateZ(angle)
      ..translateByDouble(-cx, -cy, 0.0, 1.0);
  }
}