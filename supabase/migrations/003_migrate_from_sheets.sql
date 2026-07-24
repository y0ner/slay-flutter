-- ──────────────────────────────────────────────────────────────
-- Slay · Script de migración única desde Google Sheets
-- ──────────────────────────────────────────────────────────────
-- INSTRUCCIONES:
--   1. Exporta cada hoja de tu Google Sheet a CSV.
--   2. Crea un usuario temporal en Supabase Auth (será el "owner"
--      inicial de los datos importados). Guarda su UUID.
--   3. Reemplaza 'PASTE-USER-UUID-HERE' abajo por ese UUID.
--   4. Reemplaza el contenido de las CTE `csv_*` con tus CSV
--      (o importa primero con `COPY categories FROM ...`).
--   5. Ejecuta este script UNA sola vez.
-- ──────────────────────────────────────────────────────────────

do $$
declare
  owner_id uuid := 'PASTE-USER-UUID-HERE'::uuid;
  cat_record record;
  new_cat_id uuid;
begin
  -- ── Categorías ─────────────────────────────────────────
  -- CSV esperado (sin encabezado):
  --   id_excel,nombre,color,orden
  -- El id_excel puede ser el timestamp viejo; lo regeneramos.
  for cat_record in
    select * from (
      values
        -- ('mi-id-viejo-1', 'Trabajo',  '#4CAF50', 0),
        -- ('mi-id-viejo-2', 'Personal', '#2196F3', 1)
    ) as t(id_excel text, nombre text, color text, orden int)
  loop
    insert into public.categories (user_id, name, color, sort_order)
    values (owner_id, cat_record.nombre, cat_record.color, cat_record.orden)
    returning id into new_cat_id;

    -- (Opcional) guarda mapeo id_excel → uuid para usarlo en tasks
    raise notice 'Categoría % → %', cat_record.nombre, new_cat_id;
  end loop;

  -- ── Tareas ─────────────────────────────────────────────
  -- CSV esperado:
  --   titulo, status, fecha, categoria_id_excel, orden, reminder
  -- Esta parte requiere mapear categoria_id_excel → uuid. Lo más
  -- simple es: importar primero las categorías en una tabla
  -- temporal, y luego hacer join. Aquí va el patrón simplificado:
  --
  --   insert into public.tasks (user_id, category_id, title, status, date, reminder, sort_order)
  --   select owner_id,
  --          (select id from public.categories where user_id = owner_id and name = t.categoria_nombre),
  --          t.titulo, t.status, t.fecha::timestamptz, t.reminder::timestamptz, t.orden
  --   from (values (...)) as t(titulo, status, fecha, categoria_nombre, orden, reminder);

  raise notice 'Migración completada.';
end $$;
