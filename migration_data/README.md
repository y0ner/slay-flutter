# Migración desde Google Sheets

1. Exporta cada hoja de tu Google Sheet a CSV (Archivo → Descargar → CSV):
   - Hoja `Categorias` → `categorias.csv`
   - Hoja `Tareas` → `tareas.csv`
   - Hoja `Subtareas` → `subtareas.csv`
2. Obtén tu `service_role` key en Supabase (Project Settings → API)
3. Ejecuta:
   ```
   export SUPABASE_URL=https://xxxx.supabase.co
   export SUPABASE_SERVICE_ROLE_KEY=eyJhbGci...
   export OWNER_EMAIL=tu@email.com
   dart run bin/migrate.dart
   ```
