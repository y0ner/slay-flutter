-- ──────────────────────────────────────────────────────────────
-- Slay · limpiar datos previos mal migrados
-- ──────────────────────────────────────────────────────────────
-- ANTES de re-ejecutar bin/migrate.dart, corré este script para
-- borrar lo que se haya importado con keys incorrectas.
-- ──────────────────────────────────────────────────────────────

-- Borrar solo lo que pertenece al usuario "owner" para no tocar
-- cuentas reales que se hubieran creado en la app.
-- Reemplazá 'OWNER_UUID_AQUÍ' por el UUID de tu usuario.
do $$
declare
  owner_id uuid;
begin
  -- Detecta automáticamente el primer usuario de la organización
  select id into owner_id from auth.users order by created_at asc limit 1;

  if owner_id is null then
    raise notice 'No hay usuarios en auth.users; nada que borrar';
    return;
  end if;

  raise notice 'Borrando datos del usuario %', owner_id;

  delete from public.subtasks
    where task_id in (select id from public.tasks where user_id = owner_id);
  delete from public.tasks where user_id = owner_id;
  delete from public.categories where user_id = owner_id;

  raise notice '✅ Limpieza completa. Ahora corré bin/migrate.dart';
end $$;
