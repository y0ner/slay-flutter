-- ──────────────────────────────────────────────────────────────
-- Slay · Row Level Security
-- Cada usuario solo puede ver/modificar sus propios datos.
-- ──────────────────────────────────────────────────────────────

-- Helper: id del usuario actual (equivale a auth.uid() pero cacheado)
create or replace function public.current_user_id()
returns uuid
language sql
stable
as $$
  select auth.uid()
$$;

-- ── profiles ───────────────────────────────────────────────
alter table public.profiles enable row level security;

create policy "Users can view their own profile"
  on public.profiles for select
  using (id = public.current_user_id());

create policy "Users can update their own profile"
  on public.profiles for update
  using (id = public.current_user_id())
  with check (id = public.current_user_id());

-- ── categories ─────────────────────────────────────────────
alter table public.categories enable row level security;

create policy "Users manage their own categories"
  on public.categories for all
  using (user_id = public.current_user_id())
  with check (user_id = public.current_user_id());

-- ── tasks ──────────────────────────────────────────────────
alter table public.tasks enable row level security;

create policy "Users manage their own tasks"
  on public.tasks for all
  using (user_id = public.current_user_id())
  with check (user_id = public.current_user_id());

-- ── subtasks ───────────────────────────────────────────────
alter table public.subtasks enable row level security;

create policy "Users manage subtasks of their own tasks"
  on public.subtasks for all
  using (
    exists (
      select 1 from public.tasks t
      where t.id = subtasks.task_id
        and t.user_id = public.current_user_id()
    )
  )
  with check (
    exists (
      select 1 from public.tasks t
      where t.id = subtasks.task_id
        and t.user_id = public.current_user_id()
    )
  );
