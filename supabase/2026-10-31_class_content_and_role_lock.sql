-- ChemHW migration — 2026-10-31
-- Run once in Supabase: Dashboard → SQL Editor → New query → paste → Run.
-- Safe to re-run.
--
-- 1) class_content: questions + assignments are stored in the database (one row per class code)
--    so students on any device see what the teacher built.
-- 2) Role lock: users can no longer make themselves teachers.

-- ─────────────────────────────────────────────
-- 1) Shared class content
-- ─────────────────────────────────────────────
create table if not exists public.class_content (
  class_code         text primary key,
  questions          jsonb not null default '[]'::jsonb,
  next_question_id   int   not null default 1,
  assignments        jsonb not null default '[]'::jsonb,
  next_assignment_id int   not null default 1,
  updated_at         timestamptz not null default now(),
  updated_by         uuid references public.profiles(id) on delete set null
);
alter table public.class_content enable row level security;

-- Helper: is the signed-in user a teacher? (security definer so it can read profiles inside policies)
create or replace function public.is_teacher() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'teacher');
$$;
revoke all on function public.is_teacher() from public;
grant execute on function public.is_teacher() to authenticated;

drop policy if exists "Signed-in users read class content" on public.class_content;
create policy "Signed-in users read class content" on public.class_content
  for select to authenticated using (true);

drop policy if exists "Teachers insert class content" on public.class_content;
create policy "Teachers insert class content" on public.class_content
  for insert to authenticated with check (public.is_teacher());

drop policy if exists "Teachers update class content" on public.class_content;
create policy "Teachers update class content" on public.class_content
  for update to authenticated using (public.is_teacher()) with check (public.is_teacher());

grant select, insert, update on public.class_content to authenticated;
grant all on public.class_content to service_role;

-- ─────────────────────────────────────────────
-- 2) Role lock
-- ─────────────────────────────────────────────
-- Keep teacher access for the existing primary accounts (the old app promoted these by username).
update public.profiles set role = 'teacher'
  where username in ('teacher', 'admin') and role <> 'teacher';

-- Users may edit only these columns of their own profile — NOT role or class_code.
-- (The co-teacher panel changes roles with the service role key, which is unaffected.)
revoke update on public.profiles from authenticated, anon;
grant update (username, email, first_name, last_name, login_history) on public.profiles to authenticated;

-- Self-created profiles must be students.
drop policy if exists "New profiles must be students" on public.profiles;
create policy "New profiles must be students" on public.profiles
  as restrictive for insert with check (role = 'student');

-- ─────────────────────────────────────────────
-- Check: these accounts have teacher access. Make sure yours is listed!
-- ─────────────────────────────────────────────
select username, email, class_code, role from public.profiles where role = 'teacher' order by username;
