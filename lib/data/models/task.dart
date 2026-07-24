import 'category.dart' show TaskStatus;

class Task {
  final String id;            // uuid de Supabase
  final String title;
  final String status;        // TaskStatus.pendiente | TaskStatus.completado
  final DateTime? date;       // fecha en la que aparece en "Mi Día"
  final String? categoryId;   // uuid de la categoría
  final int sortOrder;
  final DateTime? reminder;   // fecha-hora del recordatorio
  final int subtaskCount;
  final bool isLocal;         // reservado para futuras optimizaciones offline

  const Task({
    required this.id,
    required this.title,
    required this.status,
    this.date,
    this.categoryId,
    this.sortOrder = 0,
    this.reminder,
    this.subtaskCount = 0,
    this.isLocal = false,
  });

  bool get isCompleted => TaskStatus.isDone(status);
  bool get hasSubtasks => subtaskCount > 0;

  factory Task.fromJson(Map<String, dynamic> json) => Task(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        status: json['status'] as String? ?? TaskStatus.pendiente,
        date: _parseDate(json['date']),
        categoryId: json['category_id'] as String?,
        sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
        reminder: _parseDate(json['reminder']),
        subtaskCount: (json['subtask_count'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'status': status,
        'date': date?.toIso8601String(),
        'category_id': categoryId,
        'sort_order': sortOrder,
        'reminder': reminder?.toIso8601String(),
      };

  Task copyWith({
    String? title,
    String? status,
    DateTime? date,
    String? categoryId,
    int? sortOrder,
    DateTime? reminder,
    int? subtaskCount,
  }) =>
      Task(
        id: id,
        title: title ?? this.title,
        status: status ?? this.status,
        date: date ?? this.date,
        categoryId: categoryId ?? this.categoryId,
        sortOrder: sortOrder ?? this.sortOrder,
        reminder: reminder ?? this.reminder,
        subtaskCount: subtaskCount ?? this.subtaskCount,
      );
}

class SubTask {
  final String id;
  final String parentTaskId;
  final String title;
  final String status;
  final int sortOrder;
  final DateTime? reminder;

  const SubTask({
    required this.id,
    required this.parentTaskId,
    required this.title,
    required this.status,
    this.sortOrder = 0,
    this.reminder,
  });

  bool get isCompleted => TaskStatus.isDone(status);

  factory SubTask.fromJson(Map<String, dynamic> json) => SubTask(
        id: json['id'] as String,
        parentTaskId: json['task_id'] as String,
        title: json['title'] as String? ?? '',
        status: json['status'] as String? ?? TaskStatus.pendiente,
        sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
        reminder: _parseDate(json['reminder']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'task_id': parentTaskId,
        'title': title,
        'status': status,
        'sort_order': sortOrder,
        'reminder': reminder?.toIso8601String(),
      };

  SubTask copyWith({String? title, String? status, DateTime? reminder, int? sortOrder}) =>
      SubTask(
        id: id,
        parentTaskId: parentTaskId,
        title: title ?? this.title,
        status: status ?? this.status,
        sortOrder: sortOrder ?? this.sortOrder,
        reminder: reminder ?? this.reminder,
      );
}

DateTime? _parseDate(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  return DateTime.tryParse(v.toString());
}
