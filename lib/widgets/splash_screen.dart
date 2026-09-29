import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/terminal_theme.dart';

/// Splash estilo terminal: fondo plano cálido, prompt `>_` en naranja,
/// palabra en pixel font y spinner de bloques. Sin gradientes ni glows.
///
/// **Perf**: las partes estáticas (logo, título, subtítulo) NO viven
/// dentro de ningún `AnimatedBuilder`, así que no se reconstruyen por
/// frame. El spinner rota en una capa aislada (RepaintBoundary). Al salir
/// se detienen los controladores para no quemar ciclos durante el fade.
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
    _spinController.stop();
    await _entryExitController.reverse();
    if (mounted) {
      widget.onComplete?.call();
    }
  }

  @override
  void dispose() {
    _entryExitController.dispose();
    _spinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? TerminalTheme.nightBg : TerminalTheme.dayBg;
    final fg = isDark ? TerminalTheme.nightFg : TerminalTheme.dayFg;
    final accent = isDark ? TerminalTheme.nightAccent : TerminalTheme.dayAccent;
    final muted = isDark ? TerminalTheme.nightMuted : TerminalTheme.dayMuted;
    final line = isDark ? TerminalTheme.nightLine : TerminalTheme.dayLine;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Material(
          color: bg,
          child: SafeArea(
            child: Stack(
              children: [
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Prompt de la casa: >_ en naranja.
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '>',
                            style: TextStyle(
                              fontFamily: TerminalTheme.pixelFamily,
                              fontSize: 56,
                              height: 1,
                              color: accent,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 9),
                            child: Container(
                              width: 36,
                              height: 10,
                              color: accent,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 26),
                      Text(
                        'Slay',
                        style: TextStyle(
                          fontFamily: TerminalTheme.pixelFamily,
                          fontSize: 38,
                          height: 1.15,
                          color: fg,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(width: 6, height: 6, color: accent),
                          const SizedBox(width: 8),
                          Text(
                            'Domina tu día',
                            style: TextStyle(
                              fontFamily: TerminalTheme.monoFamily,
                              color: muted,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.8,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(width: 6, height: 6, color: accent),
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
                              size: const Size(36, 36),
                              painter: _BlockSpinnerPainter(
                                rotation: _spinController.value * 2 * 3.14159,
                                color: accent,
                                trackColor: line,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Cargando...',
                          style: TextStyle(
                            fontFamily: TerminalTheme.monoFamily,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                            color: muted.withValues(alpha: 0.7),
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
    );
  }
}

/// Spinner de la casa: bloques cuadrados orbitando, sin arcos redondeados.
class _BlockSpinnerPainter extends CustomPainter {
  _BlockSpinnerPainter({
    required this.rotation,
    required this.color,
    required this.trackColor,
  });

  final double rotation;
  final Color color;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    // Pista: 8 bloques apagados en círculo.
    const total = 8;
    final trackPaint = Paint()..color = trackColor;
    for (var i = 0; i < total; i++) {
      final angle = (i / total) * 2 * math.pi;
      final pos =
          center + Offset(radius * math.cos(angle), radius * math.sin(angle));
      canvas.drawRect(
        Rect.fromCenter(center: pos, width: 4, height: 4),
        trackPaint,
      );
    }

    // Bloques activos: los 3 primeros tras la rotación van llenos.
    final activePaint = Paint()..color = color;
    for (var i = 0; i < 3; i++) {
      final angle = rotation + (i / total) * 2 * math.pi;
      final pos =
          center + Offset(radius * math.cos(angle), radius * math.sin(angle));
      canvas.drawRect(
        Rect.fromCenter(center: pos, width: 5, height: 5),
        activePaint,
      );
    }
  }

  @override
  bool shouldRepaint(_BlockSpinnerPainter oldDelegate) =>
      oldDelegate.rotation != rotation;
}
