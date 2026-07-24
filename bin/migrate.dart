// ──────────────────────────────────────────────────────────────
// Slay · script de migración única desde Google Sheets → Supabase
//
// USO:
//   1. Exporta cada hoja de tu Sheet a CSV (Google Sheets →
//      Archivo → Descargar → CSV).
//   2. Crea la carpeta `migration_data/` junto a este script y
//      poné los 3 archivos:
//        migration_data/categorias.csv
//        migration_data/tareas.csv
//        migration_data/subtareas.csv
//   3. Exportá SUPABASE_URL y SUPABASE_SERVICE_ROLE_KEY como
//      variables de entorno (NUNCA commitees la service_role).
//   4. Ejecutá:
//        dart run bin/migrate.dart
// ──────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:http/http.dart' as http;

const _supabaseUrl = 'SUPABASE_URL';
const _serviceKey = 'SUPABASE_SERVICE_ROLE_KEY';
const _ownerEmail = 'OWNER_EMAIL'; // email del usuario al que se le asignan los datos

const _folder = 'migration_data';
const _catsFile = '$_folder/categorias.csv';
const _tasksFile = '$_folder/tareas.csv';
const _subsFile = '$_folder/subtareas.csv';

Future<void> main() async {
  final supabaseUrl = Platform.environment[_supabaseUrl];
  final serviceKey = Platform.environment[_serviceKey];
  final ownerEmail = Platform.environment[_ownerEmail];

  if (supabaseUrl == null || supabaseUrl.isEmpty) {
    stderr.writeln('❌ Falta la variable $_supabaseUrl');
    exit(1);
  }
  if (serviceKey == null || serviceKey.isEmpty) {
    stderr.writeln('❌ Falta la variable $_serviceKey');
    stderr.writeln('   (Project Settings → API → service_role)');
    exit(1);
  }
  if (ownerEmail == null || ownerEmail.isEmpty) {
    stderr.writeln('❌ Falta la variable $_ownerEmail');
    exit(1);
  }

  print('▶ Conectando a $supabaseUrl…');
  final api = SupabaseApi(supabaseUrl, serviceKey);

  // 1) Resolver el UUID del usuario "owner"
  final ownerId = await api.getUserIdByEmail(ownerEmail);
  if (ownerId == null) {
    stderr.writeln('❌ No existe el usuario $ownerEmail. Créalo primero en Supabase Auth.');
    exit(1);
  }
  print('  ✓ Owner: $ownerEmail → $ownerId');

  // 2) Migrar categorías
  final catsFile = File(_catsFile);
  if (!catsFile.existsSync()) {
    stderr.writeln('❌ No existe $_catsFile');
    exit(1);
  }
  final catRows = _readCsv(catsFile);
  print('▶ Migrando ${catRows.length} categorías…');
  final catIdMap = <String, String>{}; // id_viejo → uuid_nuevo
  for (final entry in catRows) {
    final row = entry.fields;
    final oldId = row.getOrEmpty('ID');
    final name = row.getOrEmpty('Nombre');
    final color = row.getOrEmpty('Color').defaultIfEmpty('#4CAF50');
    final order = _safeOrder(row.getOrEmpty('Orden'), 0);
    final newId = await api.insertCategory(
      userId: ownerId, name: name, color: color, sortOrder: order);
    catIdMap[oldId] = newId;
    print('  ✓ $name → $newId');
  }

  // 3) Migrar tareas
  final tasksFile = File(_tasksFile);
  if (!tasksFile.existsSync()) {
    stderr.writeln('❌ No existe $_tasksFile');
    exit(1);
  }
  final taskRows = _readCsv(tasksFile);
  print('▶ Migrando ${taskRows.length} tareas…');
  final taskIdMap = <String, String>{}; // rowIndex (2,3,…) → uuid
  for (var i = 0; i < taskRows.length; i++) {
    final entry = taskRows[i];
    final row = entry.fields;
    final oldRowIndex = entry.rowNumber.toString(); // fila REAL del CSV
    final title = row.getOrEmpty('Título');
    final status = row.getOrEmpty('Estado').defaultIfEmpty('Pendiente');
    final date = _parseDate(row.getOrEmpty('Fecha'));
    final oldCatId = row.getOrEmpty('CategoryID');
    final order = _safeOrder(row.getOrEmpty('Orden'), i);
    final reminder = _parseDate(row.getOrEmpty('Recordatorio'));

    final newCatId = catIdMap[oldCatId];
    final newId = await api.insertTask(
      userId: ownerId,
      categoryId: newCatId,
      title: title,
      status: status,
      date: date,
      reminder: reminder,
      sortOrder: order,
    );
    taskIdMap[oldRowIndex] = newId;
    print('  ✓ [fila $oldRowIndex] $title → $newId');
  }

  // 4) Migrar subtareas
  final subsFile = File(_subsFile);
  if (subsFile.existsSync()) {
    final subRows = _readCsv(subsFile);
    print('▶ Migrando ${subRows.length} subtareas…');
    var orphans = 0;
    for (final entry in subRows) {
      final row = entry.fields;
      // El header de subtareas.csv usa nombres distintos al de tareas.csv
      // (Sheets exportó "ParentTaskID" y "Titulo" sin tilde). Aceptamos
      // ambas variantes para ser tolerantes a re-exports.
      final oldParentRowIndex =
          row.getOrEmpty('ParentTaskID').defaultIfEmpty(row.getOrEmpty('TaskID'));
      final title =
          row.getOrEmpty('Titulo').defaultIfEmpty(row.getOrEmpty('Título'));
      final status = row.getOrEmpty('Estado').defaultIfEmpty('Pendiente');
      final order = _safeOrder(row.getOrEmpty('Orden'), 0);
      final reminder = _parseDate(row.getOrEmpty('Recordatorio'));

      if (oldParentRowIndex.isEmpty) {
        orphans++;
        print('  ⚠ Subtarea sin padre definido: "$title"');
        continue;
      }

      final newParentId = taskIdMap[oldParentRowIndex];
      if (newParentId == null) {
        orphans++;
        print('  ⚠ Subtarea huérfana: "$title" (padre fila $oldParentRowIndex)');
        continue;
      }
      await api.insertSubtask(
        taskId: newParentId,
        title: title,
        status: status,
        reminder: reminder,
        sortOrder: order,
      );
      print('  ✓ $title');
    }
    if (orphans > 0) {
      print('  ⚠ $orphans subtareas sin padre (filas del CSV con id inexistente)');
    }
  } else {
    print('⏭  Sin subtareas (no existe $_subsFile)');
  }

  print('\n✅ Migración completada.');
}

