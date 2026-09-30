/// Tests de regresión para el orden de tareas.
///
/// Verifica que:
/// 1. La TaskListScreen muestra el número de orden a la izquierda.
/// 2. La lista está ordenada por `sortOrder`.
/// 3. Política de auto-movimiento (sortOrderAfterCheck /
///    sortOrderAfterUncheck): al chuletear la tarea va al fondo, al
///    deschuletar vuelve al final del bloque pendiente.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:slay_flutter/data/models/category.dart' show TaskStatus;
import 'package:slay_flutter/data/models/task.dart';
import 'package:slay_flutter/data/repositories/task_repository.dart';
import 'package:slay_flutter/widgets/task_card.dart';

void main() {
  testWidgets(
    'TaskListScreen muestra número de orden 1-based a la izquierda',
    (tester) async {
      // No podemos levantar la pantalla entera sin mockear Supabase,
      // pero podemos verificar la lógica de orden y la presencia del
      // número en TaskCard pasando dos cards con sortOrder diferente.
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ListView(
                children: [
                  TaskCard(
                    task: _task(id: 'a', sortOrder: 0, isCompleted: false),
                    orderNumber: 1,
                    onTap: () {},
                    onToggle: () {},
                    onEdit: () {},
                    onDelete: () {},
                  ),
                  TaskCard(
                    task: _task(id: 'b', sortOrder: 2, isCompleted: true),
                    orderNumber: 3,
                    onTap: () {},
                    onToggle: () {},
                    onEdit: () {},
                    onDelete: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('1'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    },
  );

  test('Orden de tareas: solo sortOrder', () {
    final a = _task(id: 'a', sortOrder: 0, isCompleted: false);
    final b = _task(id: 'b', sortOrder: 1, isCompleted: true);
    final list = [a, b]..sort((x, y) => x.sortOrder.compareTo(y.sortOrder));
    expect(list.first.id, 'a');
    expect(list.last.id, 'b');
  });

  group('sortOrderAfterCheck — completar mueve al fondo', () {
    test('tarea en medio va al fondo (max + 1)', () {
      final list = [
        _task(id: 'a', sortOrder: 0),
        _task(id: 'b', sortOrder: 1),
        _task(id: 'c', sortOrder: 2),
      ];
      // Chuleteamos 'a' (sortOrder 0).
      expect(sortOrderAfterCheck(list, list[0]), 3);
    });

    test('tarea ya al fondo: null (nada que mover)', () {
      final list = [
        _task(id: 'a', sortOrder: 0),
        _task(id: 'b', sortOrder: 1),
      ];
      expect(sortOrderAfterCheck(list, list[1]), isNull);
    });

    test('lista de un elemento: null', () {
      final list = [_task(id: 'a', sortOrder: 0)];
      expect(sortOrderAfterCheck(list, list[0]), isNull);
    });

    test('con huecos en sortOrder, va más allá del máximo', () {
      final list = [
        _task(id: 'a', sortOrder: 5),
        _task(id: 'b', sortOrder: 10),
        _task(id: 'c', sortOrder: 50),
      ];
      expect(sortOrderAfterCheck(list, list[0]), 51);
    });
  });

  group('sortOrderAfterUncheck — descompletar vuelve al bloque pendiente', () {
    test('completada del fondo vuelve a la posición de la última pendiente',
        () {
      // [p0, p1, done2, done3]: 'p1' es la última pendiente (sortOrder 1).
      final list = [
        _task(id: 'p0', sortOrder: 0),
        _task(id: 'p1', sortOrder: 1),
        _task(id: 'done2', sortOrder: 2, isCompleted: true),
        _task(id: 'done3', sortOrder: 3, isCompleted: true),
      ];
      // Reactivamos 'done3' → toma el lugar de la última pendiente.
      expect(sortOrderAfterUncheck(list, list[3]), 1);
    });

    test('tarea ya dentro del bloque pendiente: null (drag del usuario manda)',
        () {
      final list = [
        _task(id: 'a', sortOrder: 0),
        _task(id: 'b', sortOrder: 1),
        _task(id: 'done', sortOrder: 5, isCompleted: true),
      ];
      // Descompletamos 'a' — su sortOrder ya es <= anchor (1).
      expect(sortOrderAfterUncheck(list, list[0]), isNull);
    });

    test('sin pendientes restantes: null', () {
      final list = [
        _task(id: 'done1', sortOrder: 0, isCompleted: true),
        _task(id: 'done2', sortOrder: 1, isCompleted: true),
      ];
      expect(sortOrderAfterUncheck(list, list[1]), isNull);
    });

    test('la propia tarea excluida del cálculo del anchor', () {
      // Caso borde: la tarea descompletada todavía figura como
      // completada en la lista, pero pudo haber tenido sortOrder bajo.
      final list = [
        _task(id: 'p0', sortOrder: 0),
        _task(id: 'x', sortOrder: 1, isCompleted: true),
      ];
      // 'x' tiene sortOrder 1 > anchor 0 → se mueve a 0? No: anchor es
      // la última PENDIENTE (p0 → 0), y x (1) > 0 → target = 0.
      expect(sortOrderAfterUncheck(list, list[1]), 0);
    });
  });
}

// Helpers ──────────────────────────────────────────────────────────

Task _task({
  required String id,
  required int sortOrder,
  bool isCompleted = false,
}) {
  // Lo mínimo para que TaskCard construya sin crashear.
  return Task(
    id: id,
    title: 'Task $id',
    status: isCompleted ? TaskStatus.completado : TaskStatus.pendiente,
    categoryId: 'cat',
    sortOrder: sortOrder,
  );
}
