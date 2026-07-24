/// Estado de una tarea o subtarea. Mismas constantes que en Sheets.
class TaskStatus {
  static const pendiente = 'Pendiente';
  static const completado = 'Completado';
  static const all = [pendiente, completado];
  static bool isDone(String s) => s.toLowerCase() == completado.toLowerCase();
}

class Category {
  final String id;
  final String name;
  final String color; // hex "#RRGGBB"
  final int sortOrder;
  final int taskCount;

  const Category({
    required this.id,
    required this.name,
    required this.color,
    required this.sortOrder,
    this.taskCount = 0,
  });

  factory Category.fromJson(Map<String, dynamic> json) => Category(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        color: json['color'] as String? ?? '#4CAF50',
        sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
        taskCount: (json['task_count'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'color': color,
        'sort_order': sortOrder,
      };

  Category copyWith({
    String? name,
    String? color,
    int? sortOrder,
    int? taskCount,
  }) =>
      Category(
        id: id,
        name: name ?? this.name,
        color: color ?? this.color,
        sortOrder: sortOrder ?? this.sortOrder,
        taskCount: taskCount ?? this.taskCount,
      );
}
