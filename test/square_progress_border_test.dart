/// Regresión visual del borde cuadrado de progreso.
///
/// Bug: al arrancar la sesión (progreso chico, <12.5% del perímetro),
/// la silueta naranja se dibujaba en DIAGONAL desde la esquina del
/// lienzo ("se sale de su lugar, después se arregla"): el punto
/// actual se pedía con `computeMetrics` sobre un path recién
/// `moveTo` (sin `lineTo`) y el fallback era `Offset.zero`.
///
/// Fix: `squareProgressPath` lleva el punto actual de forma explícita.
/// El path de un progreso chico tiene que vivir SOBRE el perímetro
/// (empezando en el medio del lado superior), nunca por fuera.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slay_flutter/widgets/square_progress_border.dart';

void main() {
  const size = Size(256, 256);
  const stroke = 8.0;
  const inset = stroke / 2; // el path corre por la línea media del trazo

  test('progreso chico (0.05): sin diagonal fantasma desde la esquina', () {
    final path = squareProgressPath(
      progress: 0.05,
      size: size,
      strokeWidth: stroke,
    );
    final bounds = path.getBounds();

    // Nada del path puede quedar por fuera del rect del trazo.
    expect(bounds.top, greaterThanOrEqualTo(inset - 0.01),
        reason: 'el path no puede subir por encima del borde superior');
    expect(bounds.left, greaterThanOrEqualTo(inset - 0.01),
        reason: 'el path no puede quedar a la izquierda del borde izquierdo');
    expect(bounds.right, lessThanOrEqualTo(size.width - inset + 0.01));
    expect(bounds.bottom, lessThanOrEqualTo(size.height - inset + 0.01));

    // Empieza en el medio del lado superior: el tramo dibujado va del
    // centro hacia la derecha, pegado al borde superior.
    expect(bounds.top, lessThan(inset + 0.01));
    expect(bounds.left, greaterThan(size.width / 2 - 0.01));
  });

  test('progreso 0.5: llega exactamente a la esquina inferior derecha', () {
    final path = squareProgressPath(
      progress: 0.5,
      size: size,
      strokeWidth: stroke,
    );
    final bounds = path.getBounds();

    // Mitad del perímetro = medio-sup → sup-der → inf-der.
    expect(bounds.right, closeTo(size.width - inset, 0.01));
    expect(bounds.bottom, closeTo(size.height - inset, 0.01));
    expect(bounds.top, closeTo(inset, 0.01));
  });

  test('progreso 0: path vacío', () {
    final path = squareProgressPath(
      progress: 0,
      size: size,
      strokeWidth: stroke,
    );
    expect(path.computeMetrics().isEmpty, isTrue);
  });
}
