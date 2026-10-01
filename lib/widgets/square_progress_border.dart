import 'dart:ui';

import 'package:flutter/material.dart';

/// Borde cuadrado cuyo perímetro se va dibujando según [progress]
/// (0..1), recorriendo los 4 lados desde el medio del superior, en
/// sentido horario. El [child] se dibuja encima, con [padding] de
/// separación respecto al borde.
///
/// Reemplaza al CircularProgressIndicator (círculo) en la sesión de
/// foco: el círculo no iba con la estética terminal de la app.
class SquareProgressBorder extends StatelessWidget {
  const SquareProgressBorder({
    super.key,
    required this.progress,
    required this.color,
    required this.trackColor,
    required this.strokeWidth,
    required this.padding,
    required this.child,
  });

  /// Progreso 0..1 del perímetro dibujado.
  final double progress;

  /// Color del trazo de progreso.
  final Color color;

  /// Color del perímetro completo (pista detrás del progreso).
  final Color trackColor;

  /// Grosor del trazo.
  final double strokeWidth;

  /// Separación entre el borde y el [child].
  final double padding;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _SquareProgressPainter(
              progress: progress.clamp(0.0, 1.0),
              color: color,
              trackColor: trackColor,
              strokeWidth: strokeWidth,
            ),
          ),
        ),
        Padding(padding: EdgeInsets.all(padding + strokeWidth), child: child),
      ],
    );
  }
}

/// Un segmento recto del perímetro, con longitud precalculada.
class _Seg {
  const _Seg(this.end, this.length);
  final Offset end;
  final double length;
}

class _SquareProgressPainter extends CustomPainter {
  _SquareProgressPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
    required this.strokeWidth,
  });

  final double progress;
  final Color color;
  final Color trackColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = strokeWidth / 2;
    final rect = Rect.fromLTRB(
      inset,
      inset,
      size.width - inset,
      size.height - inset,
    );

    // Pista completa (perímetro entero, tinta tenue).
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawRect(rect, trackPaint);

    if (progress <= 0) return;

    final w = rect.width;
    final h = rect.height;
    final start = Offset(rect.left + w / 2, rect.top);

    // Segmentos en sentido horario desde el medio del lado superior:
    // medio-sup → sup-der → inf-der → inf-izq → sup-izq → medio-sup.
    final segments = <_Seg>[
      _Seg(Offset(rect.right, rect.top), w / 2),
      _Seg(Offset(rect.right, rect.bottom), h),
      _Seg(Offset(rect.left, rect.bottom), w),
      _Seg(Offset(rect.left, rect.top), h),
      _Seg(start, w / 2),
    ];

    final total = segments.fold<double>(0, (m, s) => m + s.length);
    var remaining = progress.clamp(0.0, 1.0) * total;

    final path = Path()..moveTo(start.dx, start.dy);
    for (final seg in segments) {
      if (remaining <= 0) break;
      final from = pathLastOffset(path);
      if (remaining >= seg.length) {
        path.lineTo(seg.end.dx, seg.end.dy);
        remaining -= seg.length;
      } else {
        final t = remaining / seg.length;
        final partial = Offset(
          from.dx + (seg.end.dx - from.dx) * t,
          from.dy + (seg.end.dy - from.dy) * t,
        );
        path.lineTo(partial.dx, partial.dy);
        remaining = 0;
      }
    }

    final progressPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;
    canvas.drawPath(path, progressPaint);
  }

  /// `Path` no expone el último punto; como todos los segmentos son
  /// lineTo encadenados desde `start`, lo reconstruimos acumulando.
  static Offset pathLastOffset(Path path) {
    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return Offset.zero;
    final m = metrics.last;
    final contour = m.getTangentForOffset(m.length);
    return contour?.position ?? Offset.zero;
  }

  @override
  bool shouldRepaint(_SquareProgressPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.trackColor != trackColor ||
      old.strokeWidth != strokeWidth;
}
