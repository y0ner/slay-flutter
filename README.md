# Slay · Flutter

Aplicación de gestión de tareas diarias, construida con **Flutter** y respaldada por **Supabase** (Postgres + Auth + Realtime).

Un único código base para **Android · Linux · Windows**, sustituyendo los antiguos proyectos
[`Slay`](../Slay) (Android Kotlin/Jetpack Compose) y [`Slay-Desktop`](../Slay-Desktop) (Compose Multiplatform Desktop).

---

## ✨ Features

- 🗓️ **Mi Día** — tareas cuya fecha o recordatorio caen hoy
- 🗂️ **Categorías** con color personalizado y reordenamiento
- ⏱️ **Pomodoro** con tarea preseleccionable desde cualquier tarjeta
- 📅 **Calendario** mensual/semanal con `table_calendar`
- 🔔 **Recordatorios locales** vía `flutter_local_notifications`
- 🌓 **Tema claro/oscuro/sistema** con persistencia
- ☁️ **Realtime sync** entre dispositivos con la misma cuenta Supabase
- 📡 **Modo offline con cola de sync** (Drift SQLite) — agrega/edita/borra sin internet, se sube al reconectarse
- 👆 **TaskCard enriquecido**: swipe → toggle/edit, badges de categoría/fecha/subtareas, copiar al portapapeles, enviar a Focus

---

## 📁 Estructura

```
slay-flutter/
├── android/                       # Permisos Android (notif, red, alarms)
├── linux/                         # Runner nativo Linux
├── windows/                       # Runner nativo Windows
├── lib/
│   ├── main.dart                  # Entry: Supabase, timezone, locale
│   ├── app.dart                   # MaterialApp.router + NetworkStatusPill
│   ├── core/
│   │   ├── router/app_router.dart       # GoRouter + auth guard
│   │   ├── supabase/supabase_config.dart
│   │   └── theme/{slay_theme,theme_controller}.dart
│   ├── data/
│   │   ├── local/app_database.dart      # Drift schema (pending_ops, cache)
│   │   ├── sync/                        # ConnectivityProvider, SyncService, SyncState
│   │   ├── models/{task,category}.dart  # fromJson/toJson manual
│   │   └── repositories/                # TaskRepository, CategoryRepository
│   ├── features/                        # Una carpeta por pantalla
│   ├── notifications/local_notifications.dart
│   └── widgets/
│       ├── task_card.dart               # Enriquecido con swipe + badges
│       ├── network_status_pill.dart     # Pill animado offline/syncing/synced
│       ├── edit_task_dialog.dart
│       └── delete_task_dialog.dart
├── bin/migrate.dart                    # Script one-shot CSV → Supabase
├── supabase/migrations/                 # 001, 002, 004, 005
├── migration_data/                      # CSVs exportados de Sheets
└── run.sh                               # Wrapper con --dart-define
```

---

## ⚙️ Setup (una sola vez)

### 1. Instalar Flutter

```bash
# Snap (Ubuntu/Mint)
sudo snap install flutter --classic
# o descarga manual en https://docs.flutter.dev/get-started/install/linux
```

```bash
# Dependencias nativas para build Linux
sudo apt install clang cmake ninja-build libgtk-3-dev
```

### 2. Clonar e instalar dependencias

```bash
cd ~/Desktop/Projects
git clone <repo-url> slay-flutter
cd slay-flutter
flutter pub get
```

### 3. Generar código (Drift, Freezed, JSON)

```bash
dart run build_runner build --delete-conflicting-outputs
```

### 4. Configurar Supabase

