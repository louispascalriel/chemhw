-- ChemHW migration — 2026-10-31 (b): lock down who can read student data
-- Run once in Supabase: SQL Editor → + → New snippet → paste → Run. Safe to re-run.
-- Requires the earlier 2026-10-31_class_content_and_role_lock.sql (for is_teacher()).
--
-- After this:
--   • Teachers (profiles.role = 'teacher') can read all profiles and all results.
--   • Students can read only their own profile and their own results.
--   • Not-signed-in visitors can read nothing — sign-in uses email_for_username() instead.

-- 1) Narrow lookup for username sign-in: one username in → that account's email out.
create or replace function public.email_for_username(uname text) returns text
language sql stable security definer set search_path = public as $$
  select email from public.profiles where username = lower(trim(uname)) limit 1;
$$;
revoke all on function public.email_for_username(text) from public;
grant execute on function public.email_for_username(text) to anon, authenticated;

-- 2) Remove EVERY existing read rule on these tables (including any from earlier fixes).
do $$
declare p record;
begin
  for p in
    select policyname, tablename from pg_policies
    where schemaname = 'public' and tablename in ('profiles', 'student_results') and cmd = 'SELECT'
  loop
    execute format('drop policy %I on public.%I', p.policyname, p.tablename);
  end loop;
end $$;

-- 3) The only read rules from now on.
create policy "Users read own profile"     on public.profiles        for select to authenticated using (auth.uid() = id);
create policy "Teachers read all profiles" on public.profiles        for select to authenticated using (public.is_teacher());
create policy "Students read own results"  on public.student_results for select to authenticated using (auth.uid() = student_id);
create policy "Teachers read all results"  on public.student_results for select to authenticated using (public.is_teacher());

-- 4) Not-signed-in visitors get no table access to student data.
revoke select on public.profiles from anon;
revoke select, insert, update, delete on public.student_results from anon;

-- 5) Check.
select case
  when exists (select 1 from pg_policies where schemaname = 'public'
               and tablename in ('profiles', 'student_results') and cmd = 'ALL')
    then 'CHECK NEEDED: an "ALL" rule exists on profiles/student_results — tell Claude'
  else 'OK: only the new read rules apply'
end as status;
