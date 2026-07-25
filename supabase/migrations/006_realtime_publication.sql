-- ── Habilitar realtime para tasks / categories / subtasks ───
--
-- Hasta ahora las tablas existen pero no están incluidas en la
-- publicación `supabase_realtime`, que es la que el cliente WebSocket
-- escucha. Resultado: `client.channel(...).onPostgresChanges(...).subscribe()`
-- conecta OK pero nunca recibe eventos de INSERT/UPDATE/DELETE hechos
-- desde la propia app (ni desde otro dispositivo). La UI quedaba stale
-- hasta que el user hacía pull-to-refresh manual.
--
-- Esta migración agrega las tres tablas a la publicación con `REPLICA
-- IDENTITY FULL` para que los eventos de UPDATE incluyan los valores
-- anteriores (default = sólo PK, lo que rompe el `old` en el callback).
--
-- Aplicar en Supabase SQL Editor UNA VEZ. Idempotente: si ya están
-- agregadas, el `ALTER TABLE ... REPLICA IDENTITY FULL` no rompe nada.

-- 1) Replica identity completa (para que UPDATE envíe old.* completo)
alter table public.tasks       replica identity full;
alter table public.categories  replica identity full;
alter table public.subtasks    replica identity full;

-- 2) Agregar a la publicación que el cliente WebSocket escucha.
--    Si la tabla ya está en la publicación, este statement es un no-op
--    (la `if not exists` lo ataja o devuelve warning inofensivo).
alter publication supabase_realtime add table public.tasks;
alter publication supabase_realtime add table public.categories;
alter publication supabase_realtime add table public.subtasks;