// ── Helpers ──────────────────────────────────────────────────

/// Límite seguro para columnas `int` (Postgres `integer` = int32).
const int _int32Max = 2147483647;

/// Devuelve una lista de (númeroDeFilaOriginal, mapaDeColumnas) para cada
/// fila de datos. Usa el paquete `csv` — maneja correctamente campos
/// entre comillas, comas dentro del valor y saltos de línea.
///
/// El número de fila es el de la línea física en el archivo
/// (la primera línea de datos es 2 porque la 1 es el encabezado).
/// Las filas totalmente vacías se descartan.
List<({int rowNumber, Map<String, String> fields})> _readCsv(File f) {
  final raw = f.readAsStringSync();
  final allRows = const CsvToListConverter(
    eol: '\n',
    shouldParseNumbers: false,
    allowInvalid: true,
  ).convert(raw);

  if (allRows.isEmpty) return const [];

  final headers = allRows.first.map((c) => c.toString().trim()).toList();
  final result = <({int rowNumber, Map<String, String> fields})>[];

  for (var i = 1; i < allRows.length; i++) {
    final rowNumber = i + 1; // 1 = header
    final cells = allRows[i].map((c) => c.toString().trim()).toList();

    // Saltar filas totalmente vacías
    if (cells.every((c) => c.isEmpty)) continue;

    // Mapear header → valor
    final map = <String, String>{};
    for (var c = 0; c < headers.length; c++) {
      map[headers[c]] = c < cells.length ? cells[c] : '';
    }
    result.add((rowNumber: rowNumber, fields: map));
  }
  return result;
}

