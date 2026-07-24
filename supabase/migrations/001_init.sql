-- ──────────────────────────────────────────────────────────────
-- Slay · Esquema inicial de la base de datos en Supabase
-- Ejecutar en el SQL editor de tu proyecto Supabase.
-- ──────────────────────────────────────────────────────────────

-- Extensión para generar UUIDs
create extension if not exists "pgcrypto";

-- ── profiles ───────────────────────────────────────────────
-- Extiende auth.users con datos de aplicación.
create table if not exists public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  email       text,
  display_name text,
  created_at  timestamptz not null default now()
);

-- Trigger: al crear un usuario en auth.users, crea su profile.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, email, display_name)
  values (new.id, new.email, split_part(new.email, '@', 1));
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ── categories ─────────────────────────────────────────────
create table if not exists public.categories (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles(id) on delete cascade,
  name        text not null,
  color       text not null default '#4CAF50',
  sort_order  int  not null default 0,
  created_at  timestamptz not null default now()
);

create index if not exists categories_user_id_idx on public.categories(user_id);

-- ── tasks ──────────────────────────────────────────────────
-- status: 'Pendiente' | 'Completado' (mismo vocabulario que la app original)
create table if not exists public.tasks (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles(id) on delete cascade,
  category_id uuid references public.categories(id) on delete set null,
  title       text not null,
  status      text not null default 'Pendiente',
  date        timestamptz,           -- fecha de creación / cuándo aparece en "Mi Día"
  reminder    timestamptz,           -- fecha-hora del recordatorio
  sort_order  int  not null default 0,
  created_at  timestamptz not null default now()
);

create index if not exists tasks_user_id_idx   on public.tasks(user_id);
create index if not exists tasks_category_idx  on public.tasks(category_id);
create index if not exists tasks_date_idx      on public.tasks(date);
create index if not exists tasks_reminder_idx  on public.tasks(reminder);

-- ── subtasks ───────────────────────────────────────────────
create table if not exists public.subtasks (
  id          uuid primary key default gen_random_uuid(),
  task_id     uuid not null references public.tasks(id) on delete cascade,
  title       text not null,
  status      text not null default 'Pendiente',
  reminder    timestamptz,
  sort_order  int  not null default 0,
  created_at  timestamptz not null default now()
);

create index if not exists subtasks_task_id_idx on public.subtasks(task_id);
