import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slay_flutter/data/models/category.dart';
import 'package:slay_flutter/data/repositories/category_repository.dart';
import 'package:slay_flutter/features/tasks/category_list_screen.dart';

class FakeCategoryRepository implements CategoryRepository {
  List<Category> currentList;
  int reorderCallCount = 0;

  FakeCategoryRepository(this.currentList);

  @override
  Stream<List<Category>> watchCategories() => Stream.value(currentList);

  @override
  Future<List<Category>> getAll() async => currentList;

  @override
  Future<void> reorder(List<Category> ordered) async {
    reorderCallCount++;
    currentList = ordered;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('Reorder + checkmark without drag should NOT save', (tester) async {
    final initialList = [
      const Category(id: '1', name: 'Cat 1', color: '#ff0000', sortOrder: 0),
      const Category(id: '2', name: 'Cat 2', color: '#00ff00', sortOrder: 1),
      const Category(id: '3', name: 'Cat 3', color: '#0000ff', sortOrder: 2),
      const Category(id: '4', name: 'Cat 4', color: '#ffff00', sortOrder: 3),
    ];

    final fakeRepo = FakeCategoryRepository(initialList);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          categoryRepositoryProvider.overrideWithValue(fakeRepo),
          categoriesStreamProvider.overrideWith((ref) => Stream.value(fakeRepo.currentList)),
        ],
        child: const MaterialApp(
          home: CategoryListScreen(),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    // Tap reorder button
    final reorderBtn = find.byIcon(Icons.reorder);
    await tester.tap(reorderBtn);
    await tester.pump();
    await tester.pump();

    // Immediately tap check button WITHOUT any drag
    final checkBtn = find.byIcon(Icons.check);
    await tester.tap(checkBtn);
    await tester.pump();
    await tester.pump();

    // Should NOT have called reorder since no drag happened
    expect(fakeRepo.reorderCallCount, 0,
        reason: 'reorder() should not be called when no drag occurred');
  });
}