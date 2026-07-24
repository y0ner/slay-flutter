// Test mínimo de humo. Se sustituye con tests reales en fases siguientes.
import 'package:flutter_test/flutter_test.dart';

import 'package:slay_flutter/data/models/category.dart';
import 'package:slay_flutter/data/models/task.dart';

void main() {
  test('TaskStatus detecta completado', () {
    expect(TaskStatus.isDone('Completado'), isTrue);
    expect(TaskStatus.isDone('completado'), isTrue);
    expect(TaskStatus.isDone('Pendiente'), isFalse);
  });

  test('Category roundtrip JSON', () {
    final c = Category(id: 'a', name: 'Trabajo', color: '#4CAF50', sortOrder: 0);
    final j = c.toJson();
    final c2 = Category.fromJson({...j, 'task_count': 5});
    expect(c2.id, 'a');
    expect(c2.taskCount, 5);
  });

  test('Task roundtrip JSON', () {
    final t = Task(
      id: '1', title: 'Hola', status: TaskStatus.pendiente,
      date: DateTime(2026, 7, 23),
    );
    final t2 = Task.fromJson({...t.toJson(), 'subtask_count': 3});
    expect(t2.title, 'Hola');
    expect(t2.subtaskCount, 3);
    expect(t2.isCompleted, isFalse);
  });
}