/// Devuelve el valor de la columna o string vacío si no existe.
String _getOrEmpty(Map<String, String> row, String column) =>
    row[column]?.trim() ?? '';

extension _RowExt on Map<String, String> {
  String getOrEmpty(String column) => _getOrEmpty(this, column);
}

extension _StringExt on String {
  /// Si el string está vacío (o solo whitespace), devuelve `fallback`.
  String defaultIfEmpty(String fallback) =>
      trim().isEmpty ? fallback : this;
}

/// Parsea un entero y lo clampa al rango int32 de Postgres.
/// Si el valor es inválido o se pasa del rango, usa `fallback`.
int _safeOrder(String raw, int fallback) {
  final v = int.tryParse(raw);
  if (v == null) return fallback;
  if (v < 0) return 0;
  if (v > _int32Max) return _int32Max;
  return v;
}

DateTime? _parseDate(String s) {
  if (s.isEmpty) return null;
  // Acepta "dd/MM/yyyy HH:mm" o ISO 8601
  try {
    return DateTime.parse(s);
  } catch (_) {}
  final m = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})\s*(\d{1,2}):(\d{2})?')
      .firstMatch(s);
  if (m == null) return null;
  return DateTime(
    int.parse(m.group(3)!),
    int.parse(m.group(2)!),
    int.parse(m.group(1)!),
    int.parse(m.group(4) ?? '0'),
    int.parse(m.group(5) ?? '0'),
  );
}

// ── Cliente HTTP de Supabase ──────────────────────────────────

class SupabaseApi {
  SupabaseApi(this.baseUrl, this.serviceKey);
  final String baseUrl;
  final String serviceKey;

  Map<String, String> get _headers => {
        'apikey': serviceKey,
        'Authorization': 'Bearer $serviceKey',
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
      };

  Future<String?> getUserIdByEmail(String email) async {
    final url = Uri.parse(
        '$baseUrl/auth/v1/admin/users?email=${Uri.encodeQueryComponent(email)}');
    final res = await http.get(url, headers: _headers);
    if (res.statusCode != 200) {
      stderr.writeln('Error buscando usuario: ${res.body}');
      return null;
    }
    // Supabase >= 2.x devuelve { "users": [...], "aud": "authenticated" }.
    // Versiones viejas devolvían el array directo. Soportamos ambos.
    final body = jsonDecode(res.body);
    final list = body is List
        ? body
        : (body as Map<String, dynamic>)['users'] as List? ?? const [];
    if (list.isEmpty) return null;
    return list.first['id'] as String;
  }

  Future<String> insertCategory({
    required String userId,
    required String name,
    required String color,
    required int sortOrder,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/rest/v1/categories'),
      headers: _headers,
      body: jsonEncode({
        'user_id': userId,
        'name': name,
        'color': color,
        'sort_order': sortOrder,
      }),
    );
    _check(res);
    return (jsonDecode(res.body) as List).first['id'] as String;
  }

  Future<String> insertTask({
    required String userId,
    String? categoryId,
    required String title,
    required String status,
    DateTime? date,
    DateTime? reminder,
    required int sortOrder,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/rest/v1/tasks'),
      headers: _headers,
      body: jsonEncode({
        'user_id': userId,
        'category_id': categoryId,
        'title': title,
        'status': status,
        'date': date?.toIso8601String(),
        'reminder': reminder?.toIso8601String(),
        'sort_order': sortOrder,
      }),
    );
    _check(res);
    return (jsonDecode(res.body) as List).first['id'] as String;
  }

  Future<void> insertSubtask({
    required String taskId,
    required String title,
    required String status,
    DateTime? reminder,
    required int sortOrder,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/rest/v1/subtasks'),
      headers: _headers,
      body: jsonEncode({
        'task_id': taskId,
        'title': title,
        'status': status,
        'reminder': reminder?.toIso8601String(),
        'sort_order': sortOrder,
      }),
    );
    _check(res);
  }

  void _check(http.Response res) {
    if (res.statusCode >= 300) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
  }
}
