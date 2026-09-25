import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Splash screen animado y moderno con el logo oficial de la app.
/// Se adapta perfectamente a modo Oscuro (Dark) y modo Claro (White)
/// e incluye un Loading Spinner estilizado con la paleta de Slay.
///
/// **Perf**: las partes estáticas (logo, título, subtítulo) NO viven
/// dentro de ningún `AnimatedBuilder`, así que no se reconstruyen por
/// frame. El aura pulsa vía `Transform.scale` (pintura sin relayout)
/// dentro de su propio `RepaintBoundary`; el spinner rota en una capa
/// igualmente aislada. Al salir se detienen los controladores para no
/// quemar ciclos durante el fade-out.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.onComplete});
  final VoidCallback? onComplete;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _entryExitController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );

  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat(reverse: true);

  late final AnimationController _spinController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  late final Animation<double> _fadeAnimation = CurvedAnimation(
    parent: _entryExitController,
    curve: Curves.easeOut,
  );

  late final Animation<double> _scaleAnimation = Tween<double>(
    begin: 0.92,
    end: 1.0,
  ).animate(CurvedAnimation(
    parent: _entryExitController,
    curve: Curves.easeOutCubic,
  ));

  bool _isExiting = false;

  @override
  void initState() {
    super.initState();
    _entryExitController.forward();
    Future.delayed(const Duration(milliseconds: 850), () {
      if (!mounted) return;
      _dismiss();
    });
  }

  void _dismiss() async {
    if (_isExiting) return;
    _isExiting = true;
    _pulseController.stop();
    _spinController.stop();
    await _entryExitController.reverse();
    if (mounted) {
      widget.onComplete?.call();
    }
  }

  @override
  void dispose() {
    _entryExitController.dispose();
    _pulseController.dispose();
    _spinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final primaryColor =
        isDark ? const Color(0xFF34D399) : const Color(0xFF10B981);
    final accentColor =
        isDark ? const Color(0xFF22D3EE) : const Color(0xFF14B8A6);
    final bgColor = isDark ? const Color(0xFF0D0E12) : const Color(0xFFF8FAFC);
    final textColor = isDark ? const Color(0xFFF3F4F6) : const Color(0xFF111827);
    final subtleColor = isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);

    return FadeTransition(
      opacity: _fadeAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Material(
          color: bgColor,
          child: Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.2),
                radius: 1.3,
                colors: isDark
                    ? [
                        primaryColor.withValues(alpha: 0.15),
                        const Color(0xFF0E0F14),
                        const Color(0xFF07080A),
                      ]
                    : [
                        primaryColor.withValues(alpha: 0.12),
                        const Color(0xFFF9FAFB),
                        const Color(0xFFEEF2F6),
                      ],
              ),
            ),
            child: SafeArea(
              child: Stack(
                children: [
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 190,
                          height: 190,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              RepaintBoundary(
                                child: AnimatedBuilder(
                                  animation: _pulseController,
                                  builder: (_, __) {
                                    final t = Curves.easeInOut
                                        .transform(_pulseController.value);
                                    return Transform.scale(
                                      scale: 1.0 + 0.13 * t,
                                      child: Container(
                                        width: 150,
                                        height: 150,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          gradient: RadialGradient(
                                            colors: [
                                              primaryColor.withValues(
                                                alpha: isDark ? 0.35 : 0.22,
                                              ),
                                              primaryColor.withValues(alpha: 0.0),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              _LogoBadge(isDark: isDark, primaryColor: primaryColor),
                            ],
                          ),
                        ),
                        const SizedBox(height: 22),
                        Text(
                          'Slay',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                            fontSize: 34,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                color: primaryColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Domina tu día',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: subtleColor,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.4,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                color: primaryColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 56,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          RepaintBoundary(
                            child: AnimatedBuilder(
                              animation: _spinController,
                              builder: (_, __) => CustomPaint(
                                size: const Size(44, 44),
                                painter: _CometSpinnerPainter(
                                  rotation:
                                      _spinController.value * 2 * math.pi,
                                  colors: [
                                    primaryColor.withValues(alpha: 0.0),
                                    accentColor,
                                    primaryColor,
                                  ],
                                  trackColor:
                                      primaryColor.withValues(alpha: 0.10),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Cargando...',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                              color: subtleColor.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LogoBadge extends StatelessWidget {
  const _LogoBadge({required this.isDark, required this.primaryColor});
  final bool isDark;
  final Color primaryColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF18191E) : Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.black.withValues(alpha: 0.06),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withValues(alpha: isDark ? 0.35 : 0.25),
            blurRadius: 30,
            spreadRadius: 2,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.40 : 0.08),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: CustomPaint(
          size: const Size(54, 54),
          painter: _SlayCheckPainter(
            gradient: LinearGradient(
              colors: isDark
                  ? [const Color(0xFF34D399), const Color(0xFF10B981)]
                  : [const Color(0xFF10B981), const Color(0xFF059669)],
            ),
          ),
        ),
      ),
    );
  }
}

class _CometSpinnerPainter extends CustomPainter {
  const _CometSpinnerPainter({
    required this.rotation,
    required this.colors,
    required this.trackColor,
  });
  final double rotation;
  final List<Color> colors;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final strokeWidth = size.shortestSide * 0.09;
    final radius = (size.shortestSide - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final sweep = math.pi * 1.45;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = trackColor,
    );

    final haloPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth * 2.4
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        colors: colors,
        transform: GradientRotation(rotation),
      ).createShader(rect);
    canvas.drawArc(rect, rotation, sweep, false, haloPaint);

    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        colors: colors,
        transform: GradientRotation(rotation),
      ).createShader(rect);
    canvas.drawArc(rect, rotation, sweep, false, arcPaint);

    final headAngle = rotation + sweep;
    final headCenter = center +
        Offset(math.cos(headAngle), math.sin(headAngle)) * radius;
    canvas.drawCircle(headCenter, strokeWidth * 0.85,
        Paint()..color = colors.last);
  }

  @override
  bool shouldRepaint(covariant _CometSpinnerPainter oldDelegate) =>
      oldDelegate.rotation != rotation ||
      oldDelegate.colors != colors ||
      oldDelegate.trackColor != trackColor;
}

class _SlayCheckPainter extends CustomPainter {
  const _SlayCheckPainter({required this.gradient});
  final Gradient gradient;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    path.moveTo(size.width * 0.22, size.height * 0.52);
    path.lineTo(size.width * 0.44, size.height * 0.74);
    path.lineTo(size.width * 0.80, size.height * 0.28);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}