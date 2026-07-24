-- ──────────────────────────────────────────────────────────────
-- Slay · auto-set user_id en inserts
-- ──────────────────────────────────────────────────────────────
-- En lugar de pedirle al cliente que envíe `user_id` en cada insert
-- (propenso a errores), un trigger lo rellena desde la sesión actual.
-- ──────────────────────────────────────────────────────────────

create or replace function public.set_current_user_id()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if new.user_id is null then
    new.user_id := auth.uid();
  end if;
  if new.user_id is null then
    raise exception 'No hay sesión activa: no se puede inferir user_id';
  end if;
  return new;
end;
$$;

drop trigger if exists categories_set_user on public.categories;
create trigger categories_set_user
  before insert on public.categories
  for each row execute function public.set_current_user_id();

drop trigger if exists tasks_set_user on public.tasks;
create trigger tasks_set_user
  before insert on public.tasks
  for each row execute function public.set_current_user_id();