1. Crear proyecto en [supabase.com](https://supabase.com)
2. **SQL editor** → correr en orden:
   - `supabase/migrations/001_init.sql`     → tablas + triggers
   - `supabase/migrations/002_rls.sql`      → RLS por usuario
   - `supabase/migrations/004_auto_user_id.sql` → trigger BEFORE INSERT para `user_id`
3. **Project Settings → API** → copiar:
   - `URL`            → `SUPABASE_URL`
   - `anon` key       → `SUPABASE_ANON_KEY` (pública, puede ir en el código)
   - `service_role`   → `SUPABASE_SERVICE_ROLE_KEY` (SOLO para migración, **nunca** commitear)
4. Crear un usuario en **Authentication → Users** (será el "owner" de los datos migrados)

### 5. Crear `.env` local (opcional)

```bash
cat > .env <<'EOF'
SUPABASE_URL=https://xxxxx.supabase.co
SUPABASE_ANON_KEY=eyJhbGciOi...
# SUPABASE_SERVICE_ROLE_KEY=...   # solo para migración, no commitear
EOF
```

`run.sh` y `bin/migrate.dart` lo leen automáticamente.

---

## 🚀 Correr la app

### Linux desktop

```bash
cp .env.example .env       # completar claves
./run.sh linux
```

(equivalente a `flutter run -d linux --dart-define=SUPABASE_URL=...`)

### Android (celular USB)

```bash
# 1. Habilitar depuración USB en el celular
#    Ajustes → Acerca del teléfono → Toca "Número de compilación" 7 veces
#    Ajustes → Opciones de desarrollador → Depuración USB → ON
# 2. Conectar por USB y confiar en la PC
# 3. Verificar
flutter devices
# 4. Instalar y correr (debug)
./run.sh android
# o equivalente:
# flutter run -d <device-id> \
#   --dart-define=SUPABASE_URL=https://xxxxx.supabase.co \
#   --dart-define=SUPABASE_ANON_KEY=eyJhbGc...
```

> La primera vez tarda ~5-10 min (descarga Gradle deps). Builds subsiguientes son segundos.

#### Requisitos Android ya aplicados en este proyecto

- **AGP 8.2.1 + Kotlin 1.9.22** en `android/settings.gradle` (>=8.2.1 requerido por JDK 21)
- **Core library desugaring** habilitado en `android/app/build.gradle` (`flutter_local_notifications` usa `java.time.*`):
  ```gradle
  compileOptions { coreLibraryDesugaringEnabled true ... }
  dependencies { coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.0.4' }
  ```
- Permisos de notificaciones, alarms y red en `AndroidManifest.xml`

### Build APK release (instalable sin `flutter`)

```bash
flutter build apk --release \
  --dart-define=SUPABASE_URL=https://xxxxx.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJhbGc...
# APK queda en build/app/outputs/flutter-apk/app-release.apk
```

Instalar en celular con `adb install build/app/outputs/flutter-apk/app-release.apk` o pasando el `.apk` al teléfono.

### Windows

```bash
flutter run -d windows \
  --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
```

---

## 🔄 Migrar datos desde Google Sheets (una sola vez)

### 1. Exportar CSVs

Google Sheets → **Archivo → Descargar → CSV** para cada hoja:
- `categorias` → `migration_data/categorias.csv`
- `tareas`     → `migration_data/tareas.csv`
- `subtareas`  → `migration_data/subtareas.csv`

### 2. Configurar env vars y correr

```bash
export SUPABASE_URL='https://xxxxx.supabase.co'
export SUPABASE_SERVICE_ROLE_KEY='eyJhbGc...'   # Settings → API → service_role
export OWNER_EMAIL='tu@email.com'                # el usuario creado en Supabase Auth

dart run bin/migrate.dart
```

Salida esperada:
```
▶ Migrando 10 categorías…
▶ Migrando 58 tareas…
▶ Migrando 45 subtareas…
✅ Migración completada.
```

### 3. Si algo falla a mitad de camino

Limpiá lo importado y reintentá:

```sql
-- supabase/migrations/005_reset_and_remigrate.sql
-- corre en SQL editor; detecta el primer user y borra sus datos
```

Después re-ejecutá `dart run bin/migrate.dart`.

---

## 🧪 Tests

```bash
flutter test
```

3 tests cubren: `TaskStatus.isDone`, `Category.fromJson/toJson`, `Task.fromJson/toJson`.

---

## 🔧 Troubleshooting

| Síntoma | Solución |
|---|---|
| `SocketException: Failed host lookup` en `migrate.dart` | Verificá `SUPABASE_URL` (no `xxxxx.supabase.co`) |
| `22003 numeric value out of range` | Bug viejo del parser CSV: usá la última versión de `bin/migrate.dart` (paquete `csv`, no `split(',')`) |
| Subtareas "huérfanas" | Filas vacías en `tareas.csv`. Esperable, no es bug. |
| Pill rojo permanente | Sin internet. La cola se procesa al reconectarse. |
| `JdkImageTransform` / `core-for-system-modules.jar` | AGP < 8.2.1 + JDK 21. Subir AGP en `android/settings.gradle` |
| `requires core library desugaring to be enabled` | Agregar `coreLibraryDesugaringEnabled true` + `desugar_jdk_libs:2.0.4` a `android/app/build.gradle` |
| `BUILD FAILED` en Android por SDK | `flutter doctor` y aceptar licencias: `flutter doctor --android-licenses` |
| Notificaciones no suenan | Settings → Apps → Slay → Notificaciones → ON (Android 13+) |

---

## 🌿 Workflow de desarrollo

Por convención, cada corrección / feature va en una **rama paralela a `main`**
y se valida antes de mergear (sin Pull Requests, dado que es app personal).

Ver [CONTRIBUTING.md](CONTRIBUTING.md) para el detalle completo. Resumen:

```bash
git checkout -b fix/<descripcion>   # rama desde main
# ... cambios, pruebas en el celu ...
git commit -m "fix: ..."
git checkout main
git merge --no-ff fix/<descripcion> # merge directo, sin PR
git push
```

Tipos de rama: `fix/`, `feat/`, `chore/`, `docs/`.

---

## 📋 Roadmap

- [x] Migración Kotlin → Flutter con Supabase
- [x] Modo offline (cola `pending_ops` con Drift)
- [x] TaskCard enriquecido (swipe, badges, copy)
- [x] Reorder de categorías con flechas ↑/↓
- [ ] Hidratar `cached_tasks` / `cached_categories` para que la app arranque sin red
- [ ] Drag-to-reorder en listas de tareas
- [ ] Tema personalizado por categoría (color de fondo dinámico)
- [ ] Notificaciones en Windows
- [ ] PWA/Web
